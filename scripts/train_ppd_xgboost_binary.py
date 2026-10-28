"""
XGBoost model for Postpartum Depression (PPD) binary prediction
Using the pre-cleaned, LASSO+VIF feature-selected train/validation sets
(train_cleaned_v3.csv / validation_cleaned_v3.csv), as produced by
clean_ppd_v3.py.

Target: PPD (1 = EPDS Score >= 13, 0 = otherwise)
28 predictors -- see encoding_reference.md / Encoding_Reference_Guide.docx
"""
import pandas as pd
import numpy as np
from sklearn.metrics import (classification_report, confusion_matrix,
                              accuracy_score, f1_score, roc_auc_score,
                              precision_score, recall_score, roc_curve)
from xgboost import XGBClassifier
import json

RANDOM_STATE = 42

# ---------------------------------------------------------------
# 1. Load pre-cleaned data
# ---------------------------------------------------------------
train = pd.read_csv('C:/Users/user1/Downloads/files/train_cleaned_v3.csv')
val = pd.read_csv('C:/Users/user1/Downloads/files/validation_cleaned_v3.csv')

X_train = train.drop(columns=['PPD'])
y_train = train['PPD']
X_val = val.drop(columns=['PPD'])
y_val = val['PPD']

print(f"Train: {X_train.shape}, Val: {X_val.shape}")
print(f"Train PPD rate: {y_train.mean():.3f}, Val PPD rate: {y_val.mean():.3f}")

# ---------------------------------------------------------------
# 2. Train XGBoost binary classifier
# ---------------------------------------------------------------
# class imbalance is mild (316 vs 244 in train), use scale_pos_weight anyway
scale_pos_weight = (y_train == 0).sum() / (y_train == 1).sum()

model = XGBClassifier(
    n_estimators=300,
    max_depth=4,
    learning_rate=0.05,
    subsample=0.8,
    colsample_bytree=0.8,
    scale_pos_weight=scale_pos_weight,
    objective='binary:logistic',
    eval_metric='logloss',
    random_state=RANDOM_STATE,
    n_jobs=-1
)

model.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)

# ---------------------------------------------------------------
# 3. Evaluate on validation set
# ---------------------------------------------------------------
y_pred = model.predict(X_val)
y_proba = model.predict_proba(X_val)[:, 1]

acc = accuracy_score(y_val, y_pred)
f1 = f1_score(y_val, y_pred)
precision = precision_score(y_val, y_pred)
recall = recall_score(y_val, y_pred)
auc = roc_auc_score(y_val, y_proba)

print("\n" + "="*60)
print("VALIDATION SET EVALUATION")
print("="*60)
print(f"Accuracy:   {acc:.4f}")
print(f"Precision:  {precision:.4f}")
print(f"Recall:     {recall:.4f}")
print(f"F1 score:   {f1:.4f}")
print(f"ROC-AUC:    {auc:.4f}")

print("\nClassification report:")
print(classification_report(y_val, y_pred, target_names=['No PPD (0)', 'PPD (1)']))

cm = confusion_matrix(y_val, y_pred)
cm_df = pd.DataFrame(cm, index=['Actual: No PPD', 'Actual: PPD'],
                      columns=['Pred: No PPD', 'Pred: PPD'])
print("Confusion matrix:")
print(cm_df)

# ---------------------------------------------------------------
# 4. Feature importance
# ---------------------------------------------------------------
importance = pd.DataFrame({
    'feature': X_train.columns,
    'importance': model.feature_importances_
}).sort_values('importance', ascending=False)

print("\nFeature importance (all 28 features):")
print(importance.to_string(index=False))

# ---------------------------------------------------------------
# 5. Save artifacts
# ---------------------------------------------------------------
model.save_model('C:/Users/user1/Downloads/files/ppd_xgboost_binary_model.json')
importance.to_csv('C:/Users/user1/Downloads/files/feature_importance_binary.csv', index=False)
cm_df.to_csv('C:/Users/user1/Downloads/files/confusion_matrix_binary.csv')

fpr, tpr, thresholds = roc_curve(y_val, y_proba)
roc_df = pd.DataFrame({'fpr': fpr, 'tpr': tpr, 'threshold': thresholds})
roc_df.to_csv('C:/Users/user1/Downloads/files/roc_curve_data.csv', index=False)

metrics = {
    'accuracy': acc,
    'precision': precision,
    'recall': recall,
    'f1': f1,
    'roc_auc': auc,
    'n_train': int(X_train.shape[0]),
    'n_val': int(X_val.shape[0]),
    'n_features': int(X_train.shape[1]),
    'scale_pos_weight_used': float(scale_pos_weight)
}
with open('C:/Users/user1/Downloads/files/metrics_binary.json', 'w') as f:
    json.dump(metrics, f, indent=2)

print("\nSaved: ppd_xgboost_binary_model.json, feature_importance_binary.csv, "
      "confusion_matrix_binary.csv, roc_curve_data.csv, metrics_binary.json")
