"""
Fire / Gas Leak Early Warning — Flask REST API Server
=====================================================
Serves ML predictions at http://localhost:5000/predict
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
from predict import predict_fire_risk

app = Flask(__name__)
CORS(app)  # Allow cross-origin requests from Flutter web


@app.route("/predict", methods=["POST"])
def predict():
    data = request.get_json(force=True)
    result = predict_fire_risk(data)
    return jsonify({"prediction": result})


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "ml-prediction"})


if __name__ == "__main__":
    print("[ML] Prediction Server starting on http://localhost:5000")
    app.run(host="0.0.0.0", port=5000, debug=False)
