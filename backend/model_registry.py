import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import select

if __package__:
    from .config import FEATURE_NAMES, PRODUCTION_MODEL_PATH, PRODUCTION_THRESHOLD
    from .database import SessionLocal, initialize_database
    from .models import ModelVersion
    from .model_loader import LoadedModel, load_production_model
else:
    from config import FEATURE_NAMES, PRODUCTION_MODEL_PATH, PRODUCTION_THRESHOLD
    from database import SessionLocal, initialize_database
    from models import ModelVersion
    from model_loader import LoadedModel, load_production_model


BASE_MODEL_VERSION_ID = "base-v1"
BASE_MODEL_TYPE = "base"
BASE_MODEL_STATUS = "active"
BASE_DATASET_VERSION = "cleaned_v3"
BASE_MODEL_NOTES = "Initial base model"
CANDIDATE_MODEL_STATUS = "candidate"
APPROVED_MODEL_STATUS = "approved"
REJECTED_MODEL_STATUS = "rejected"

ALLOWED_MODEL_TYPES = {"candidate"}

BASE_HYPERPARAMETERS = {
    "n_estimators": 200,
    "max_depth": 3,
    "learning_rate": 0.05,
    "subsample": 0.7,
    "colsample_bytree": 0.7,
    "scale_pos_weight": 1.2950819672131149,
    "random_state": 42,
}
BASE_VALIDATION_METRICS = {
    "accuracy": 0.6917,
    "precision": 0.6115,
    "recall": 0.8095,
    "f1": 0.6967,
    "roc_auc": 0.8178,
    "best_cv_roc_auc": 0.8484,
}


def _model_file_hash(model_path: str | Path) -> str:
    path = Path(model_path)
    if not path.is_file():
        raise FileNotFoundError(f"Model file does not exist: {path}")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _ensure_safe_model_version_id(model_version_id: str) -> str:
    if not isinstance(model_version_id, str):
        raise ValueError("Model version ID must be a non-empty string.")
    value = model_version_id.strip()
    if not value or value == BASE_MODEL_VERSION_ID:
        raise ValueError("Invalid model version ID.")
    if value.startswith("base-"):
        raise ValueError("Candidate model version ID cannot start with 'base-'.")
    return value


def _candidate_model_file_hash(model_path: str | Path) -> str:
    return _model_file_hash(model_path)


def _validate_model_metadata_for_activation(
    model_version: ModelVersion,
    *,
    expected_file_path: str,
    expected_threshold: float,
    expected_feature_names: tuple[str, ...],
    expected_dataset_version: str,
    expected_model_type: str,
) -> None:
    if model_version.model_type != expected_model_type:
        raise ValueError(
            "Candidate model type mismatch: expected the candidate type to match the approved row."
        )
    if model_version.file_path != expected_file_path:
        raise ValueError("Candidate model file path does not match the stored metadata.")
    if model_version.file_hash != _candidate_model_file_hash(model_version.file_path):
        raise ValueError("Candidate model file hash does not match the stored metadata.")
    if model_version.trained_on_dataset_version != expected_dataset_version:
        raise ValueError("Candidate dataset version does not match the expected model dataset.")
    if model_version.production_threshold_used != expected_threshold:
        raise ValueError("Candidate model threshold does not match the production threshold.")

    try:
        metrics = json.loads(model_version.validation_metrics)
    except (TypeError, json.JSONDecodeError) as exc:
        raise ValueError("Candidate model validation_metrics is not valid JSON.") from exc
    if not isinstance(metrics, dict):
        raise ValueError("Candidate model validation_metrics must be a JSON object.")

    try:
        hyperparameters = json.loads(model_version.hyperparameters)
    except (TypeError, json.JSONDecodeError) as exc:
        raise ValueError("Candidate model hyperparameters is not valid JSON.") from exc
    if not isinstance(hyperparameters, dict):
        raise ValueError("Candidate model hyperparameters must be a JSON object.")

    if not model_version.file_path:
        raise ValueError("Candidate model file path is required.")

    model = load_production_model(
        model_version_id=model_version.model_version_id,
        threshold=model_version.production_threshold_used,
    )
    if list(FEATURE_NAMES) != expected_feature_names:
        raise ValueError("Candidate model feature names mismatch the frozen schema.")
    if model.model.feature_names != list(expected_feature_names):
        raise ValueError("Candidate model does not match the configured feature order.")
    if model.threshold != expected_threshold:
        raise ValueError("Candidate model threshold does not match the expected threshold.")


def get_model_version(model_version_id: str) -> ModelVersion | None:
    with SessionLocal() as session:
        return session.get(ModelVersion, model_version_id)


def validate_stored_metadata(model_version: ModelVersion) -> None:
    expected_values = {
        "model_version_id": BASE_MODEL_VERSION_ID,
        "model_type": BASE_MODEL_TYPE,
        "file_path": str(PRODUCTION_MODEL_PATH.resolve()),
        "file_hash": _model_file_hash(PRODUCTION_MODEL_PATH),
        "trained_on_dataset_version": BASE_DATASET_VERSION,
        "hyperparameters": BASE_HYPERPARAMETERS,
        "validation_metrics": BASE_VALIDATION_METRICS,
        "production_threshold_used": PRODUCTION_THRESHOLD,
        "status": BASE_MODEL_STATUS,
        "reviewed_by": None,
        "reviewed_at": None,
        "notes": BASE_MODEL_NOTES,
    }

    for field, expected in expected_values.items():
        actual = getattr(model_version, field)
        if field in {"hyperparameters", "validation_metrics"}:
            try:
                actual = json.loads(actual)
            except (TypeError, json.JSONDecodeError) as exc:
                raise ValueError(f"Invalid JSON in model_versions.{field}") from exc
        if actual != expected:
            raise ValueError(
                f"Stored base model metadata mismatch for {field}: "
                f"expected {expected!r}, got {actual!r}."
            )

    try:
        created_at = datetime.fromisoformat(model_version.created_at)
    except (TypeError, ValueError) as exc:
        raise ValueError(
            "Stored base model created_at is not a valid ISO timestamp"
        ) from exc
    if created_at.tzinfo is None or created_at.utcoffset() is None:
        raise ValueError("Stored base model created_at must include a UTC offset")
    if created_at.utcoffset().total_seconds() != 0:
        raise ValueError("Stored base model created_at must be a UTC timestamp")


def _model_version_dict(model_version: ModelVersion) -> dict:
    return {
        "model_version_id": model_version.model_version_id,
        "model_type": model_version.model_type,
        "status": model_version.status,
        "trained_on_dataset_version": model_version.trained_on_dataset_version,
        "production_threshold_used": model_version.production_threshold_used,
        "validation_metrics": model_version.validation_metrics,
        "created_at": model_version.created_at,
        "reviewed_by": model_version.reviewed_by,
        "reviewed_at": model_version.reviewed_at,
        "notes": model_version.notes,
    }


def list_model_versions() -> list[dict]:
    with SessionLocal() as session:
        model_versions = session.query(ModelVersion).order_by(
            ModelVersion.created_at.asc()
        ).all()
        return [_model_version_dict(model_version) for model_version in model_versions]


def register_candidate_model(
    *,
    model_version_id: str,
    model_type: str,
    file_path: str | Path,
    trained_on_dataset_version: str,
    hyperparameters: dict,
    validation_metrics: dict,
    production_threshold_used: float,
    notes: str | None = None,
) -> ModelVersion:
    if model_type not in ALLOWED_MODEL_TYPES:
        raise ValueError("Model type must be 'candidate'.")
    candidate_id = _ensure_safe_model_version_id(model_version_id)
    file_path = str(Path(file_path))
    if not Path(file_path).is_file():
        raise FileNotFoundError(f"Model file does not exist: {file_path}")
    if production_threshold_used != PRODUCTION_THRESHOLD:
        raise ValueError(
            f"Candidate threshold must equal {PRODUCTION_THRESHOLD}."
        )
    if not isinstance(hyperparameters, dict):
        raise ValueError("hyperparameters must be a dictionary.")
    if not isinstance(validation_metrics, dict):
        raise ValueError("validation_metrics must be a dictionary.")

    with SessionLocal.begin() as session:
        existing = session.get(ModelVersion, candidate_id)
        if existing is not None:
            raise ValueError(f"Model version '{candidate_id}' already exists.")

        model_version = ModelVersion(
            model_version_id=candidate_id,
            model_type=model_type,
            file_path=file_path,
            file_hash=_candidate_model_file_hash(file_path),
            trained_on_dataset_version=trained_on_dataset_version,
            hyperparameters=json.dumps(hyperparameters, separators=(",", ":")),
            validation_metrics=json.dumps(validation_metrics, separators=(",", ":")),
            production_threshold_used=production_threshold_used,
            status=CANDIDATE_MODEL_STATUS,
            created_at=datetime.now(timezone.utc).isoformat(),
            reviewed_by=None,
            reviewed_at=None,
            notes=notes,
        )
        session.add(model_version)
        session.flush()
        return model_version


def review_candidate_model(model_version_id: str, *, reviewer: str | None, decision: str, notes: str | None = None) -> dict:
    if decision not in {APPROVED_MODEL_STATUS, REJECTED_MODEL_STATUS}:
        raise ValueError("Decision must be 'approved' or 'rejected'.")
    if not reviewer:
        reviewer = "admin"
    if model_version_id == BASE_MODEL_VERSION_ID:
        raise ValueError("base-v1 cannot be reviewed.")

    with SessionLocal.begin() as session:
        model_version = session.get(ModelVersion, model_version_id)
        if model_version is None:
            raise ValueError(f"Model version '{model_version_id}' not found.")
        if model_version.status != CANDIDATE_MODEL_STATUS:
            raise ValueError("Only candidate models can be reviewed.")
        model_version.status = decision
        model_version.reviewed_by = reviewer
        model_version.reviewed_at = datetime.now(timezone.utc).isoformat()
        if notes is not None:
            model_version.notes = notes
        session.flush()
        return _model_version_dict(model_version)


def activate_model(model_version_id: str, *, reviewer: str | None = None) -> ModelVersion:
    if model_version_id == BASE_MODEL_VERSION_ID:
        raise ValueError("base-v1 is protected and cannot be activated by this action.")

    with SessionLocal.begin() as session:
        model_version = session.get(ModelVersion, model_version_id)
        if model_version is None:
            raise ValueError(f"Model version '{model_version_id}' not found.")
        if model_version.status != APPROVED_MODEL_STATUS:
            raise ValueError("Only approved candidates may be activated.")

        if model_version.file_path is None or not Path(model_version.file_path).is_file():
            raise FileNotFoundError(f"Model file does not exist: {model_version.file_path}")
        if model_version.file_hash != _candidate_model_file_hash(model_version.file_path):
            raise ValueError("Model file hash mismatch.")
        if model_version.production_threshold_used != PRODUCTION_THRESHOLD:
            raise ValueError("Candidate threshold must match the production threshold.")

        feature_names = tuple(FEATURE_NAMES)
        if not model_version.model_type or model_version.model_type not in ALLOWED_MODEL_TYPES:
            raise ValueError("Model type is invalid.")

        try:
            loaded = load_production_model(
                model_version_id=model_version.model_version_id,
                threshold=model_version.production_threshold_used,
            )
        except Exception as exc:
            raise ValueError("Candidate model could not be loaded for activation.") from exc
        if list(loaded.model.feature_names) != list(feature_names):
            raise ValueError("Candidate model feature names do not match config.FEATURE_NAMES.")
        if loaded.model.num_features() != len(feature_names):
            raise ValueError("Candidate model feature count does not match config.FEATURE_NAMES.")

        active_rows = session.query(ModelVersion).filter(ModelVersion.status == BASE_MODEL_STATUS).all()
        if len(active_rows) > 1:
            raise ValueError("Multiple active models are present; activation cannot proceed.")

        if len(active_rows) == 1:
            active_row = active_rows[0]
            if active_row.model_version_id == BASE_MODEL_VERSION_ID:
                active_row.status = "inactive"
            else:
                active_row.status = "inactive"

        model_version.status = BASE_MODEL_STATUS
        model_version.reviewed_by = reviewer or model_version.reviewed_by or "admin"
        model_version.reviewed_at = model_version.reviewed_at or datetime.now(timezone.utc).isoformat()
        session.flush()
        return model_version


def register_base_model() -> ModelVersion:
    model_hash = _model_file_hash(PRODUCTION_MODEL_PATH)
    initialize_database()

    with SessionLocal.begin() as session:
        model_version = session.get(ModelVersion, BASE_MODEL_VERSION_ID)
        if model_version is None:
            model_version = ModelVersion(
                model_version_id=BASE_MODEL_VERSION_ID,
                model_type=BASE_MODEL_TYPE,
                file_path=str(PRODUCTION_MODEL_PATH.resolve()),
                file_hash=model_hash,
                trained_on_dataset_version=BASE_DATASET_VERSION,
                hyperparameters=json.dumps(
                    BASE_HYPERPARAMETERS, separators=(",", ":")
                ),
                validation_metrics=json.dumps(
                    BASE_VALIDATION_METRICS, separators=(",", ":")
                ),
                production_threshold_used=PRODUCTION_THRESHOLD,
                status=BASE_MODEL_STATUS,
                created_at=datetime.now(timezone.utc).isoformat(),
                reviewed_by=None,
                reviewed_at=None,
                notes=BASE_MODEL_NOTES,
            )
            session.add(model_version)
            session.flush()
        else:
            validate_stored_metadata(model_version)

    model_version = get_model_version(BASE_MODEL_VERSION_ID)
    if model_version is None:
        raise RuntimeError("Base model registration did not persist.")
    validate_stored_metadata(model_version)
    return model_version


def get_active_model_version() -> ModelVersion:
    with SessionLocal() as session:
        active_versions = session.scalars(
            select(ModelVersion).where(ModelVersion.status == "active")
        ).all()

    if len(active_versions) != 1:
        raise RuntimeError(
            f"Expected exactly one active model version to load; found "
            f"{len(active_versions)}."
        )
    return active_versions[0]


def load_active_model() -> LoadedModel:
    model_version = get_active_model_version()
    validate_stored_metadata(model_version)
    return load_production_model(
        model_version_id=model_version.model_version_id,
        threshold=model_version.production_threshold_used,
    )


def initialize_model_registry() -> LoadedModel:
    register_base_model()
    return load_active_model()
