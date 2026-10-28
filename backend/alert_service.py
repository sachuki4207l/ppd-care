import json
from datetime import datetime, timezone
from flask import jsonify

if __package__:
    from .database import SessionLocal
    from .models import Contact, FamilyAlert, PersonalCheckin, User
    from .prediction_service import _json_error
    from .profile_service import LOCAL_DEVICE_NAME
else:
    from database import SessionLocal
    from models import Contact, FamilyAlert, PersonalCheckin, User
    from prediction_service import _json_error
    from profile_service import LOCAL_DEVICE_NAME

ALLOWED_DECISIONS = {"compose_opened", "declined"}
MAX_RECIPIENT_CONTACTS = 5


def _validate_alert_payload(payload):
    if not isinstance(payload, dict):
        return None, _json_error("Request body must be a JSON object.")

    expected_keys = {"checkin_id", "decision", "recipient_contact_ids"}
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

    # Validate checkin_id: strict integer, reject bool, float, str, huge ints
    checkin_id = payload["checkin_id"]
    if isinstance(checkin_id, bool) or not isinstance(checkin_id, int):
        return None, _json_error("Invalid value for 'checkin_id': expected an integer.")
    if abs(checkin_id) > 2147483647:
        return None, _json_error("Invalid value for 'checkin_id': integer out of range.")

    # Validate decision
    decision = payload["decision"]
    if not isinstance(decision, str) or decision not in ALLOWED_DECISIONS:
        return None, _json_error(
            "Invalid value for 'decision': must be 'compose_opened' or 'declined'."
        )

    # Validate recipient_contact_ids based on decision
    recipients = payload["recipient_contact_ids"]
    validated_recipients = None

    if decision == "declined":
        if recipients is not None:
            return None, _json_error(
                "Invalid value for 'recipient_contact_ids': must be null when decision is 'declined'."
            )
    elif decision == "compose_opened":
        if not isinstance(recipients, list) or len(recipients) == 0:
            return None, _json_error(
                "Invalid value for 'recipient_contact_ids': must be a non-empty list when decision is 'compose_opened'."
            )
        if len(recipients) > MAX_RECIPIENT_CONTACTS:
            return None, _json_error(
                f"Invalid value for 'recipient_contact_ids': maximum of {MAX_RECIPIENT_CONTACTS} recipients allowed."
            )

        # Must be distinct integers, reject bool, float, str, huge ints
        seen_ids = set()
        distinct_ids = []
        for idx, item in enumerate(recipients):
            if isinstance(item, bool) or not isinstance(item, int):
                return None, _json_error(
                    f"Invalid recipient contact ID at index {idx}: expected an integer."
                )
            if abs(item) > 2147483647:
                return None, _json_error(
                    f"Invalid recipient contact ID at index {idx}: integer out of range."
                )
            if item in seen_ids:
                return None, _json_error(
                    f"Duplicate recipient contact ID: {item}."
                )
            seen_ids.add(item)
            distinct_ids.append(item)

        validated_recipients = distinct_ids

    validated = {
        "checkin_id": checkin_id,
        "decision": decision,
        "recipient_contact_ids": validated_recipients,
    }
    return validated, None


def record_alert_decision(payload):
    data, error = _validate_alert_payload(payload)
    if error is not None:
        return error

    try:
        with SessionLocal.begin() as session:
            # Never creates a user (no profile -> 404)
            profile = (
                session.query(User)
                .filter(User.name == LOCAL_DEVICE_NAME)
                .order_by(User.created_at)
                .first()
            )
            if profile is None:
                return _json_error("Local profile not found.", 404)

            # Validate that the check-in belongs to THIS profile
            checkin = session.get(PersonalCheckin, data["checkin_id"])
            if checkin is None or checkin.user_id != profile.id:
                return _json_error("Check-in not found or not owned by this profile.", 404)

            # Validate that every selected contact belongs to THIS profile
            recipient_ids = data["recipient_contact_ids"]
            if recipient_ids is not None:
                for cid in recipient_ids:
                    c = session.get(Contact, cid)
                    if c is None or c.user_id != profile.id:
                        return _json_error(
                            f"Contact {cid} not found or not owned by this profile.", 404
                        )

            recipient_ids_json = (
                json.dumps(recipient_ids, separators=(",", ":"))
                if recipient_ids is not None
                else None
            )
            now_iso = datetime.now(timezone.utc).isoformat()

            alert = FamilyAlert(
                checkin_id=checkin.id,
                user_id=profile.id,
                timestamp=now_iso,
                decision=data["decision"],
                recipient_contact_ids=recipient_ids_json,
            )
            session.add(alert)
            session.flush()
            alert_id = alert.id
    except Exception:
        return _json_error("Family alert decision could not be recorded.", 500)

    return jsonify({"alert_id": alert_id}), 201
