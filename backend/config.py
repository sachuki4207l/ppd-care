from pathlib import Path


HOST = "0.0.0.0"
PORT = 5000
DEBUG = False

BACKEND_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BACKEND_DIR.parent
PRODUCTION_MODEL_PATH = BACKEND_DIR / "models" / "ppd_xgboost_tuned_model.json"
DATABASE_PATH = BACKEND_DIR / "ppd_care.db"

PRODUCTION_THRESHOLD = 0.29

FEATURE_NAMES = (
    "Education Level",
    "Current monthly income",
    "Husband’s monthly income",
    "Total children",
    "Family type",
    "Relationship with the in-laws",
    "Relationship with husband",
    "Relationship with the newborn",
    "Relationship between father and newborn",
    "Feeling about motherhood",
    "Recieved Support",
    "Major changes or losses during pregnancy",
    "Abuse",
    "Trust and share feelings",
    "Fear of pregnancy",
    "Diseases during pregnancy",
    "Gender of newborn",
    "Birth compliancy",
    "Breastfeed",
    "Worry about newborn",
    "Relax/sleep when the newborn is asleep",
    "Angry after latest child birth",
    "Depression before pregnancy (PHQ2)",
    "Depression during pregnancy (PHQ2)",
    "Occupation before latest pregnancy_Housewife",
    "Occupation before latest pregnancy_Student",
    "Feeling for regular activities_Normal",
    "Need for Support_Unknown",
)
assert len(FEATURE_NAMES) == 28

EXPLANATION_EXCLUDED_FEATURES = {"Abuse"}
