from datetime import date, datetime, timedelta
import math
from flask import jsonify

if __package__:
    from .database import SessionLocal
    from .models import SleepLog, User
    from .prediction_service import _json_error
    from .profile_service import LOCAL_DEVICE_NAME, get_or_create_profile
else:
    from database import SessionLocal
    from models import SleepLog, User
    from prediction_service import _json_error
    from profile_service import LOCAL_DEVICE_NAME, get_or_create_profile

ALLOWED_QUALITIES = {"Poor", "Fair", "Good"}
MAX_NOTE_LENGTH = 500
MAX_GET_ENTRIES = 90


class _DuplicateSleepError(Exception):
    pass


def _validate_sleep_payload(payload):
    if not isinstance(payload, dict):
        return None, _json_error("Request body must be a JSON object.")

    allowed_keys = {"date", "hours", "quality", "note"}
    required_keys = {"date", "hours"}

    payload_keys = set(payload.keys())
    missing = [k for k in required_keys if k not in payload_keys]
    extra = [k for k in payload_keys if k not in allowed_keys]

    if missing and extra:
        return None, _json_error(
            f"Missing keys: {missing}; unexpected keys: {extra}."
        )
    if missing:
        return None, _json_error(f"Missing keys: {missing}.")
    if extra:
        return None, _json_error(f"Unexpected keys: {extra}.")

    # Validate date
    date_val = payload["date"]
    if not isinstance(date_val, str):
        return None, _json_error("Invalid value for 'date': expected a string in YYYY-MM-DD format.")

    if len(date_val) != 10 or date_val[4] != "-" or date_val[7] != "-":
        return None, _json_error("Invalid value for 'date': expected a string in YYYY-MM-DD format.")

    try:
        parsed_date = datetime.strptime(date_val, "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return None, _json_error("Invalid value for 'date': invalid calendar date.")

    # Format check to ensure strict YYYY-MM-DD (e.g. rejects non-padded or malformed)
    if parsed_date.strftime("%Y-%m-%d") != date_val:
        return None, _json_error("Invalid value for 'date': expected a string in YYYY-MM-DD format.")

    server_today = date.today()
    min_date = server_today - timedelta(days=29)
    if parsed_date > server_today:
        return None, _json_error("Invalid value for 'date': future dates are not allowed.")
    if parsed_date < min_date:
        return None, _json_error("Invalid value for 'date': date is older than allowed window (today-29).")

    # Validate hours
    hours_raw = payload["hours"]
    if hours_raw is None or isinstance(hours_raw, bool) or not isinstance(hours_raw, (int, float)):
        return None, _json_error("Invalid value for 'hours': expected a finite number between 0 and 24.")

    try:
        numeric_hours = float(hours_raw)
    except (TypeError, ValueError, OverflowError):
        return None, _json_error("Invalid value for 'hours': expected a finite number between 0 and 24.")

    if not math.isfinite(numeric_hours) or numeric_hours < 0.0 or numeric_hours > 24.0:
        return None, _json_error("Invalid value for 'hours': must be between 0 and 24.")

    # Validate quality (optional)
    quality_val = payload.get("quality")
    if quality_val is not None:
        if not isinstance(quality_val, str) or quality_val not in ALLOWED_QUALITIES:
            return None, _json_error(
                f"Invalid value for 'quality': expected one of {sorted(list(ALLOWED_QUALITIES))} or null."
            )

    # Validate note (optional)
    note_val = payload.get("note")
    if note_val is not None:
        if not isinstance(note_val, str):
            return None, _json_error("Invalid value for 'note': expected a string or null.")
        if len(note_val) > MAX_NOTE_LENGTH:
            return None, _json_error(
                f"Invalid value for 'note': length exceeds maximum of {MAX_NOTE_LENGTH} characters."
            )

    validated = {
        "date": date_val,
        "hours": numeric_hours,
        "quality": quality_val,
        "note": note_val,
    }
    return validated, None


def submit_sleep_log(payload):
    data, error = _validate_sleep_payload(payload)
    if error is not None:
        return error

    try:
        with SessionLocal.begin() as session:
            # Check for existing profile and duplicate (user_id, date) BEFORE creating anything
            existing_profile = (
                session.query(User)
                .filter(User.name == LOCAL_DEVICE_NAME)
                .order_by(User.created_at)
                .first()
            )
            if existing_profile is not None:
                existing_entry = (
                    session.query(SleepLog)
                    .filter(
                        SleepLog.user_id == existing_profile.id,
                        SleepLog.date == data["date"],
                    )
                    .first()
                )
                if existing_entry is not None:
                    raise _DuplicateSleepError()

            profile = get_or_create_profile(session)

            sleep_log = SleepLog(
                user_id=profile.id,
                date=data["date"],
                hours=data["hours"],
                quality=data["quality"],
                note=data["note"],
            )
            session.add(sleep_log)
            session.flush()
            sleep_id = sleep_log.id
            result_date = sleep_log.date
            result_hours = sleep_log.hours
    except _DuplicateSleepError:
        return _json_error("A sleep log for this date already exists.", 409)
    except Exception:
        return _json_error("Sleep log could not be saved.", 500)

    return (
        jsonify(
            {
                "sleep_id": sleep_id,
                "date": result_date,
                "hours": result_hours,
            }
        ),
        201,
    )


def get_sleep_logs():
    try:
        with SessionLocal() as session:
            profile = (
                session.query(User)
                .filter(User.name == LOCAL_DEVICE_NAME)
                .order_by(User.created_at)
                .first()
            )
            if profile is None:
                return jsonify({"entries": []}), 200

            logs = (
                session.query(SleepLog)
                .filter(SleepLog.user_id == profile.id)
                .order_by(SleepLog.date.desc(), SleepLog.id.desc())
                .limit(MAX_GET_ENTRIES)
                .all()
            )

            entries = [
                {
                    "date": log.date,
                    "hours": log.hours,
                    "quality": log.quality,
                    "note": log.note,
                }
                for log in logs
            ]
            return jsonify({"entries": entries}), 200
    except Exception:
        return _json_error("Could not retrieve sleep logs.", 500)
