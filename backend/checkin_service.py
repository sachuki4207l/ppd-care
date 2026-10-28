import json
from datetime import datetime, timezone

from flask import jsonify

if __package__:
    from .config import FEATURE_NAMES
    from .database import SessionLocal
    from .models import PersonalCheckin, User
    from .prediction_service import _json_error, predict_risk
else:
    from config import FEATURE_NAMES
    from database import SessionLocal
    from models import PersonalCheckin, User
    from prediction_service import _json_error, predict_risk


QUESTION_TO_FEATURE = {
    "angry": "Angry after latest child birth",
    "relax": "Relax/sleep when the newborn is asleep",
    "trust": "Trust and share feelings",
    "husband_rel": "Relationship with husband",
    "inlaw_rel": "Relationship with the in-laws",
    "support": "Recieved Support",
    "motherhood": "Feeling about motherhood",
}

QUESTION_CHOICES = {
    "angry": {"Yes": 1, "No": 0},
    "relax": {"Yes": 1, "No": 0},
    "trust": {"Yes": 1, "No": 0},
    "husband_rel": {"Poor": 0, "Bad": 1, "Neutral": 2, "Friendly": 3, "Good": 4},
    "inlaw_rel": {"Poor": 0, "Bad": 1, "Neutral": 2, "Friendly": 3, "Good": 4},
    "support": {"Low": 0, "Medium": 1, "High": 2},
    "motherhood": {"Sad": 0, "Neutral": 1, "Happy": 2},
}

DEFAULTS = {
    "Education Level": 3,
    "Current monthly income": 0,
    "Husband’s monthly income": 3,
    "Total children": 0,
    "Family type": 1,
    "Relationship with the newborn": 2,
    "Relationship between father and newborn": 2,
    "Major changes or losses during pregnancy": 0,
    "Abuse": 1,
    "Fear of pregnancy": 1,
    "Diseases during pregnancy": 0,
    "Gender of newborn": 1,
    "Birth compliancy": 0,
    "Breastfeed": 1,
    "Worry about newborn": 1,
    "Depression before pregnancy (PHQ2)": 0,
    "Depression during pregnancy (PHQ2)": 0,
    "Occupation before latest pregnancy_Housewife": 0,
    "Occupation before latest pregnancy_Student": 0,
    "Feeling for regular activities_Normal": 0,
    "Need for Support_Unknown": 0,
}

DEFAULT_FEATURE_NAMES = list(DEFAULTS.keys())
LOCAL_DEVICE_NAME = "local_device"
SUCCESS_MESSAGE = (
    "Talking to someone you trust or a healthcare professional could help. "
    "This check-in is not a diagnosis and cannot rule anything out."
)


def _validate_payload(payload):
    if not isinstance(payload, dict):
        return None, _json_error("Request body must be a JSON object.")

    expected_keys = tuple(QUESTION_CHOICES)
    payload_keys = set(payload)
    expected_set = set(expected_keys)
    if payload_keys != expected_set:
        missing = [key for key in expected_keys if key not in payload]
        extra = [key for key in payload if key not in expected_set]
        if missing and extra:
            return None, _json_error(
                f"Missing keys: {missing}; unexpected keys: {extra}."
            )
        if missing:
            return None, _json_error(f"Missing keys: {missing}.")
        return None, _json_error(f"Unexpected keys: {extra}.")

    validated = {}
    for key in expected_keys:
        value = payload[key]
        if not isinstance(value, str):
            return None, _json_error(f"Invalid value for '{key}': expected a string.")
        allowed = QUESTION_CHOICES[key]
        if value not in allowed:
            expected_values = "/".join(allowed)
            return None, _json_error(
                f"Invalid value for '{key}': expected one of {expected_values}."
            )
        validated[key] = value

    return validated, None


def _build_feature_vector(answers):
    question_feature_names = set(QUESTION_TO_FEATURE.values())
    default_feature_names = set(DEFAULTS)
    full_feature_names = set(FEATURE_NAMES)

    if question_feature_names | default_feature_names != full_feature_names:
        raise AssertionError(
            "Check-in question features and defaults do not cover config.FEATURE_NAMES exactly."
        )
    if len(question_feature_names & default_feature_names) != 0:
        raise AssertionError("Check-in question features overlap defaulted features.")
    if len(question_feature_names) != 7:
        raise AssertionError("Expected exactly seven personal question features.")
    if len(default_feature_names) != 21:
        raise AssertionError("Expected exactly twenty-one defaulted features.")
    if len(set(FEATURE_NAMES)) != len(FEATURE_NAMES):
        raise AssertionError("FEATURE_NAMES contains duplicates.")

    feature_values = {}
    for key, feature_name in QUESTION_TO_FEATURE.items():
        feature_values[feature_name] = QUESTION_CHOICES[key][answers[key]]
    for feature_name, value in DEFAULTS.items():
        feature_values[feature_name] = value

    ordered = [feature_values[name] for name in FEATURE_NAMES]
    return ordered


def _json_success(checkin_id):
    return jsonify(
        {
            "checkin_id": checkin_id,
            "message": SUCCESS_MESSAGE,
        }
    )


def submit_checkin(payload):
    answers, error = _validate_payload(payload)
    if error is not None:
        return error

    feature_vector = _build_feature_vector(answers)
    try:
        result = predict_risk(feature_vector)
    except Exception:
        return _json_error("Prediction service unavailable.", 500)

    timestamp = datetime.now(timezone.utc).isoformat()
    default_names_json = json.dumps(DEFAULT_FEATURE_NAMES, separators=(",", ":"))
    answers_json = json.dumps(answers, separators=(",", ":"))
    top_factors_json = json.dumps([], separators=(",", ":"))

    try:
        with SessionLocal.begin() as session:
            profile = (
                session.query(User)
                .filter(User.name == LOCAL_DEVICE_NAME)
                .order_by(User.created_at)
                .first()
            )
            if profile is None:
                profile = User(name=LOCAL_DEVICE_NAME)
                session.add(profile)
                session.flush()

            checkin = PersonalCheckin(
                user_id=profile.id,
                timestamp=timestamp,
                answers=answers_json,
                model_version_id=result["model_version"],
                probability=float(result["probability"]),
                elevated_risk=bool(result["prediction"] == 1),
                top_factors=top_factors_json,
                used_defaults_for=default_names_json,
            )
            session.add(checkin)
            session.flush()
            checkin_id = checkin.id
    except Exception:
        return _json_error("Check-in could not be saved.", 500)

    return _json_success(checkin_id)
