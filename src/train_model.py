"""
Fire / Gas Leak Early Warning System — Model Training Module
=============================================================
Trains multiple classifiers, performs hyperparameter tuning,
cross-validation, selects the best model by F1-score, and saves it.
"""

import os
import sys
import logging
import warnings
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split, GridSearchCV, cross_val_score
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.svm import SVC
from xgboost import XGBClassifier
from sklearn.metrics import f1_score
import joblib

warnings.filterwarnings("ignore")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data")
MODELS_DIR = os.path.join(BASE_DIR, "models")

# ── Model definitions ─────────────────────────────────────────────────────────
MODELS = {
    "Logistic Regression": LogisticRegression(max_iter=1000, random_state=42),
    "Random Forest": RandomForestClassifier(random_state=42, n_jobs=-1),
    "Gradient Boosting": GradientBoostingClassifier(random_state=42),
    "XGBoost": XGBClassifier(random_state=42, eval_metric="logloss",
                              use_label_encoder=False, verbosity=0),
    "SVM": SVC(random_state=42, probability=True),
}

# ── Hyperparameter grids (focused for speed) ─────────────────────────────────
PARAM_GRIDS = {
    "Random Forest": {
        "n_estimators": [100, 200],
        "max_depth": [10, 20, None],
        "min_samples_split": [2, 5],
    },
    "XGBoost": {
        "n_estimators": [100, 200],
        "max_depth": [3, 6, 10],
        "learning_rate": [0.05, 0.1],
    },
    "Gradient Boosting": {
        "n_estimators": [100, 200],
        "max_depth": [3, 5],
        "learning_rate": [0.05, 0.1],
    },
}


def load_processed_data() -> tuple[pd.DataFrame, np.ndarray]:
    """Load processed features and target from CSV."""
    X = pd.read_csv(os.path.join(DATA_DIR, "processed_features.csv"))
    y = pd.read_csv(os.path.join(DATA_DIR, "processed_target.csv"))["target"].values
    logger.info("Loaded processed data: %d samples, %d features", len(X), X.shape[1])
    return X, y


def train_and_evaluate_models(X_train, X_test, y_train, y_test) -> pd.DataFrame:
    """
    Train all models, compute F1 on test set, perform 5-fold CV.
    Returns a comparison DataFrame sorted by F1.
    """
    results = []

    for name, model in MODELS.items():
        logger.info("Training %s …", name)

        # Hyperparameter tuning for select models
        if name in PARAM_GRIDS:
            logger.info("  → GridSearchCV for %s", name)
            gs = GridSearchCV(model, PARAM_GRIDS[name], cv=3, scoring="f1",
                              n_jobs=-1, verbose=0)
            gs.fit(X_train, y_train)
            best_model = gs.best_estimator_
            logger.info("  → Best params: %s", gs.best_params_)
        else:
            best_model = model
            best_model.fit(X_train, y_train)

        # Test-set F1
        y_pred = best_model.predict(X_test)
        test_f1 = f1_score(y_test, y_pred)

        # 5-fold cross-validation
        cv_scores = cross_val_score(best_model, X_train, y_train,
                                     cv=5, scoring="f1", n_jobs=-1)

        results.append({
            "Model": name,
            "Test F1": round(test_f1, 4),
            "CV F1 Mean": round(cv_scores.mean(), 4),
            "CV F1 Std": round(cv_scores.std(), 4),
            "model_obj": best_model,
        })
        logger.info("  %s — Test F1: %.4f | CV F1: %.4f ± %.4f",
                     name, test_f1, cv_scores.mean(), cv_scores.std())

    comparison = pd.DataFrame(results).sort_values("Test F1", ascending=False)
    return comparison


def select_best_model(comparison: pd.DataFrame):
    """Select the best model by highest Test F1-score."""
    best_row = comparison.iloc[0]
    best_model = best_row["model_obj"]
    logger.info("🏆 Best model: %s (F1=%.4f)", best_row["Model"], best_row["Test F1"])
    return best_model, best_row["Model"]


def run_training() -> dict:
    """Full training pipeline."""
    os.makedirs(MODELS_DIR, exist_ok=True)

    # Load data
    X, y = load_processed_data()

    # Train-test split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    logger.info("Train: %d  Test: %d", len(X_train), len(X_test))

    # Train & compare
    comparison = train_and_evaluate_models(X_train, X_test, y_train, y_test)

    # Display comparison table
    display_cols = ["Model", "Test F1", "CV F1 Mean", "CV F1 Std"]
    print("\n+======================================================+")
    print("|           MODEL COMPARISON TABLE                     |")
    print("+======================================================+")
    print(comparison[display_cols].to_string(index=False))
    print("+======================================================+\n")

    # Save comparison
    comparison[display_cols].to_csv(
        os.path.join(DATA_DIR, "model_comparison.csv"), index=False)

    # Select & save best model
    best_model, best_name = select_best_model(comparison)
    model_path = os.path.join(MODELS_DIR, "fire_warning_model.pkl")
    joblib.dump(best_model, model_path)
    logger.info("Saved best model to %s", model_path)

    # Save test split for evaluation
    joblib.dump((X_test, y_test), os.path.join(DATA_DIR, "test_split.pkl"))

    return {
        "best_model": best_model,
        "best_name": best_name,
        "comparison": comparison,
        "X_train": X_train, "X_test": X_test,
        "y_train": y_train, "y_test": y_test,
    }


if __name__ == "__main__":
    result = run_training()
    print(f"[OK] Training complete - Best model: {result['best_name']}")
