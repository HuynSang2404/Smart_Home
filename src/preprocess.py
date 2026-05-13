"""
Fire / Gas Leak Early Warning System — Data Preprocessing Module
================================================================
Loads the UCI Gas Sensor Array Drift Dataset (libsvm format),
cleans, transforms, and prepares features for model training.
"""

import os
import logging
import numpy as np
import pandas as pd
from sklearn.datasets import load_svmlight_file
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomForestClassifier
import joblib
from scipy import sparse

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

# ── Paths ────────────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATASET_DIR = os.path.join(BASE_DIR, "Dataset")
DATA_DIR = os.path.join(BASE_DIR, "data")
MODELS_DIR = os.path.join(BASE_DIR, "models")

# Gas class labels in the original dataset
GAS_LABELS = {1: "Ethanol", 2: "Ethylene", 3: "Ammonia",
              4: "Acetaldehyde", 5: "Acetone", 6: "Toluene"}

# Binary mapping: Ethylene (flammable) and Ammonia (toxic) → Dangerous
DANGEROUS_CLASSES = {2, 3}  # Ethylene, Ammonia


def load_all_batches() -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Load all 10 batch .dat files and return (X, y_original, batch_ids)."""
    logger.info("Loading all batch files from %s …", DATASET_DIR)
    X_parts, y_parts, batch_ids = [], [], []

    for batch_num in range(1, 11):
        fpath = os.path.join(DATASET_DIR, f"batch{batch_num}.dat")
        if not os.path.exists(fpath):
            logger.warning("Missing %s — skipped", fpath)
            continue
        X_batch, y_batch = load_svmlight_file(fpath, n_features=128)
        # Convert class;concentration → class only (some files use "class;conc")
        y_classes = np.array([int(str(int(lbl)).split(";")[0]) for lbl in y_batch])
        X_parts.append(X_batch)
        y_parts.append(y_classes)
        batch_ids.append(np.full(len(y_classes), batch_num))
        logger.info("  batch%d: %d samples", batch_num, len(y_classes))

    X = sparse.vstack(X_parts)
    y = np.concatenate(y_parts)
    batches = np.concatenate(batch_ids)
    logger.info("Total samples loaded: %d", len(y))
    return X, y, batches


def create_binary_target(y_original: np.ndarray) -> np.ndarray:
    """Map original gas classes to binary target: 1=Dangerous, 0=Safe."""
    y_binary = np.where(np.isin(y_original, list(DANGEROUS_CLASSES)), 1, 0)
    n_dangerous = y_binary.sum()
    n_safe = len(y_binary) - n_dangerous
    logger.info("Binary target — Dangerous: %d  Safe: %d  (%.1f%% dangerous)",
                n_dangerous, n_safe, 100 * n_dangerous / len(y_binary))
    return y_binary


def select_sensor_features(X_sparse: sparse.spmatrix) -> pd.DataFrame:
    """
    From 128 features (16 sensors × 8 features each), select a
    representative subset that maps to the user's 8 sensor inputs
    plus derived temperature/humidity/time proxies.

    Sensor steady-state responses (DR) = features 1,9,17,25,33,41,49,57
    (first feature of each of the first 8 sensors, 0-indexed: 0,8,16,24,32,40,48,56)
    """
    X_dense = X_sparse.toarray() if sparse.issparse(X_sparse) else X_sparse

    # Indices for 8 sensor steady-state responses (0-indexed)
    sensor_indices = [0, 8, 16, 24, 32, 40, 48, 56]
    sensor_cols = [f"sensor{i+1}" for i in range(8)]

    df = pd.DataFrame(X_dense[:, sensor_indices], columns=sensor_cols)

    # Derive proxy features for temperature, humidity, time
    # Use features from remaining sensors as proxies
    df["temperature"] = X_dense[:, 64]   # Sensor 9 steady-state (proxy)
    df["humidity"] = X_dense[:, 72]      # Sensor 10 steady-state (proxy)
    df["time"] = X_dense[:, 80]          # Sensor 11 steady-state (proxy)

    logger.info("Selected %d features: %s", len(df.columns), list(df.columns))
    return df


def handle_missing_and_duplicates(df: pd.DataFrame) -> pd.DataFrame:
    """Handle missing values and remove duplicates."""
    n_before = len(df)

    # Fill NaN with column median
    if df.isnull().sum().sum() > 0:
        logger.info("Filling %d missing values with column medians",
                     df.isnull().sum().sum())
        df = df.fillna(df.median())

    # Remove duplicates
    df = df.drop_duplicates()
    n_removed = n_before - len(df)
    if n_removed > 0:
        logger.info("Removed %d duplicate rows", n_removed)
    else:
        logger.info("No duplicate rows found")

    return df


def remove_outliers_iqr(df: pd.DataFrame, y: np.ndarray,
                        factor: float = 3.0) -> tuple[pd.DataFrame, np.ndarray]:
    """Remove outliers using IQR method."""
    Q1 = df.quantile(0.25)
    Q3 = df.quantile(0.75)
    IQR = Q3 - Q1
    lower = Q1 - factor * IQR
    upper = Q3 + factor * IQR

    mask = ((df >= lower) & (df <= upper)).all(axis=1)
    n_removed = (~mask).sum()
    logger.info("Removed %d outlier rows (IQR factor=%.1f)", n_removed, factor)
    return df[mask].reset_index(drop=True), y[mask.values]


def scale_features(df: pd.DataFrame) -> tuple[pd.DataFrame, StandardScaler]:
    """StandardScaler normalization."""
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(df)
    df_scaled = pd.DataFrame(X_scaled, columns=df.columns)
    logger.info("Features scaled with StandardScaler")
    return df_scaled, scaler


def feature_importance_analysis(X: pd.DataFrame, y: np.ndarray) -> pd.DataFrame:
    """Compute feature importance using Random Forest."""
    rf = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1)
    rf.fit(X, y)
    importance = pd.DataFrame({
        "feature": X.columns,
        "importance": rf.feature_importances_
    }).sort_values("importance", ascending=False).reset_index(drop=True)
    logger.info("Top 5 important features:\n%s", importance.head().to_string())
    return importance


def run_preprocessing() -> dict:
    """
    Full preprocessing pipeline. Returns a dict with all processed objects.
    """
    os.makedirs(DATA_DIR, exist_ok=True)
    os.makedirs(MODELS_DIR, exist_ok=True)

    # 1. Load data
    X_raw, y_original, batch_ids = load_all_batches()

    # 2. Binary target
    y_binary = create_binary_target(y_original)

    # 3. Feature selection
    df = select_sensor_features(X_raw)

    # 4. Handle missing & duplicates
    df = handle_missing_and_duplicates(df)

    # 5. Remove outliers
    df, y_binary = remove_outliers_iqr(df, y_binary, factor=3.0)

    # 6. Scale features
    df_scaled, scaler = scale_features(df)

    # 7. Feature importance
    importance = feature_importance_analysis(df_scaled, y_binary)

    # Save artifacts
    df_scaled.to_csv(os.path.join(DATA_DIR, "processed_features.csv"), index=False)
    pd.Series(y_binary, name="target").to_csv(
        os.path.join(DATA_DIR, "processed_target.csv"), index=False)
    importance.to_csv(os.path.join(DATA_DIR, "feature_importance.csv"), index=False)
    joblib.dump(scaler, os.path.join(MODELS_DIR, "scaler.pkl"))
    logger.info("Saved processed data to %s", DATA_DIR)
    logger.info("Saved scaler to %s", os.path.join(MODELS_DIR, "scaler.pkl"))

    return {
        "X": df_scaled,
        "y": y_binary,
        "scaler": scaler,
        "importance": importance,
        "feature_names": list(df_scaled.columns),
        "batch_ids": batch_ids,
        "y_original": y_original,
        "X_unscaled": df,
    }


if __name__ == "__main__":
    result = run_preprocessing()
    print(f"\nPreprocessing complete — {len(result['X'])} samples, "
          f"{result['X'].shape[1]} features")
    print(f"Class distribution: Safe={int((result['y']==0).sum())}, "
          f"Dangerous={int((result['y']==1).sum())}")
