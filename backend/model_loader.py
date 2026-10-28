from dataclasses import dataclass
from typing import Any

from xgboost import Booster, DMatrix
from xgboost.core import XGBoostError

if __package__:
    from .config import FEATURE_NAMES, PRODUCTION_MODEL_PATH
else:
    from config import FEATURE_NAMES, PRODUCTION_MODEL_PATH


@dataclass(frozen=True)
class LoadedModel:
    model_version_id: str
    threshold: float
    model: Booster

    def __call__(self, features: Any) -> Any:
        matrix = DMatrix(features, feature_names=list(FEATURE_NAMES))
        return self.model.predict(matrix)


def load_production_model(model_version_id: str, threshold: float) -> LoadedModel:
    if not PRODUCTION_MODEL_PATH.is_file():
        raise FileNotFoundError(
            f"Production model file does not exist: {PRODUCTION_MODEL_PATH}"
        )

    model = Booster()
    try:
        model.load_model(str(PRODUCTION_MODEL_PATH))
    except (OSError, ValueError, XGBoostError) as exc:
        raise RuntimeError(
            f"Failed to load production model from {PRODUCTION_MODEL_PATH}"
        ) from exc

    actual_feature_names = model.feature_names
    if actual_feature_names != list(FEATURE_NAMES):
        raise ValueError(
            "Production model feature names do not match config.FEATURE_NAMES "
            "in both count and order."
        )
    if model.num_features() != len(FEATURE_NAMES):
        raise ValueError(
            f"Production model has {model.num_features()} features; "
            f"expected {len(FEATURE_NAMES)}."
        )

    return LoadedModel(
        model_version_id=model_version_id,
        threshold=threshold,
        model=model,
    )
