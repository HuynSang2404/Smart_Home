"""
Fire / Gas Leak Early Warning System — Prediction Module
========================================================
Provides the real-time prediction function and standalone test.
"""

import os
import logging
import numpy as np
import pandas as pd
import joblib

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR = os.path.join(BASE_DIR, "models")

# Feature order expected by the model
FEATURE_ORDER = [
    "sensor1", "sensor2", "sensor3", "sensor4",
    "sensor5", "sensor6", "sensor7", "sensor8",
    "temperature", "humidity", "time",
]

# ── Lazy-loaded globals ──────────────────────────────────────────────────────
_model = None
_scaler = None


def _load_artifacts():
    """Load model and scaler once."""
    global _model, _scaler
    if _model is None:
        model_path = os.path.join(MODELS_DIR, "fire_warning_model.pkl")
        scaler_path = os.path.join(MODELS_DIR, "scaler.pkl")
        _model = joblib.load(model_path)
        _scaler = joblib.load(scaler_path)
        logger.info("Loaded model and scaler for prediction")


def predict_fire_risk(sensor_data: dict) -> str:
    """
    Predict fire / gas leak risk from sensor readings.

    Parameters
    ----------
    sensor_data : dict
        Keys: sensor1..sensor8, temperature, humidity (time is optional).
        Example::

            {
                "sensor1": 0.52, "sensor2": 0.61, "sensor3": 0.44,
                "sensor4": 0.70, "sensor5": 0.35, "sensor6": 0.28,
                "sensor7": 0.41, "sensor8": 0.50,
                "temperature": 35, "humidity": 60
            }

    Returns
    -------
    str
        "🔥 Fire Risk Detected" or "✅ Safe Condition"
    """
    _load_artifacts()

    # Build feature vector in correct order
    if "time" not in sensor_data:
        sensor_data["time"] = 0.0  # default if not provided

    features = [sensor_data.get(f, 0.0) for f in FEATURE_ORDER]
    X = np.array(features).reshape(1, -1)

    # Scale
    X_scaled = _scaler.transform(X)

    # Predict
    prediction = _model.predict(X_scaled)[0]
    proba = None
    if hasattr(_model, "predict_proba"):
        proba = _model.predict_proba(X_scaled)[0][1]

    if prediction == 1:
        result = "🔥 Fire Risk Detected"
    else:
        result = "✅ Safe Condition"

    if proba is not None:
        result += f"  (confidence: {max(proba, 1-proba)*100:.1f}%)"

    logger.info("Prediction: %s", result)
    return result


# ── Standalone test ──────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("=" * 55)
    print("  FIRE / GAS LEAK EARLY WARNING — Prediction Test")
    print("=" * 55)

    # Test case 1 — typical input
    test1 = {
        "sensor1": 0.52, "sensor2": 0.61, "sensor3": 0.44,
        "sensor4": 0.70, "sensor5": 0.35, "sensor6": 0.28,
        "sensor7": 0.41, "sensor8": 0.50,
        "temperature": 35, "humidity": 60,
    }
    print(f"\nTest 1 input: {test1}")
    print(f"Result: {predict_fire_risk(test1)}")

    # Test case 2 — high sensor values
    test2 = {
        "sensor1": 50000, "sensor2": 40000, "sensor3": 8000,
        "sensor4": 7000, "sensor5": 2000, "sensor6": 2500,
        "sensor7": 10000, "sensor8": 10000,
        "temperature": 30000, "humidity": 12000,
    }
    print(f"\nTest 2 input: {test2}")
    print(f"Result: {predict_fire_risk(test2)}")

    print("\n" + "=" * 55)
