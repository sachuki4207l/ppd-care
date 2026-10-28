import math

from flask import current_app, jsonify, request

if __package__:
    from .config import FEATURE_NAMES
    from .model_registry import load_active_model
else:
    from config import FEATURE_NAMES
    from model_registry import load_active_model


def _json_error(message, status_code=400):
    return jsonify({"error": message}), status_code


def _validate_features(payload):
    if not isinstance(payload, dict):
        return None, _json_error("Request body must be a JSON object.")

    missing = [name for name in FEATURE_NAMES if name not in payload]
    extra = [name for name in payload if name not in FEATURE_NAMES]
    if missing or extra:
        if missing and extra:
            return None, _json_error(
                f"Missing features: {missing}; unexpected features: {extra}."
            )
        if missing:
            return None, _json_error(f"Missing features: {missing}.")
        return None, _json_error(f"Unexpected features: {extra}.")

    values = []
    for name in FEATURE_NAMES:
        value = payload[name]
        if value is None or isinstance(value, bool):
            return None, _json_error(f"Invalid value for '{name}': must be a finite number.")
        if not isinstance(value, (int, float)):
            return None, _json_error(f"Invalid value for '{name}': must be a finite number.")
        try:
            numeric_value = float(value)
        except (TypeError, ValueError, OverflowError):
            return None, _json_error(f"Invalid value for '{name}': must be a finite number.")
        if not math.isfinite(numeric_value):
            return None, _json_error(f"Invalid value for '{name}': must be a finite number.")
        values.append(numeric_value)

    return values, None


def predict_risk(feature_vector):
    if not isinstance(feature_vector, list):
        raise TypeError("feature_vector must be a list of 28 finite numbers.")
    if len(feature_vector) != len(FEATURE_NAMES):
        raise ValueError(
            f"feature_vector must contain exactly {len(FEATURE_NAMES)} values."
        )

    validated = []
    for index, value in enumerate(feature_vector):
        if value is None or isinstance(value, bool):
            raise ValueError(f"Feature at index {index} is not a finite number.")
        if not isinstance(value, (int, float)):
            raise ValueError(f"Feature at index {index} is not a finite number.")
        try:
            numeric_value = float(value)
        except (TypeError, ValueError, OverflowError):
            raise ValueError(f"Feature at index {index} is not a finite number.") from None
        if not math.isfinite(numeric_value):
            raise ValueError(f"Feature at index {index} is not a finite number.")
        validated.append(numeric_value)

    active_model = load_active_model()
    probability = float(active_model([validated])[0])
    prediction = 1 if probability >= active_model.threshold else 0
    return {
        "prediction": prediction,
        "probability": probability,
        "threshold": float(active_model.threshold),
        "model_version": active_model.model_version_id,
    }
