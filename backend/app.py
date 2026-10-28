from urllib.parse import urlsplit

from flask import Flask, current_app, jsonify, render_template, request
from flask_cors import CORS

if __package__:
    from .alert_service import record_alert_decision
    from .checkin_service import submit_checkin
    from .contact_service import add_contact, delete_contact, list_contacts
    from .model_registry import (
        APPROVED_MODEL_STATUS,
        REJECTED_MODEL_STATUS,
        initialize_model_registry,
        list_model_versions,
        review_candidate_model,
    )
    from .prediction_service import _json_error, _validate_features, predict_risk
    from .research_service import (
        record_consent,
        submit_research_data,
        withdraw_consent,
    )
    from .sleep_service import get_sleep_logs, submit_sleep_log
else:
    from alert_service import record_alert_decision
    from checkin_service import submit_checkin
    from contact_service import add_contact, delete_contact, list_contacts
    from model_registry import (
        APPROVED_MODEL_STATUS,
        REJECTED_MODEL_STATUS,
        initialize_model_registry,
        list_model_versions,
        review_candidate_model,
    )
    from prediction_service import _json_error, _validate_features, predict_risk
    from research_service import (
        record_consent,
        submit_research_data,
        withdraw_consent,
    )
    from sleep_service import get_sleep_logs, submit_sleep_log

app = Flask(__name__, template_folder='templates')
app.json.sort_keys = False
CORS(app)

initialize_model_registry()


def _local_only_response(message, status=403):
    return jsonify({"error": message}), status


def _is_local_request():
    remote_addr = request.remote_addr or ""
    if remote_addr not in {"127.0.0.1", "::1", "::ffff:127.0.0.1"}:
        return False

    if request.method == "POST" and "Origin" in request.headers:
        try:
            origin_hostname = urlsplit(request.headers["Origin"]).hostname
        except ValueError:
            return False
        if origin_hostname not in {"127.0.0.1", "localhost"}:
            return False

    return True


@app.get("/health")
def health():
    return jsonify({"status": "ok"})


@app.get("/admin")
def admin_dashboard():
    if not _is_local_request():
        return _local_only_response("Admin access is restricted to local laptop access only.", 403)
    return render_template("admin.html", models=list_model_versions())


@app.post("/admin/review")
def admin_review():
    if not _is_local_request():
        return _local_only_response("Admin access is restricted to local laptop access only.", 403)
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return _json_error("Request body must be a JSON object.")
    model_version_id = payload.get("model_version_id")
    decision = payload.get("decision")
    reviewer = payload.get("reviewer")
    notes = payload.get("notes")
    if not isinstance(model_version_id, str) or not model_version_id.strip():
        return _json_error("model_version_id is required.")
    if decision not in {APPROVED_MODEL_STATUS, REJECTED_MODEL_STATUS}:
        return _json_error("decision must be 'approved' or 'rejected'.")
    try:
        result = review_candidate_model(
            model_version_id, reviewer=reviewer, decision=decision, notes=notes
        )
    except ValueError as exc:
        return _json_error(str(exc), 400)
    return jsonify(result)


@app.post("/admin/activate")
def admin_activate():
    if not _is_local_request():
        return _local_only_response("Admin access is restricted to local laptop access only.", 403)
    return jsonify({"error": "Activation not enabled yet"}), 501


@app.post("/predict")
def predict():
    payload = request.get_json(silent=True)
    if payload is None:
        return _json_error("Request body must be valid JSON.")

    features, error = _validate_features(payload)
    if error is not None:
        return error

    try:
        result = predict_risk(features)
    except Exception:
        current_app.logger.exception("Active model loading or prediction failed.")
        return _json_error("Prediction service unavailable.", 500)

    return jsonify(result)


@app.post("/contacts")
def contacts_create():
    payload = request.get_json(silent=True)
    if payload is None:
        return _json_error("Request body must be valid JSON.")
    return add_contact(payload)


@app.get("/contacts")
def contacts_list():
    return list_contacts()


@app.delete("/contacts/<int:id>")
def contacts_delete(id):
    return delete_contact(id)


@app.post("/alerts")
def alerts_create():
    payload = request.get_json(silent=True)
    if payload is None:
        return _json_error("Request body must be valid JSON.")
    return record_alert_decision(payload)


@app.post("/checkin")
def checkin():
    payload = request.get_json(silent=True)
    if payload is None:
        return _json_error("Request body must be valid JSON.")
    return submit_checkin(payload)


@app.post("/sleep")
def log_sleep():
    payload = request.get_json(silent=True)
    if payload is None:
        return _json_error("Request body must be valid JSON.")
    return submit_sleep_log(payload)


@app.get("/sleep")
def list_sleep():
    return get_sleep_logs()


@app.post("/research/consent")
def research_consent():
    payload = request.get_json(silent=True)
    if payload is None:
        return _json_error("Request body must be valid JSON.")
    return record_consent(payload)


@app.post("/research/submit")
def research_submit():
    payload = request.get_json(silent=True)
    if payload is None:
        return _json_error("Request body must be valid JSON.")
    return submit_research_data(payload)


@app.post("/research/withdraw")
def research_withdraw():
    payload = request.get_json(silent=True)
    if payload is None:
        return _json_error("Request body must be valid JSON.")
    return withdraw_consent(payload)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
