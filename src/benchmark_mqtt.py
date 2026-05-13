"""
Benchmark MQTT Round-Trip Latency
==================================
Đo thời gian phản hồi MQTT bằng cách:
1. Subscribe topic phản hồi
2. Publish message có chứa timestamp
3. Đo thời gian nhận được phản hồi

Chạy: python benchmark_mqtt.py
Yêu cầu: MQTT broker online (broker.emqx.io)
"""

import time
import json
import statistics
import paho.mqtt.client as mqtt

BROKER = "broker.emqx.io"
PORT = 1883
TOPIC_CMD = "demo/room1/device/cmd"       # Lệnh điều khiển
TOPIC_STATE = "demo/room1/device/state"    # Phản hồi trạng thái
TOPIC_SENSOR = "demo/room1/sensor/state"   # Dữ liệu cảm biến
TOPIC_PING = "demo/room1/benchmark/ping"   # Topic benchmark riêng
TOPIC_PONG = "demo/room1/benchmark/pong"

NUM_TESTS = 20

# ============ Test 1: MQTT Round-trip (publish → subscribe) ============

class MQTTBenchmark:
    def __init__(self):
        self.client = mqtt.Client(client_id=f"benchmark_{int(time.time())}")
        self.latencies_roundtrip = []
        self.latencies_sensor = []
        self.send_time = None
        self.waiting = False
        self.sensor_count = 0
        self.sensor_timestamps = []
        
    def on_connect(self, client, userdata, flags, rc):
        if rc == 0:
            print("✅ Kết nối MQTT broker thành công")
            client.subscribe(TOPIC_PONG)
            client.subscribe(TOPIC_SENSOR)
            client.subscribe(TOPIC_STATE)
        else:
            print(f"❌ Kết nối thất bại: rc={rc}")
    
    def on_message(self, client, userdata, msg):
        recv_time = time.perf_counter()
        topic = msg.topic
        
        if topic == TOPIC_PONG and self.waiting:
            # Round-trip latency
            latency = (recv_time - self.send_time) * 1000
            self.latencies_roundtrip.append(latency)
            self.waiting = False
            
        elif topic == TOPIC_SENSOR:
            # Sensor data received - ghi nhận thời điểm
            self.sensor_count += 1
            self.sensor_timestamps.append(recv_time)
    
    def benchmark_roundtrip(self):
        """Đo MQTT round-trip: publish ping → receive pong"""
        print("\n" + "=" * 60)
        print("  TEST 1: MQTT Round-Trip Latency (Broker Echo)")
        print(f"  Broker: {BROKER}:{PORT}")
        print(f"  Số lần đo: {NUM_TESTS}")
        print("=" * 60)
        
        # Subscribe pong topic - sẽ nhận lại chính message mình gửi
        # Thực ra ta tự publish và subscribe cùng 1 topic để đo round-trip
        self.client.subscribe(TOPIC_PING)
        
        # Override để nhận ping (echo)
        original_handler = self.client.on_message
        def echo_handler(client, userdata, msg):
            recv_time = time.perf_counter()
            if msg.topic == TOPIC_PING and self.waiting:
                latency = (recv_time - self.send_time) * 1000
                self.latencies_roundtrip.append(latency)
                self.waiting = False
            else:
                original_handler(client, userdata, msg)
        self.client.on_message = echo_handler
        
        time.sleep(1)  # Chờ subscribe hoàn tất
        
        for i in range(NUM_TESTS):
            payload = json.dumps({
                "benchmark": True,
                "seq": i + 1,
                "ts": time.time()
            })
            
            self.send_time = time.perf_counter()
            self.waiting = True
            self.client.publish(TOPIC_PING, payload, qos=1)
            
            # Chờ phản hồi tối đa 5 giây
            timeout = time.perf_counter() + 5
            while self.waiting and time.perf_counter() < timeout:
                time.sleep(0.001)
            
            if self.waiting:
                print(f"  [{i+1:2d}/{NUM_TESTS}] TIMEOUT")
                self.waiting = False
            else:
                lat = self.latencies_roundtrip[-1]
                print(f"  [{i+1:2d}/{NUM_TESTS}] {lat:8.2f} ms")
            
            time.sleep(0.2)
        
        self.client.on_message = original_handler
        
        if self.latencies_roundtrip:
            print("\n  KẾT QUẢ MQTT ROUND-TRIP:")
            print(f"  Số lần thành công  : {len(self.latencies_roundtrip)}/{NUM_TESTS}")
            print(f"  Trung bình (mean)  : {statistics.mean(self.latencies_roundtrip):8.2f} ms")
            print(f"  Trung vị (median)  : {statistics.median(self.latencies_roundtrip):8.2f} ms")
            print(f"  Min                : {min(self.latencies_roundtrip):8.2f} ms")
            print(f"  Max                : {max(self.latencies_roundtrip):8.2f} ms")
            if len(self.latencies_roundtrip) > 1:
                print(f"  Std                : {statistics.stdev(self.latencies_roundtrip):8.2f} ms")

    def monitor_sensor_interval(self, duration_sec=30):
        """Đo khoảng cách giữa các message sensor từ ESP32"""
        print("\n" + "=" * 60)
        print("  TEST 2: Sensor Data Interval (cần ESP32 đang chạy)")
        print(f"  Topic: {TOPIC_SENSOR}")
        print(f"  Thời gian theo dõi: {duration_sec} giây")
        print("=" * 60)
        
        self.sensor_count = 0
        self.sensor_timestamps = []
        
        print(f"\n  ⏳ Đang lắng nghe sensor data trong {duration_sec}s...")
        print("     (Nếu ESP32 không chạy, sẽ không có data)")
        
        start = time.time()
        while time.time() - start < duration_sec:
            time.sleep(0.1)
        
        if len(self.sensor_timestamps) >= 2:
            intervals = []
            for j in range(1, len(self.sensor_timestamps)):
                interval = (self.sensor_timestamps[j] - self.sensor_timestamps[j-1]) * 1000
                intervals.append(interval)
            
            print(f"\n  Số message nhận được : {self.sensor_count}")
            print(f"  Khoảng cách TB       : {statistics.mean(intervals):8.2f} ms")
            print(f"  Min interval         : {min(intervals):8.2f} ms")
            print(f"  Max interval         : {max(intervals):8.2f} ms")
        else:
            print(f"\n  ⚠️ Chỉ nhận được {self.sensor_count} message. ESP32 có đang chạy không?")
    
    def run(self):
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
        
        print(f"🔌 Đang kết nối đến {BROKER}:{PORT}...")
        self.client.connect(BROKER, PORT, 60)
        self.client.loop_start()
        
        time.sleep(2)  # Chờ kết nối
        
        # Test 1: Round-trip
        self.benchmark_roundtrip()
        
        # Test 2: Sensor interval (chỉ chạy nếu ESP32 đang online)
        self.monitor_sensor_interval(duration_sec=20)
        
        # Ghi kết quả
        self._save_results()
        
        self.client.loop_stop()
        self.client.disconnect()
    
    def _save_results(self):
        csv_path = "benchmark_mqtt_results.csv"
        with open(csv_path, "w", encoding="utf-8") as f:
            f.write("test_type,test_number,latency_ms\n")
            for idx, lat in enumerate(self.latencies_roundtrip):
                f.write(f"roundtrip,{idx+1},{lat:.2f}\n")
            if len(self.sensor_timestamps) >= 2:
                for j in range(1, len(self.sensor_timestamps)):
                    interval = (self.sensor_timestamps[j] - self.sensor_timestamps[j-1]) * 1000
                    f.write(f"sensor_interval,{j},{interval:.2f}\n")
        print(f"\n📁 Kết quả chi tiết đã lưu: {csv_path}")

        # Tổng kết
        print("\n" + "=" * 60)
        print("  TỔNG KẾT BENCHMARK")
        print("=" * 60)
        if self.latencies_roundtrip:
            mean_rt = statistics.mean(self.latencies_roundtrip)
            print(f"  MQTT Round-trip    : {mean_rt:.0f} ms (mean, {len(self.latencies_roundtrip)} tests)")
        print("=" * 60)


if __name__ == "__main__":
    bench = MQTTBenchmark()
    bench.run()
