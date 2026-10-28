import re
from flask import jsonify

if __package__:
    from .database import SessionLocal
    from .models import Contact, User
    from .prediction_service import _json_error
    from .profile_service import LOCAL_DEVICE_NAME, get_or_create_profile
else:
    from database import SessionLocal
    from models import Contact, User
    from prediction_service import _json_error
    from profile_service import LOCAL_DEVICE_NAME, get_or_create_profile

MAX_CONTACTS_PER_PROFILE = 5
MAX_NAME_LENGTH = 100
MAX_EMAIL_LENGTH = 254
MAX_RELATION_LENGTH = 50

# Basic format: local@domain.tld, no whitespace, no CR/LF
EMAIL_REGEX = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _validate_contact_payload(payload):
    if not isinstance(payload, dict):
        return None, _json_error("Request body must be a JSON object.")

    expected_keys = {"name", "email", "relation"}
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

    # Name validation: non-empty string <= 100 chars
    name_val = payload["name"]
    if not isinstance(name_val, str) or not name_val.strip():
        return None, _json_error("Invalid value for 'name': expected a non-empty string.")
    if len(name_val) > MAX_NAME_LENGTH:
        return None, _json_error(f"Invalid value for 'name': maximum length is {MAX_NAME_LENGTH} characters.")

    # Email validation: string <= 254 chars, one "@", no whitespace, no CR/LF, basic format
    email_val = payload["email"]
    if not isinstance(email_val, str):
        return None, _json_error("Invalid value for 'email': expected a string.")
    if len(email_val) > MAX_EMAIL_LENGTH:
        return None, _json_error(f"Invalid value for 'email': maximum length is {MAX_EMAIL_LENGTH} characters.")
    if "\r" in email_val or "\n" in email_val or "\t" in email_val or " " in email_val:
        return None, _json_error("Invalid value for 'email': whitespace and control characters are not allowed.")
    if email_val.count("@") != 1:
        return None, _json_error("Invalid value for 'email': must contain exactly one '@'.")
    if not EMAIL_REGEX.match(email_val):
        return None, _json_error("Invalid value for 'email': invalid email address format.")

    # Relation validation: string <= 50 chars or null
    relation_val = payload["relation"]
    if relation_val is not None:
        if not isinstance(relation_val, str):
            return None, _json_error("Invalid value for 'relation': expected a string or null.")
        if len(relation_val) > MAX_RELATION_LENGTH:
            return None, _json_error(f"Invalid value for 'relation': maximum length is {MAX_RELATION_LENGTH} characters.")

    validated = {
        "name": name_val.strip(),
        "email": email_val.strip(),
        "relation": relation_val.strip() if isinstance(relation_val, str) else None,
    }
    return validated, None


def add_contact(payload):
    data, error = _validate_contact_payload(payload)
    if error is not None:
        return error

    try:
        with SessionLocal.begin() as session:
            profile = get_or_create_profile(session)

            # Query existing contacts for this profile
            existing_contacts = (
                session.query(Contact)
                .filter(Contact.user_id == profile.id)
                .all()
            )

            # Cap check: Max 5 contacts per profile (409)
            if len(existing_contacts) >= MAX_CONTACTS_PER_PROFILE:
                return _json_error("Maximum number of contacts (5) reached.", 409)

            # Duplicate email check: Case-insensitive duplicate email per profile -> 409
            norm_email = data["email"].lower()
            for c in existing_contacts:
                if c.email.lower() == norm_email:
                    return _json_error("A contact with this email already exists.", 409)

            new_contact = Contact(
                user_id=profile.id,
                name=data["name"],
                email=data["email"],
                relation=data["relation"],
            )
            session.add(new_contact)
            session.flush()
            contact_id = new_contact.id
    except Exception:
        return _json_error("Contact could not be saved.", 500)

    return jsonify({"contact_id": contact_id}), 201


def list_contacts():
    try:
        with SessionLocal() as session:
            profile = (
                session.query(User)
                .filter(User.name == LOCAL_DEVICE_NAME)
                .order_by(User.created_at)
                .first()
            )
            if profile is None:
                return jsonify({"contacts": []}), 200

            contacts = (
                session.query(Contact)
                .filter(Contact.user_id == profile.id)
                .order_by(Contact.id.asc())
                .all()
            )

            result = [
                {
                    "id": c.id,
                    "name": c.name,
                    "email": c.email,
                    "relation": c.relation,
                }
                for c in contacts
            ]
            return jsonify({"contacts": result}), 200
    except Exception:
        return _json_error("Could not retrieve contacts.", 500)


def delete_contact(contact_id):
    if isinstance(contact_id, bool) or not isinstance(contact_id, int):
        return _json_error("Invalid contact ID.", 400)

    try:
        with SessionLocal.begin() as session:
            profile = (
                session.query(User)
                .filter(User.name == LOCAL_DEVICE_NAME)
                .order_by(User.created_at)
                .first()
            )
            if profile is None:
                return _json_error("Contact not found.", 404)

            contact = session.get(Contact, contact_id)
            if contact is None or contact.user_id != profile.id:
                return _json_error("Contact not found.", 404)

            session.delete(contact)
            session.flush()
    except Exception:
        return _json_error("Contact could not be deleted.", 500)

    return jsonify({"deleted": contact_id}), 200
