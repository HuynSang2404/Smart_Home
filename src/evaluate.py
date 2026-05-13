"""
Fire / Gas Leak Early Warning System — Model Evaluation Module
==============================================================
Generates comprehensive evaluation metrics, plots, and reports.
"""

import os
import logging
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")  # non-interactive backend
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score, f1_score, roc_auc_score,
    confusion_matrix, classification_report, roc_curve, precision_recall_curve,
)
import joblib

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data")
MODELS_DIR = os.path.join(BASE_DIR, "models")

# ── Styling ──────────────────────────────────────────────────────────────────
sns.set_theme(style="whitegrid", palette="muted", font_scale=1.1)
plt.rcParams.update({"figure.dpi": 120, "savefig.bbox": "tight"})


def evaluate_model(model, X_test, y_test) -> dict:
    """Compute all evaluation metrics."""
    y_pred = model.predict(X_test)
    y_proba = model.predict_proba(X_test)[:, 1] if hasattr(model, "predict_proba") else None

    metrics = {
        "Accuracy":  accuracy_score(y_test, y_pred),
        "Precision": precision_score(y_test, y_pred),
        "Recall":    recall_score(y_test, y_pred),
        "F1-Score":  f1_score(y_test, y_pred),
        "ROC-AUC":   roc_auc_score(y_test, y_proba) if y_proba is not None else None,
    }

    print("\n╔══════════════════════════════════════════════╗")
    print("║         EVALUATION METRICS                   ║")
    print("╠══════════════════════════════════════════════╣")
    for k, v in metrics.items():
        if v is not None:
            print(f"║  {k:<12s} : {v:.4f}                        ║")
    print("╚══════════════════════════════════════════════╝\n")

    # Classification report
    report = classification_report(y_test, y_pred,
                                    target_names=["Safe", "Dangerous"])
    print("Classification Report:")
    print(report)

    return {"metrics": metrics, "y_pred": y_pred, "y_proba": y_proba, "report": report}


def plot_confusion_matrix(y_test, y_pred, save_path=None):
    """Plot and save confusion matrix."""
    cm = confusion_matrix(y_test, y_pred)
    fig, ax = plt.subplots(figsize=(6, 5))
    sns.heatmap(cm, annot=True, fmt="d", cmap="Blues",
                xticklabels=["Safe", "Dangerous"],
                yticklabels=["Safe", "Dangerous"], ax=ax)
    ax.set_xlabel("Predicted")
    ax.set_ylabel("Actual")
    ax.set_title("Confusion Matrix")
    if save_path:
        fig.savefig(save_path)
        logger.info("Saved confusion matrix → %s", save_path)
    plt.close(fig)


def plot_roc_curve(y_test, y_proba, save_path=None):
    """Plot ROC curve."""
    if y_proba is None:
        logger.warning("No probabilities available — skipping ROC curve")
        return
    fpr, tpr, _ = roc_curve(y_test, y_proba)
    auc_val = roc_auc_score(y_test, y_proba)

    fig, ax = plt.subplots(figsize=(7, 5))
    ax.plot(fpr, tpr, linewidth=2, label=f"ROC (AUC = {auc_val:.4f})")
    ax.plot([0, 1], [0, 1], "k--", linewidth=1, label="Random")
    ax.set_xlabel("False Positive Rate")
    ax.set_ylabel("True Positive Rate")
    ax.set_title("ROC Curve")
    ax.legend(loc="lower right")
    if save_path:
        fig.savefig(save_path)
        logger.info("Saved ROC curve → %s", save_path)
    plt.close(fig)


def plot_precision_recall_curve(y_test, y_proba, save_path=None):
    """Plot Precision-Recall curve."""
    if y_proba is None:
        return
    prec, rec, _ = precision_recall_curve(y_test, y_proba)

    fig, ax = plt.subplots(figsize=(7, 5))
    ax.plot(rec, prec, linewidth=2, color="darkorange")
    ax.set_xlabel("Recall")
    ax.set_ylabel("Precision")
    ax.set_title("Precision–Recall Curve")
    if save_path:
        fig.savefig(save_path)
        logger.info("Saved PR curve → %s", save_path)
    plt.close(fig)


def plot_feature_importance(save_path=None):
    """Plot feature importance from saved CSV."""
    imp_path = os.path.join(DATA_DIR, "feature_importance.csv")
    if not os.path.exists(imp_path):
        return
    imp = pd.read_csv(imp_path)

    fig, ax = plt.subplots(figsize=(8, 5))
    sns.barplot(data=imp, x="importance", y="feature", ax=ax, palette="viridis")
    ax.set_title("Feature Importance Ranking")
    ax.set_xlabel("Importance")
    ax.set_ylabel("")
    if save_path:
        fig.savefig(save_path)
        logger.info("Saved feature importance → %s", save_path)
    plt.close(fig)


def run_evaluation():
    """Full evaluation pipeline."""
    # Load model
    model_path = os.path.join(MODELS_DIR, "fire_warning_model.pkl")
    model = joblib.load(model_path)
    logger.info("Loaded model from %s", model_path)

    # Load test data
    X_test, y_test = joblib.load(os.path.join(DATA_DIR, "test_split.pkl"))

    # Evaluate
    result = evaluate_model(model, X_test, y_test)

    # Plots
    plot_confusion_matrix(y_test, result["y_pred"],
                          os.path.join(DATA_DIR, "confusion_matrix.png"))
    plot_roc_curve(y_test, result["y_proba"],
                   os.path.join(DATA_DIR, "roc_curve.png"))
    plot_precision_recall_curve(y_test, result["y_proba"],
                                os.path.join(DATA_DIR, "precision_recall_curve.png"))
    plot_feature_importance(os.path.join(DATA_DIR, "feature_importance.png"))

    # Save metrics
    metrics_df = pd.DataFrame([result["metrics"]])
    metrics_df.to_csv(os.path.join(DATA_DIR, "evaluation_metrics.csv"), index=False)
    logger.info("✅ Evaluation complete — all plots and metrics saved to %s", DATA_DIR)

    return result


if __name__ == "__main__":
    run_evaluation()
