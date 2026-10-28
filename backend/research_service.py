import json
from datetime import datetime, timezone
from uuid import uuid4

from flask import jsonify

if __package__:
    from .config import FEATURE_NAMES
    from .database import SessionLocal
    from .models import ResearchParticipant, ResearchSubmission
    from .prediction_service import _json_error
else:
    from config import FEATURE_NAMES
    from database import SessionLocal
    from models import ResearchParticipant, ResearchSubmission
    from prediction_service import _json_error

CONSENT_VERSIONS = {"v1"}
RESEARCH_SOURCE = "dev_test"

# Explicit per-feature maximum allowed integer ranges (0..max) for config.FEATURE_NAMES
# (all 27 features excluding Abuse)
FEATURE_MAX_VALUES = {
    "Education Level": 3,
    "Current monthly income": 5,
    "Husband’s monthly income": 4,
    "Total children": 2,
    "Family type": 1,
    "Relationship with the in-laws": 4,
    "Relationship with husband": 4,
    "Relationship with the newborn": 3,
    "Relationship between father and newborn": 3,
    "Feeling about motherhood": 2,
    "Recieved Support": 2,
    "Major changes or losses during pregnancy": 1,
    "Trust and share feelings": 1,
    "Fear of pregnancy": 1,
    "Diseases during pregnancy": 2,
    "Gender of newborn": 1,
    "Birth compliancy": 1,
    "Breastfeed": 1,
    "Worry about newborn": 1,
    "Relax/sleep when the newborn is asleep": 1,
    "Angry after latest child birth": 1,
    "Depression before pregnancy (PHQ2)": 1,
    "Depression during pregnancy (PHQ2)": 1,
    "Occupation before latest pregnancy_Housewife": 1,
    "Occupation before latest pregnancy_Student": 1,
    "Feeling for regular activities_Normal": 1,
    "Need for Support_Unknown": 1,
}

EXPECTED_FEATURE_NAMES_SUBMIT = tuple(
    name for name in FEATURE_NAMES if name != "Abuse"
)
assert len(EXPECTED_FEATURE_NAMES_SUBMIT) == 27
assert set(EXPECTED_FEATURE_NAMES_SUBMIT) == set(FEATURE_MAX_VALUES.keys())

SUBMISSION_SUCCESS_MESSAGE = "Thank you for contributing to postpartum depression research."


def record_consent(payload):
    if not isinstance(payload, dict):
        return _json_error("Request body must be a JSON object.")

    expected_keys = {"consent_given", "consent_version"}
    payload_keys = set(payload.keys())
    if payload_keys != expected_keys:
        missing = [k for k in sorted(expected_keys) if k not in payload_keys]
        extra = [k for k in sorted(payload_keys) if k not in expected_keys]
        if missing and extra:
            return _json_error(
                f"Missing keys: {missing}; unexpected keys: {extra}."
            )
        if missing:
            return _json_error(f"Missing keys: {missing}.")
        return _json_error(f"Unexpected keys: {extra}.")

    consent_given_val = payload["consent_given"]
    # Must be JSON literal true; reject False, "true", 1, null, etc.
    if consent_given_val is not True:
        return _json_error("consent_given must be boolean true.")

    version_val = payload["consent_version"]
    if not isinstance(version_val, str) or version_val not in CONSENT_VERSIONS:
        allowed = sorted(list(CONSENT_VERSIONS))
        return _json_error(
            f"Invalid consent_version: expected one of {allowed}."
        )

    research_id = str(uuid4())
    now_iso = datetime.now(timezone.utc).isoformat()

    try:
        with SessionLocal.begin() as session:
            participant = ResearchParticipant(
                research_id=research_id,
                consent_given=True,
                consent_version=version_val,
                consent_timestamp=now_iso,
                withdrawn=False,
                withdrawn_at=None,
            )
            session.add(participant)
            session.flush()
    except Exception:
        return _json_error("Research consent could not be recorded.", 500)

    return (
        jsonify(
            {
                "research_id": research_id,
            }
        ),
        201,
    )


def _validate_submit_payload(payload):
    if not isinstance(payload, dict):
        return None, _json_error("Request body must be a JSON object.")

    expected_keys = {"research_id", "features", "abuse_reworded", "epds_answers"}
    payload_keys = set(payload.keys())
    if payload_keys != expected_keys:
        missing = [k for k in sorted(expected_keys) if k not in payload_keys]
        extra = [k for k in sorted(payload_keys) if k not in expected_keys]
        if missing and extra:
            return None, _json_error(
                f"Missing keys: {missing}; unexpected keys: {extra}."
            )
        if missing:
            return None, _json_error(f"Missing keys: {missing}.")
        return None, _json_error(f"Unexpected keys: {extra}.")

    # Validate research_id type
    research_id = payload["research_id"]
    if not isinstance(research_id, str) or not research_id.strip():
        return None, _json_error("Invalid value for 'research_id': expected a non-empty string.")

    # Validate features object
    features_obj = payload["features"]
    if not isinstance(features_obj, dict):
        return None, _json_error("Invalid value for 'features': expected a JSON object.")

    features_keys = set(features_obj.keys())
    expected_f_keys = set(EXPECTED_FEATURE_NAMES_SUBMIT)
    if features_keys != expected_f_keys:
        f_missing = [k for k in EXPECTED_FEATURE_NAMES_SUBMIT if k not in features_keys]
        f_extra = [k for k in sorted(features_keys) if k not in expected_f_keys]
        if f_missing and f_extra:
            return None, _json_error(
                f"Missing features: {f_missing}; unexpected features: {f_extra}."
            )
        if f_missing:
            return None, _json_error(f"Missing features: {f_missing}.")
        return None, _json_error(f"Unexpected features: {f_extra}.")

    validated_features = {}
    for name in EXPECTED_FEATURE_NAMES_SUBMIT:
        val = features_obj[name]
        # Must be plain int; reject bool, float, str, null
        if isinstance(val, bool) or not isinstance(val, int):
            return None, _json_error(
                f"Invalid value for feature '{name}': expected an integer."
            )
        max_val = FEATURE_MAX_VALUES[name]
        if val < 0 or val > max_val:
            return None, _json_error(
                f"Invalid value for feature '{name}': expected integer between 0 and {max_val}."
            )
        validated_features[name] = val

    # Validate abuse_reworded
    abuse_reworded = payload["abuse_reworded"]
    if isinstance(abuse_reworded, bool) or not isinstance(abuse_reworded, int):
        return None, _json_error("Invalid value for 'abuse_reworded': expected integer 0 or 1.")
    if abuse_reworded not in (0, 1):
        return None, _json_error("Invalid value for 'abuse_reworded': expected integer 0 or 1.")

    # Validate epds_answers: list of exactly 10 ints, each 0..3
    epds_answers = payload["epds_answers"]
    if not isinstance(epds_answers, list):
        return None, _json_error("Invalid value for 'epds_answers': expected a list of 10 integers.")
    if len(epds_answers) != 10:
        return None, _json_error(
            f"Invalid value for 'epds_answers': expected exactly 10 items, got {len(epds_answers)}."
        )

    validated_epds_positions = []
    for idx, ans in enumerate(epds_answers):
        if isinstance(ans, bool) or not isinstance(ans, int):
            return None, _json_error(
                f"Invalid value for EPDS item at index {idx}: expected an integer between 0 and 3."
            )
        if ans < 0 or ans > 3:
            return None, _json_error(
                f"Invalid value for EPDS item at index {idx}: expected an integer between 0 and 3."
            )
        validated_epds_positions.append(ans)

    validated = {
        "research_id": research_id,
        "features": validated_features,
        "abuse_reworded": abuse_reworded,
        "epds_positions": validated_epds_positions,
    }
    return validated, None


def _score_epds(positions):
    """
    Score 10 EPDS responses.
    Positions are 0..3 (printed option position).
    Forward items: items 1, 2, 4 (0-indexed: 0, 1, 3) -> points = position
    Reverse items: items 3, 5, 6, 7, 8, 9, 10 (0-indexed: 2, 4, 5, 6, 7, 8, 9) -> points = 3 - position
    total = sum of 10 points (0..30)
    label = 1 if total >= 13 else 0
    crisis_flag = (item 10 points > 0)
    """
    points = []
    for idx, pos in enumerate(positions):
        # 1-indexed item number is idx + 1
        item_num = idx + 1
        if item_num in (1, 2, 4):
            pts = pos
        else:
            pts = 3 - pos
        points.append(pts)

    total = sum(points)
    label = 1 if total >= 13 else 0
    item_10_points = points[9]
    crisis_flag = bool(item_10_points > 0)
    return points, total, label, crisis_flag


def submit_research_data(payload):
    data, error = _validate_submit_payload(payload)
    if error is not None:
        return error

    epds_points, epds_total, epds_label, crisis_flag = _score_epds(
        data["epds_positions"]
    )

    # Build stored features dictionary: all 28 keys in FEATURE_NAMES order with "Abuse": null
    stored_features = {}
    for name in FEATURE_NAMES:
        if name == "Abuse":
            stored_features[name] = None
        else:
            stored_features[name] = data["features"][name]

    extra_fields = {"abuse_reworded": data["abuse_reworded"]}
    now_iso = datetime.now(timezone.utc).isoformat()

    features_json = json.dumps(stored_features, separators=(",", ":"))
    extra_fields_json = json.dumps(extra_fields, separators=(",", ":"))
    epds_items_json = json.dumps(epds_points, separators=(",", ":"))

    try:
        with SessionLocal.begin() as session:
            participant = session.get(ResearchParticipant, data["research_id"])
            if participant is None:
                return _json_error("Research participant not found.", 404)
            if not participant.consent_given or participant.withdrawn:
                return _json_error(
                    "Research participant consent is withdrawn or invalid.", 403
                )

            submission = ResearchSubmission(
                research_id=participant.research_id,
                timestamp=now_iso,
                dataset_version=None,
                source=RESEARCH_SOURCE,
                features=features_json,
                extra_fields=extra_fields_json,
                epds_items=epds_items_json,
                epds_total=epds_total,
                epds_label=epds_label,
            )
            session.add(submission)
            session.flush()
            submission_id = submission.id
    except Exception:
        return _json_error("Research submission could not be saved.", 500)

    return (
        jsonify(
            {
                "submission_id": submission_id,
                "crisis_flag": crisis_flag,
                "message": SUBMISSION_SUCCESS_MESSAGE,
            }
        ),
        201,
    )


def withdraw_consent(payload):
    if not isinstance(payload, dict):
        return _json_error("Request body must be a JSON object.")

    expected_keys = {"research_id"}
    payload_keys = set(payload.keys())
    if payload_keys != expected_keys:
        missing = [k for k in sorted(expected_keys) if k not in payload_keys]
        extra = [k for k in sorted(payload_keys) if k not in expected_keys]
        if missing and extra:
            return _json_error(
                f"Missing keys: {missing}; unexpected keys: {extra}."
            )
        if missing:
            return _json_error(f"Missing keys: {missing}.")
        return _json_error(f"Unexpected keys: {extra}.")

    research_id = payload["research_id"]
    if not isinstance(research_id, str) or not research_id.strip():
        return _json_error("Invalid value for 'research_id': expected a non-empty string.")

    now_iso = datetime.now(timezone.utc).isoformat()

    try:
        with SessionLocal.begin() as session:
            participant = session.get(ResearchParticipant, research_id)
            if participant is None:
                return _json_error("Research participant not found.", 404)

            # Idempotent: if already withdrawn, do not change withdrawn_at
            if not participant.withdrawn:
                participant.withdrawn = True
                participant.withdrawn_at = now_iso
                session.flush()
    except Exception:
        return _json_error("Research consent withdrawal could not be processed.", 500)

    return (
        jsonify(
            {
                "status": "withdrawn",
                "research_id": research_id,
            }
        ),
        200,
    )
