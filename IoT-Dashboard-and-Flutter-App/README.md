# 🏠 IoT Smart Garden / Smart Home System

<div align="center">

![IoT Demo System](https://img.shields.io/badge/IoT-Demo_System-blue.svg)
![Status](https://img.shields.io/badge/Status-Production_Ready-green.svg)
![Flutter](https://img.shields.io/badge/Flutter-Web-blue.svg)
![MQTT](https://img.shields.io/badge/MQTT-Synchronized-orange.svg)
![ESP32](https://img.shields.io/badge/ESP32--C3-red.svg)
![Machine Learning](https://img.shields.io/badge/AI-Machine_Learning-purple.svg)

**Hệ thống IoT hoàn chỉnh tích hợp AI dự đoán cháy nổ, Web Dashboard (Flutter), Điều khiển Giọng nói và ESP32-C3**

[🚀 Quick Start](#-quick-start) • [📋 Features](#-features) • [🏗️ Architecture](#️-architecture) • [🛠️ Installation](#️-installation) • [🔧 Hardware Setup](#-hardware-setup)

</div>

---

## 📋 **Features**

### 📱 **Flutter Web Dashboard**
- ✅ **Giao diện người dùng** thiết kế với Material Design 3.
- ✅ **Giám sát thời gian thực** (Nhiệt độ, Độ ẩm, Khí Gas MQ-2).
- ✅ **Biểu đồ lịch sử** hiển thị dữ liệu theo thời gian.
- ✅ **Điều khiển thiết bị** (Đèn ngoài sân, Đèn phòng khách, Quạt, Còi) áp dụng cơ chế optimistic UI.
- ✅ **Cấu hình WiFi từ xa** qua ứng dụng, không cần nạp lại code cho mạch.
- ✅ **Điều khiển bằng giọng nói tiếng Việt** sử dụng Web Speech API (Hỗ trợ điều khiển từng thiết bị hoặc bật/tắt toàn bộ thiết bị cùng lúc).

### 🤖 **ESP32-C3 Hardware**
- ✅ **ESP32-C3 Super Mini** firmware điều khiển thiết bị.
- ✅ **Cơ chế WiFi Auto-Reconnect:** Lưu trữ vòng lặp tới 3 mạng WiFi. Tự động chuyển đổi và tìm kiếm mạng khi mất kết nối.
- ✅ **Giao tiếp MQTT** với broker công cộng (HiveMQ).
- ✅ **Tích hợp cảm biến:** (DHT22, MQ-2, PIR).
- ✅ **Chế độ Tự động (Auto Mode):** Nhận diện chuyển động bằng PIR để bật tắt đèn ngoài sân, logic chạy độc lập trên thiết bị.

### 🧠 **AI & Machine Learning Server**
- ✅ **Dự đoán rủi ro cháy nổ** theo thời gian thực.
- ✅ **API Server (Python)** tích hợp model AI phân tích dữ liệu Khí Gas và Nhiệt độ.
- ✅ **Tự động kích hoạt chuông cảnh báo (Buzzer)** và màn hình khẩn cấp khi hệ thống đánh giá mức độ rủi ro cao.

---

## 🏗️ **System Architecture**

### 📊 **Overall System Diagram**

```mermaid
graph TB
    subgraph "🏠 Smart Home System"
        APP[📱 Flutter Web App<br/>Điều khiển & Theo dõi]
        VOICE[🎤 Nhận diện Giọng nói]
        APP --- VOICE
        
        subgraph "☁️ Cloud / Broker"
            BROKER[🔌 MQTT Broker<br/>HiveMQ Public]
        end
        
        subgraph "🧠 AI Server"
            ML[🐍 Python ML Server<br/>Dự đoán Cháy nổ]
        end
        
        subgraph "🔧 Device Layer"
            ESP[🤖 ESP32-C3 Super Mini<br/>Sensors + Relays]
        end
    end
    
    APP <-->|MQTT (WebSocket)| BROKER
    ESP <-->|MQTT (TCP)| BROKER
    APP -->|HTTP POST| ML
    ML -->|Cảnh báo| APP
    
    style APP fill:#4A90E2,color:#fff
    style BROKER fill:#F5A623,color:#fff
    style ESP fill:#D0021B,color:#fff
    style ML fill:#9013FE,color:#fff
```

### 🗂️ **Project Structure**

```
📦 NCKH Project
├── 📱 IoT-Dashboard-and-Flutter-App/ # Thư mục chứa Frontend
│   ├── app_flutter/                  # Flutter Web Application
│   │   ├── lib/
│   │   │   ├── main.dart             # Giao diện chính và kết nối MQTT
│   │   │   └── voice_service.dart    # Logic xử lý nhận diện giọng nói
│   │   └── pubspec.yaml
│   └── README_APP_DOCUMENTATION.md   # Tài liệu chi tiết luồng xử lý ứng dụng
│
├── 🤖 firmware_esp32_super_mini/     # Code Firmware cho vi điều khiển
│   └── esp32_super_mini_enhanced.ino # Source C++ chính cho ESP32-C3
│
└── 🧠 src/                           # Backend / AI Server
    └── ml_server.py                  # Server Python chạy mô hình dự báo
```

---

## 🚀 **Quick Start**

### 1️⃣ **Chạy Machine Learning Server**
Mở terminal tại thư mục chứa file python:
```bash
cd src
python ml_server.py
# Server chạy ở http://localhost:5000
```

### 2️⃣ **Chạy Flutter Web App**
Mở terminal mới tại thư mục Flutter:
```bash
cd IoT-Dashboard-and-Flutter-App/app_flutter
flutter run -d chrome
```

---

## 🔧 **Hardware Setup (ESP32-C3 Super Mini)**

### 🔌 **Wiring Diagram**

```text
ESP32-C3 Pinout:
├── 📡 DHT22 Sensor (Nhiệt độ & Độ ẩm)
│   ├── VCC → 3.3V
│   ├── GND → GND
│   └── Data → GPIO 3
│
├── 💨 MQ-2 Sensor (Khí Gas)
│   ├── VCC → 5V
│   ├── GND → GND
│   └── A0 → GPIO 2 (ADC1_CH1)
│
├── 🏃 PIR Sensor (Chuyển động)
│   ├── VCC → 3.3V
│   ├── GND → GND
│   └── OUT → GPIO 4
│
├── 💡 Relay Module (Điều khiển thiết bị)
│   ├── Relay 1 (Đèn ngoài sân) → GPIO 21
│   ├── Relay 2 (Đèn phòng khách) → GPIO 20
│   └── Relay 3 (Quạt) → GPIO 8
│
└── 🔊 Buzzer (Còi báo động)
    ├── VCC → GPIO 10
    └── GND → GND
```

### ⚙️ **Configuration Steps**
Sử dụng **Arduino IDE**:
1. Cài đặt các thư viện: `DHT sensor library`, `PubSubClient`, `Preferences`, `ArduinoJson`.
2. Truy cập **Tools > Board**, chọn **ESP32C3 Dev Module**.
3. Cắm cáp Type-C vào ESP32-C3, chọn đúng Port và nhấn **Upload**.
*(Lưu ý: Mạch đã được code cơ chế Fallback WiFi, ở lần đầu khởi động nếu chưa có mạng, mạch sẽ cố gắng dùng cấu hình gốc, sau đó bạn có thể dùng App Flutter để set mạng mới).*

---

## 📄 **License & Attribution**

This project is licensed under the **MIT License**.

### 🎉 **Acknowledgments**
- **HiveMQ** - Free public MQTT broker
- **Flutter Team** - Excellent framework  
- **Thủ Dầu Một University (TDMU)** - Educational support

**👨‍💻 Author:** Nguyễn Trung Kiệt  
**🏫 Institution:** Thủ Dầu Một University (TDMU)  
**📅 Year:** 2025