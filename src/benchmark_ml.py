"""
Benchmark ML Prediction Latency
================================
Đo thời gian phản hồi ML API (Flask /predict endpoint).
Chạy: python benchmark_ml.py
Yêu cầu: ML server đang chạy tại localhost:5000
"""

import time
import requests
import statistics
import json

ML_URL = "http://localhost:5000/predict"
NUM_TESTS = 20

# Các test case mô phỏng dữ liệu thực tế từ cảm biến
test_cases = [
    # Case 1: Điều kiện bình thường
    {
        "sensor1": 200, "sensor2": 150, "sensor3": 50,
        "sensor4": 30, "sensor5": 28, "sensor6": 65,
        "sensor7": 500, "sensor8": 160,
        "temperature": 28, "humidity": 65,
    },
    # Case 2: Gas hơi cao
    {
        "sensor1": 1200, "sensor2": 900, "sensor3": 300,
        "sensor4": 250, "sensor5": 30, "sensor6": 55,
        "sensor7": 400, "sensor8": 960,
        "temperature": 30, "humidity": 55,
    },
    # Case 3: Nguy cơ cháy cao
    {
        "sensor1": 5000, "sensor2": 4000, "sensor3": 800,
        "sensor4": 700, "sensor5": 45, "sensor6": 30,
        "sensor7": 200, "sensor8": 4000,
        "temperature": 45, "humidity": 30,
    },
    # Case 4: Nhiệt độ cao, gas thấp
    {
        "sensor1": 300, "sensor2": 200, "sensor3": 80,
        "sensor4": 60, "sensor5": 40, "sensor6": 40,
        "sensor7": 600, "sensor8": 240,
        "temperature": 40, "humidity": 40,
    },
]


def benchmark():
    print("=" * 60)
    print("  BENCHMARK ML PREDICTION LATENCY")
    print(f"  URL: {ML_URL}")
    print(f"  Số lần đo: {NUM_TESTS}")
    print("=" * 60)

    # Check ML server
    try:
        r = requests.get("http://localhost:5000/health", timeout=5)
        print(f"\n✅ ML Server status: {r.json()}")
    except Exception as e:
        print(f"\n❌ ML Server không khả dụng: {e}")
        print("   Hãy chạy: python ml_server.py")
        return

    latencies = []

    for i in range(NUM_TESTS):
        test_data = test_cases[i % len(test_cases)]

        start = time.perf_counter()
        try:
            resp = requests.post(
                ML_URL,
                json=test_data,
                headers={"Content-Type": "application/json"},
                timeout=10,
            )
            end = time.perf_counter()

            latency_ms = (end - start) * 1000
            latencies.append(latency_ms)

            result = resp.json().get("prediction", "N/A")
            print(f"  [{i+1:2d}/{NUM_TESTS}] {latency_ms:8.2f} ms | {result[:50]}")
        except Exception as e:
            print(f"  [{i+1:2d}/{NUM_TESTS}] ERROR: {e}")

    if latencies:
        print("\n" + "=" * 60)
        print("  KẾT QUẢ ĐO ML PREDICTION LATENCY")
        print("=" * 60)
        print(f"  Số lần đo thành công : {len(latencies)}/{NUM_TESTS}")
        print(f"  Trung bình (mean)    : {statistics.mean(latencies):8.2f} ms")
        print(f"  Trung vị (median)    : {statistics.median(latencies):8.2f} ms")
        print(f"  Nhỏ nhất (min)       : {min(latencies):8.2f} ms")
        print(f"  Lớn nhất (max)       : {max(latencies):8.2f} ms")
        if len(latencies) > 1:
            print(f"  Độ lệch chuẩn (std) : {statistics.stdev(latencies):8.2f} ms")
        print("=" * 60)

        # Ghi kết quả ra file CSV
        csv_path = "benchmark_ml_results.csv"
        with open(csv_path, "w", encoding="utf-8") as f:
            f.write("test_number,latency_ms,prediction\n")
            for idx, lat in enumerate(latencies):
                f.write(f"{idx+1},{lat:.2f},ok\n")
        print(f"\n📁 Kết quả chi tiết đã lưu: {csv_path}")


if __name__ == "__main__":
    benchmark()
