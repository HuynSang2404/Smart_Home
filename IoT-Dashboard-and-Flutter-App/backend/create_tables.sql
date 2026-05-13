-- =============================================
-- SQL Script để tạo tables cho IoT Dashboard
-- =============================================

-- 1. Bảng lưu thông tin thiết bị (devices)
CREATE TABLE IF NOT EXISTS devices (
  id SERIAL PRIMARY KEY,
  device_name VARCHAR(100) NOT NULL,
  topic VARCHAR(200) NOT NULL UNIQUE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- 2. Bảng lưu trạng thái thiết bị (device_states)
CREATE TABLE IF NOT EXISTS device_states (
  id SERIAL PRIMARY KEY,
  device_id INTEGER REFERENCES devices(id) ON DELETE CASCADE,
  light VARCHAR(10) DEFAULT 'off',
  fan VARCHAR(10) DEFAULT 'off',
  firmware VARCHAR(50),
  rssi INTEGER,
  online BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 3. Bảng lưu dữ liệu cảm biến (sensor_data)
CREATE TABLE IF NOT EXISTS sensor_data (
  id SERIAL PRIMARY KEY,
  device_id VARCHAR(100) DEFAULT 'unknown_device',
  temp_c DECIMAL(5,2),
  hum_pct DECIMAL(5,2),
  rssi INTEGER,
  topic VARCHAR(200),
  ts TIMESTAMP DEFAULT NOW()
);

-- 4. Bảng lưu lịch sử lệnh điều khiển (device_logs)
CREATE TABLE IF NOT EXISTS device_logs (
  id SERIAL PRIMARY KEY,
  device_name VARCHAR(100),
  action VARCHAR(50),
  topic VARCHAR(200),
  timestamp TIMESTAMP DEFAULT NOW()
);

-- 5. Tạo index để tăng tốc truy vấn
CREATE INDEX IF NOT EXISTS idx_sensor_data_device_id ON sensor_data(device_id);
CREATE INDEX IF NOT EXISTS idx_sensor_data_ts ON sensor_data(ts DESC);
CREATE INDEX IF NOT EXISTS idx_device_logs_device_name ON device_logs(device_name);
CREATE INDEX IF NOT EXISTS idx_device_logs_timestamp ON device_logs(timestamp DESC);

-- 6. Tạo function tự động cập nhật updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7. Tạo trigger cho bảng devices
DROP TRIGGER IF EXISTS update_devices_updated_at ON devices;
CREATE TRIGGER update_devices_updated_at
  BEFORE UPDATE ON devices
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- 8. Insert dữ liệu mẫu (optional)
INSERT INTO devices (device_name, topic) 
VALUES ('Living Room', 'demo/room1')
ON CONFLICT (topic) DO NOTHING;

-- Xem kết quả
SELECT 'Tables created successfully!' as status;
