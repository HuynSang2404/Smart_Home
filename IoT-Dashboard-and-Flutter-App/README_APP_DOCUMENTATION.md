# TÀI LIỆU ỨNG DỤNG SMART GARDEN / SMART HOME (FLUTTER)

Tài liệu này hướng dẫn cách khởi chạy ứng dụng, liệt kê các tính năng hiện có và giải thích cơ chế hoạt động (logic xử lý) đằng sau từng tính năng.

---

## PHẦN 1: CÁCH CHẠY ỨNG DỤNG

Hệ thống bao gồm 4 thành phần chính cần khởi chạy theo thứ tự:

| # | Thành phần | Port | File chính |
|---|-----------|------|-----------|
| 1 | ESP32-C3 Firmware | — | `sketch_mar10c.ino` |
| 2 | Backend Server (Node.js) | 8080 | `server_local.js` |
| 3 | ML Prediction Server (Flask) | 5000 | `ml_server.py` |
| 4 | Flutter Web App | auto | `app_flutter/lib/main.dart` |

### Bước 1: Nạp Firmware cho ESP32-C3 Super Mini (chỉ cần làm 1 lần)
- Mở file `sketch_mar10c.ino` bằng Arduino IDE.
- Chọn Board: **ESP32C3 Dev Module**, Port: COM tương ứng.
- Nhấn **Upload**. Sau khi nạp xong, ESP32 tự động kết nối WiFi và MQTT broker (`broker.emqx.io`).

### Bước 2: Chạy Backend Server (Node.js + PostgreSQL)
Backend lưu trữ dữ liệu cảm biến, lịch sử điều khiển và gửi cảnh báo Telegram.
- **Yêu cầu:** PostgreSQL đang chạy trên `localhost:5432`, database `iot_dashboard` đã tồn tại.
- Mở terminal:
  ```bash
  cd IoT-Dashboard-and-Flutter-App/backend
  npm start
  ```
- Khi thấy `🚀 Server running on http://0.0.0.0:8080` là thành công.

### Bước 3: Chạy Machine Learning Server (Flask + XGBoost)
Server này nhận dữ liệu cảm biến từ Flutter App và trả về kết quả dự đoán nguy cơ cháy.
- Mở terminal thứ 2:
  ```bash
  cd src
  python ml_server.py
  ```
- Khi thấy `[ML] Prediction Server starting on http://localhost:5000` là thành công.

### Bước 4: Chạy Flutter Web App
- Mở terminal thứ 3:
  ```bash
  cd IoT-Dashboard-and-Flutter-App/app_flutter
  flutter run -d chrome
  ```
- App sẽ tự mở trên trình duyệt Chrome.
- Đảm bảo ESP32 đã được cấp nguồn và kết nối WiFi/MQTT thành công.

> **Lưu ý:** Cả 3 server (Backend, ML, Flutter) phải chạy đồng thời. Nếu thiếu Backend → app không lưu được lịch sử. Nếu thiếu ML Server → tính năng "Cảnh báo cháy AI" sẽ hiển thị "Đang chờ dữ liệu...".

---

## PHẦN 2: CÁC TÍNH NĂNG CỦA ỨNG DỤNG

1. **Giám sát thông số môi trường (Real-time):** Hiển thị trực tiếp Nhiệt độ, Độ ẩm và Nồng độ Khí Gas.
2. **Biểu đồ dữ liệu:** Xem lại biến động của nhiệt độ và độ ẩm theo thời gian.
3. **Điều khiển thiết bị thủ công:** Bật/tắt Đèn ngoài sân, Đèn phòng khách, Quạt (Motor), và Còi báo động (Buzzer).
4. **Chế độ tự động (Auto Mode):** Đèn ngoài sân tự động bật khi có chuyển động và tự tắt sau 30 giây.
5. **Cảnh báo cháy nổ:** Cảnh báo nguy cơ cháy nổ dựa trên dữ liệu cảm biến phân tích qua mô hình Machine Learning.
6. **Điều khiển bằng giọng nói tiếng Việt:** Ra lệnh bằng giọng nói điều khiển từng thiết bị (VD: "Bật đèn phòng khách", "Tắt quạt") hoặc điều khiển toàn bộ hệ thống cùng lúc (VD: "Bật tất cả", "Tắt tất cả").
7. **Cấu hình WiFi từ xa:** Thay đổi và lưu tối đa 3 mạng WiFi cho thiết bị ESP32 trực tiếp từ ứng dụng.

---

## PHẦN 3: CÁCH XỬ LÝ (LOGIC) CỦA TỪNG TÍNH NĂNG

### 1. Giao tiếp thông qua MQTT
- **Cách xử lý:** Ứng dụng dùng giao thức MQTT (qua broker `broker.emqx.io`) làm "cầu nối". App Flutter sẽ `subscribe` (đăng ký) các topic như `/sensor/state`, `/device/state` để nhận dữ liệu, và `publish` (gửi) lệnh vào `/device/cmd`. ESP32 cũng làm tương tự ở chiều ngược lại.

### 2. Giám sát & Biểu đồ
- **Cách xử lý:** 
  - Mỗi 2 giây, ESP32 đọc cảm biến (DHT22, MQ-2) và gửi chuỗi JSON lên MQTT.
  - App Flutter nhận chuỗi này, parse JSON và cập nhật lên giao diện (gọi `setState`).
  - Dữ liệu đồng thời có thể được đẩy vào mảng dữ liệu nội bộ trên App (hoặc lấy từ Backend API qua HTTP) để vẽ đồ thị `LineChart`.

### 3. Điều khiển thiết bị thủ công
- **Cách xử lý:** 
  - Khi người dùng nhấn nút gạt (Switch) trên App, App sẽ thay đổi trạng thái UI trước để cập nhật giao diện (cơ chế *optimistic UI update*).
  - Đồng thời, App đóng gói lệnh thành JSON (VD: `{"light2":"ON"}`) và gửi qua MQTT.
  - ESP32 nhận lệnh, bật/tắt chân GPIO tương ứng (như chân 20 cho Đèn phòng khách), sau đó gửi ngược lại trạng thái thực tế để App đồng bộ.

### 4. Chế độ tự động (Auto Mode)
- **Cách xử lý:** 
  - Khi gạt công tắc "Chế độ tự động", App gửi lệnh `{"mode":"AUTO"}` xuống ESP32.
  - **Logic chính nằm ở ESP32:** Trong hàm `loop()`, ESP32 liên tục đọc cảm biến chuyển động (PIR). Nếu phát hiện chuyển động (kèm chống nhiễu `debounce`), nó tự bật chân GPIO Đèn ngoài sân và ghi nhớ thời gian (`millis()`). Sau 30 giây kể từ lần phát hiện cuối cùng, ESP32 tự tắt đèn. 
  - Khi ở mode AUTO, người dùng không thể bấm bật/tắt Đèn ngoài sân trên App.

### 5. Cảnh báo cháy nổ
- **Cách xử lý:**
  - Cảm biến MQ-2 và DHT22 thu thập dữ liệu (khí gas, nhiệt độ).
  - Dữ liệu được App (hoặc Backend) chuyển tới `ml_server.py` qua API HTTP `POST /predict`.
  - Server chạy mô hình học máy, trả về phần trăm rủi ro. 
  - Nếu rủi ro cao (cháy/khói), App sẽ hiển thị màn hình cảnh báo đỏ. Đồng thời, ESP32 nhận lệnh tự động kích hoạt Còi báo động (Buzzer) phát âm thanh liên tục cho đến khi mức Gas/Nhiệt độ giảm xuống ngưỡng an toàn.

### 6. Điều khiển bằng giọng nói
- **Cách xử lý:**
  - Sử dụng **Web Speech API** của trình duyệt (thông qua package `speech_to_text`).
  - **Giảm độ trễ:** App xử lý các kết quả tạm thời (`interimResults`). Ngay khi người dùng đang nói, App liên tục kiểm tra chuỗi chữ bằng **Biểu thức chính quy (Regex)** hoặc tiệm cận từ (proximity matching) để bắt các lệnh từ khóa (VD: "bật", "quạt", "tắt", "đèn", "phòng", "tất cả").
  - Khi regex hoặc thuật toán khớp thành công, App lập tức thực thi lệnh (gửi 1 hoặc nhiều gói MQTT đồng thời, VD gửi 3 gói bật đèn ngoài, đèn trong, và quạt cho lệnh "Bật tất cả"), sau đó chủ động **hủy (abort) session nhận diện hiện tại** và khởi động lại session mới. Điều này ngăn chặn việc App nhận diện một câu quá dài dẫn đến lặp lệnh hoặc bị trễ do chờ người dùng ngừng nói.

### 7. Cấu hình WiFi từ xa
- **Cách xử lý:**
  - Từ trang "Cài đặt WiFi", App gửi chuỗi JSON chứa `{ "wifi_set": { "ssid": "...", "password": "..." } }` qua MQTT.
  - ESP32 nhận được, sẽ chèn WiFi mới này lên đầu danh sách bộ nhớ Flash (tối đa 3 mạng cũ, mạng thứ 4 bị đẩy ra), sau đó tự động `ESP.restart()`.
  - Lúc khởi động lên, ESP32 sẽ cố gắng kết nối mạng ở vị trí số 1. Nếu rớt mạng hoặc sai pass, ESP32 sẽ chuyển qua thử mạng số 2, số 3, rồi quay lại. Luồng xử lý này hoạt động ẩn trong `loop()` mỗi 15 giây mà không làm treo thiết bị (không dùng AP Mode).
