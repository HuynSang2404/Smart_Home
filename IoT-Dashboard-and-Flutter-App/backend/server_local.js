// ======= server_local.js =======
// IoT Backend using LOCAL PostgreSQL (no Supabase dependency)
// =============================================

import express from "express";
import mqtt from "mqtt";
import pg from "pg";
import dotenv from "dotenv";
import cors from "cors";
import https from "https";

dotenv.config();

const app = express();
app.use(express.json());
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true
}));

// ======= Configuration =======
const config = {
    db: {
        host: process.env.DB_HOST || 'localhost',
        port: Number(process.env.DB_PORT || 5432),
        user: process.env.DB_USER || 'postgres',
        password: process.env.DB_PASS || '1',
        database: process.env.DB_NAME || 'iot_dashboard',
    },
    mqtt: {
        host: process.env.MQTT_HOST || "broker.emqx.io",
        port: Number(process.env.MQTT_PORT || 1883)
    },
    telegram: {
        botToken: process.env.TELEGRAM_BOT_TOKEN || "",
        chatId: process.env.TELEGRAM_CHAT_ID || ""
    },
    alerts: {
        gasThreshold: Number(process.env.GAS_ALERT_THRESHOLD || 1500),
        tempThreshold: Number(process.env.TEMP_ALERT_THRESHOLD || 45.0)
    },
    autoLight: {
        enabled: process.env.AUTO_LIGHT_ENABLED !== 'false',
        duration: Number(process.env.LIGHT_DURATION_MS || 5000)
    },
    port: Number(process.env.PORT || 8080)
};

// ======= PostgreSQL Pool =======
const pool = new pg.Pool(config.db);
console.log(`🔗 Connecting to PostgreSQL: ${config.db.host}:${config.db.port}/${config.db.database}`);

// Helper: query wrapper
async function query(sql, params) {
    const result = await pool.query(sql, params);
    return result;
}

// ======= MQTT Client =======
const mqttClient = mqtt.connect(`mqtt://${config.mqtt.host}:${config.mqtt.port}`);
const dynamicTopics = new Set();

// Alert state tracking
const alertStates = new Map();

// ======= Telegram Helper =======
function sendTelegram(message) {
    if (!config.telegram.botToken || !config.telegram.chatId) return;

    const url = `https://api.telegram.org/bot${config.telegram.botToken}/sendMessage`;
    const data = JSON.stringify({
        chat_id: config.telegram.chatId,
        text: message,
        parse_mode: 'HTML'
    });

    const options = {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': data.length }
    };

    const req = https.request(url, options, (res) => {
        if (res.statusCode === 200) console.log("📨 Telegram sent:", message.substring(0, 50));
        else console.error("❌ Telegram error:", res.statusCode);
    });
    req.on('error', (e) => console.error("❌ Telegram request error:", e.message));
    req.write(data);
    req.end();
}

// ======= Alert Management =======
async function checkAndCreateAlert(deviceId, alertType, value, threshold) {
    try {
        const deviceState = alertStates.get(deviceId) || {};
        const alertKey = alertType.toLowerCase();
        const isActive = value >= threshold;
        const wasActive = deviceState[alertKey] || false;

        if (isActive !== wasActive) {
            deviceState[alertKey] = isActive;
            alertStates.set(deviceId, deviceState);

            if (isActive) {
                const devRes = await query('SELECT device_name FROM devices WHERE id = $1', [deviceId]);
                const deviceName = devRes.rows[0]?.device_name || `Device ${deviceId}`;
                const message = `${alertType} alert: ${value.toFixed(2)} >= ${threshold}`;

                await query(
                    'INSERT INTO alerts (device_id, alert_type, alert_level, message, value, threshold) VALUES ($1,$2,$3,$4,$5,$6)',
                    [deviceId, alertType, 'WARNING', message, value, threshold]
                );

                sendTelegram(`🚨 <b>${alertType} Alert</b>\n📍 ${deviceName}\n📊 Value: ${value.toFixed(2)}\n⚠️ Threshold: ${threshold}`);
                console.log(`🚨 Alert created: ${alertType} for device ${deviceId}`);

                // KHÔNG tự bật buzzer từ backend - ESP32 tự xử lý locally
                // if (alertType === 'GAS_HIGH') await publishMQTT(deviceId, 'buzzer', 'ON');
            } else {
                await query(
                    'UPDATE alerts SET resolved = true, resolved_at = NOW() WHERE device_id = $1 AND alert_type = $2 AND resolved = false',
                    [deviceId, alertType]
                );
                sendTelegram(`✅ <b>${alertType} Resolved</b>\n📍 Device ${deviceId}\n📊 Value: ${value.toFixed(2)}`);
                // KHÔNG tự tắt buzzer từ backend - ESP32 tự xử lý locally
                // if (alertType === 'GAS_HIGH') await publishMQTT(deviceId, 'buzzer', 'OFF');
            }
        }
    } catch (error) {
        console.error("❌ Alert check error:", error.message);
    }
}

// ======= MQTT Publish Helper =======
async function publishMQTT(deviceId, device, action) {
    try {
        const res = await query('SELECT topic FROM devices WHERE id = $1', [deviceId]);
        if (!res.rows[0]) { console.error("❌ Device not found:", deviceId); return; }

        const topic = `${res.rows[0].topic}/device/cmd`;
        const payload = JSON.stringify({ [device]: action.toLowerCase() });

        mqttClient.publish(topic, payload, { qos: 1 }, (err) => {
            if (err) console.error("❌ MQTT publish error:", err);
            else console.log(`📤 Published to ${topic}: ${payload}`);
        });
    } catch (error) {
        console.error("❌ Publish MQTT error:", error.message);
    }
}

// ======= MQTT Message Handler =======
mqttClient.on("message", async (topic, message) => {
    try {
        const raw = message.toString().trim();

        // Parse message: support both JSON objects and raw values (numbers/strings)
        let data;
        try {
            data = JSON.parse(raw);
        } catch {
            // Raw value (e.g. gas topic sends plain "1385")
            const num = parseFloat(raw);
            data = isNaN(num) ? raw : num;
        }
        console.log(`📩 [${topic}]:`, typeof data === 'object' ? JSON.stringify(data) : data);

        // Find device by matching topic prefix (e.g. demo/room1)
        const parts = topic.split('/');
        const baseTopic = parts.slice(0, 2).join('/');
        const devRes = await query(
            'SELECT * FROM devices WHERE topic = $1 OR topic = $2 LIMIT 1',
            [topic, baseTopic]
        );

        if (devRes.rows.length === 0) {
            // Ignore topics from unknown devices (public broker spam)
            return;
        }

        const device = devRes.rows[0];
        const deviceId = device.id;

        // 1. Sensor data
        if (topic.endsWith('/sensor/state') || data.temp_c !== undefined) {
            const updates = [];
            const values = [];
            let idx = 1;

            const addUpdate = (col, val) => {
                if (val !== undefined) { updates.push(`${col} = $${idx}`); values.push(val); idx++; }
            };

            addUpdate('last_sensor_update', new Date().toISOString());
            addUpdate('temperature', data.temp_c);
            addUpdate('humidity', data.hum_pct);
            if (data.gas !== undefined || data.gas_level !== undefined) addUpdate('gas_level', data.gas || data.gas_level);
            if (data.gas_ppm !== undefined) addUpdate('gas_level', data.gas_ppm);
            if (data.motion !== undefined) { addUpdate('motion_detected', data.motion); addUpdate('last_motion_update', new Date().toISOString()); }
            if (data.lux !== undefined || data.light_level !== undefined) addUpdate('light_level', data.lux || data.light_level);
            addUpdate('rssi', data.rssi);
            if (data.motion_present !== undefined) addUpdate('motion_sensor_connected', data.motion_present);
            if (data.gas_present !== undefined) addUpdate('gas_sensor_connected', data.gas_present);

            if (updates.length > 0) {
                values.push(deviceId);
                await query(`UPDATE devices SET ${updates.join(', ')} WHERE id = $${idx}`, values);
            }

            // Insert sensor history
            await query(
                'INSERT INTO sensor_data (device_id, temp_c, hum_pct, gas_level, motion_detected, light_level, rssi, topic) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)',
                [deviceId, data.temp_c, data.hum_pct, data.gas || data.gas_level || data.gas_ppm, data.motion, data.lux || data.light_level, data.rssi, topic]
            );

            // Check alerts
            const gasVal = data.gas || data.gas_level || data.gas_ppm;
            if (gasVal !== undefined) await checkAndCreateAlert(deviceId, 'GAS_HIGH', gasVal, config.alerts.gasThreshold);
            if (data.temp_c !== undefined) await checkAndCreateAlert(deviceId, 'TEMP_HIGH', data.temp_c, config.alerts.tempThreshold);
        }

        // 2. Motion
        else if (topic.endsWith('/motion')) {
            const motionDetected = data === 1 || data === '1' || data === true || data?.motion === true;
            await query(
                'UPDATE devices SET motion_detected = $1, motion_sensor_connected = true, last_motion_update = NOW() WHERE id = $2',
                [motionDetected, deviceId]
            );
            if (config.autoLight.enabled && motionDetected && device.control_mode === 'AUTO') {
                await publishMQTT(deviceId, 'light', 'ON');
                console.log(`💡 Auto-light triggered for device ${deviceId}`);
            }
        }

        // 3. Gas (separate topic)
        else if (topic.endsWith('/gas')) {
            const gasLevel = parseFloat(data);
            await query(
                'UPDATE devices SET gas_level = $1, gas_sensor_connected = true, last_gas_update = NOW() WHERE id = $2',
                [gasLevel, deviceId]
            );
            await checkAndCreateAlert(deviceId, 'GAS_HIGH', gasLevel, config.alerts.gasThreshold);
        }

        // 4. Device state
        else if (topic.endsWith('/device/state')) {
            const updates = [];
            const values = [];
            let idx = 1;

            if (data.light !== undefined || data.led !== undefined) {
                const state = (data.light || data.led) === 'on';
                updates.push(`led_state = $${idx}`); values.push(state); idx++;
            }
            if (data.fan !== undefined || data.motor !== undefined) {
                const fan = data.fan || data.motor;
                const motorVal = fan === 'on' ? 1 : (fan === 'off' ? 0 : (typeof fan === 'number' ? fan : 0));
                updates.push(`motor_state = $${idx}`); values.push(motorVal); idx++;
            }
            if (data.buzzer !== undefined) {
                updates.push(`buzzer_state = $${idx}`); values.push(data.buzzer === 'on'); idx++;
            }
            if (data.mode !== undefined) {
                updates.push(`control_mode = $${idx}`); values.push(data.mode); idx++;
            }
            if (data.fw !== undefined) {
                updates.push(`firmware = $${idx}`); values.push(data.fw); idx++;
            }
            if (data.rssi !== undefined) {
                updates.push(`rssi = $${idx}`); values.push(data.rssi); idx++;
            }

            if (updates.length > 0) {
                values.push(deviceId);
                await query(`UPDATE devices SET ${updates.join(', ')} WHERE id = $${idx}`, values);
            }
        }

        // 5. Online status
        else if (topic.endsWith('/sys/online') || topic.endsWith('/status')) {
            const online = data.online === true || data === 'ONLINE';
            await query('UPDATE devices SET online = $1 WHERE id = $2', [online, deviceId]);
            if (online) sendTelegram(`✅ Device <b>${device.device_name}</b> is now ONLINE`);
        }

        // 6. Device command (log to both legacy and new tables)
        else if (topic.endsWith('/device/cmd')) {
            const [deviceType, rawAction] = Object.entries(data)[0] || ['unknown', 'unknown'];
            const actionStr = String(rawAction).toUpperCase();

            // Log to legacy table
            await query(
                'INSERT INTO device_logs (device_name, action, topic) VALUES ($1,$2,$3)',
                [device.device_name, `${deviceType}_${actionStr}`, topic]
            );

            // Map to proper action name for device_actions table
            let actionName = `${deviceType.toUpperCase()}_${actionStr}`;
            if (deviceType === 'light' || deviceType === 'led') {
                actionName = actionStr === 'ON' ? 'LED_ON' : 'LED_OFF';
            } else if (deviceType === 'motor') {
                actionName = actionStr === '1' ? 'MOTOR_FORWARD' : actionStr === '-1' ? 'MOTOR_REVERSE' : 'MOTOR_STOP';
            } else if (deviceType === 'buzzer') {
                actionName = actionStr === 'ON' ? 'BUZZER_ON' : 'BUZZER_OFF';
            } else if (deviceType === 'fan') {
                actionName = actionStr === 'ON' ? 'MOTOR_FORWARD' : 'MOTOR_STOP';
            } else if (deviceType === 'mode') {
                // Mode changes are not device actions, skip
                actionName = null;
            }

            if (actionName) {
                await query(
                    'INSERT INTO device_actions (device_id, action, triggered_by) VALUES ($1,$2,$3)',
                    [deviceId, actionName, 'USER']
                );
                console.log(`📝 Logged action: ${actionName} for device ${deviceId}`);
            }
        }

    } catch (error) {
        console.error(`❌ MQTT message error on topic [${topic}]:`, error.message);
    }
});

// ======= Application Startup =======
async function startApplication() {
    try {
        // Test DB connection
        const ver = await query('SELECT version()');
        console.log("✅ Connected to PostgreSQL:", ver.rows[0].version.split(',')[0]);

        // Load dynamic topics
        const res = await query('SELECT topic FROM devices');
        res.rows.forEach(row => {
            dynamicTopics.add(`${row.topic}/sensor/state`);
            dynamicTopics.add(`${row.topic}/device/state`);
            dynamicTopics.add(`${row.topic}/device/cmd`);
            dynamicTopics.add(`${row.topic}/sys/online`);
            dynamicTopics.add(`${row.topic}/motion`);
            dynamicTopics.add(`${row.topic}/gas`);
        });
        console.log(`🔄 Loaded ${res.rows.length} devices with ${dynamicTopics.size} topics`);

        // Connect MQTT
        mqttClient.on("connect", () => {
            console.log(`✅ Connected MQTT ${config.mqtt.host}:${config.mqtt.port}`);
            if (dynamicTopics.size > 0) {
                mqttClient.subscribe(Array.from(dynamicTopics), { qos: 1 }, (err) => {
                    if (!err) console.log(`📡 Subscribed to ${dynamicTopics.size} topics`);
                });
            }
            // Removed wildcard 'demo/+/#' - only subscribe to known device topics to avoid public broker spam
        });

        mqttClient.on("error", (err) => console.error("❌ MQTT error:", err.message));

        // Start HTTP server
        app.listen(config.port, "0.0.0.0", () => {
            console.log(`🚀 Server running on http://0.0.0.0:${config.port}`);
            console.log(`📊 Auto-light: ${config.autoLight.enabled ? 'ENABLED' : 'DISABLED'}`);
            console.log(`📨 Telegram: ${config.telegram.botToken ? 'CONFIGURED' : 'NOT CONFIGURED'}`);
        });

    } catch (error) {
        console.error("❌ Failed to start application:", error);
        process.exit(1);
    }
}

// ======= REST API ENDPOINTS =======

// Health check
app.get("/health", async (_req, res) => {
    res.json({
        status: "ok",
        mqtt: mqttClient.connected ? "connected" : "disconnected",
        database: "local PostgreSQL",
        autoLight: config.autoLight.enabled,
        telegram: !!config.telegram.botToken
    });
});

// Get all devices
app.get("/api/devices", async (_req, res) => {
    try {
        const r = await query('SELECT * FROM v_device_summary ORDER BY id ASC');
        res.json(r.rows);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Get single device
app.get("/api/devices/:id", async (req, res) => {
    try {
        const r = await query('SELECT * FROM v_device_summary WHERE id = $1', [req.params.id]);
        if (r.rows.length === 0) return res.status(404).json({ error: "Device not found" });
        res.json(r.rows[0]);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Create device
app.post("/api/devices", async (req, res) => {
    try {
        const { device_name, topic } = req.body;
        console.log('📥 POST /api/devices:', { device_name, topic });

        if (!device_name || !topic) {
            return res.status(400).json({ error: "Missing device_name or topic" });
        }

        const r = await query(
            'INSERT INTO devices (device_name, topic) VALUES ($1, $2) ON CONFLICT (topic) DO UPDATE SET device_name = $1 RETURNING *',
            [device_name, topic]
        );

        // Subscribe to new topics
        const newTopics = [
            `${topic}/sensor/state`, `${topic}/device/state`, `${topic}/device/cmd`,
            `${topic}/sys/online`, `${topic}/motion`, `${topic}/gas`
        ];

        mqttClient.subscribe(newTopics, { qos: 1 }, (err) => {
            if (!err) {
                newTopics.forEach(t => dynamicTopics.add(t));
                console.log(`✅ Subscribed to new device topics: ${topic}`);
            }
        });

        res.json({ message: "Device created", device: r.rows[0] });
    } catch (e) {
        console.error('❌ POST /api/devices error:', e);
        res.status(500).json({ error: e.message });
    }
});

// Update device
app.put("/api/devices/:id", async (req, res) => {
    try {
        const fields = req.body;
        const keys = Object.keys(fields);
        const sets = keys.map((k, i) => `${k} = $${i + 1}`).join(', ');
        const vals = [...Object.values(fields), req.params.id];

        const r = await query(`UPDATE devices SET ${sets} WHERE id = $${keys.length + 1} RETURNING *`, vals);
        res.json(r.rows[0]);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Delete device
app.delete("/api/devices/:id", async (req, res) => {
    try {
        await query('DELETE FROM devices WHERE id = $1', [req.params.id]);
        res.json({ message: "Device deleted" });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Control LED
app.post("/api/devices/:id/led", async (req, res) => {
    try {
        const { on } = req.body;
        const deviceId = parseInt(req.params.id);
        await query('UPDATE devices SET led_state = $1 WHERE id = $2', [on, deviceId]);
        await publishMQTT(deviceId, 'light', on ? 'ON' : 'OFF');
        await query('INSERT INTO device_actions (device_id, action, triggered_by) VALUES ($1,$2,$3)', [deviceId, on ? 'LED_ON' : 'LED_OFF', 'USER']);
        res.json({ message: `LED ${on ? 'ON' : 'OFF'}` });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Control Motor
app.post("/api/devices/:id/motor", async (req, res) => {
    try {
        const { state } = req.body;
        const deviceId = parseInt(req.params.id);
        await query('UPDATE devices SET motor_state = $1 WHERE id = $2', [state, deviceId]);
        await publishMQTT(deviceId, 'motor', state.toString());
        const actionName = state === 1 ? 'MOTOR_FORWARD' : state === -1 ? 'MOTOR_REVERSE' : 'MOTOR_STOP';
        await query('INSERT INTO device_actions (device_id, action, triggered_by) VALUES ($1,$2,$3)', [deviceId, actionName, 'USER']);
        res.json({ message: `Motor state: ${state}` });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Control Buzzer
app.post("/api/devices/:id/buzzer", async (req, res) => {
    try {
        const { on } = req.body;
        const deviceId = parseInt(req.params.id);
        await query('UPDATE devices SET buzzer_state = $1 WHERE id = $2', [on, deviceId]);
        await publishMQTT(deviceId, 'buzzer', on ? 'ON' : 'OFF');
        await query('INSERT INTO device_actions (device_id, action, triggered_by) VALUES ($1,$2,$3)', [deviceId, on ? 'BUZZER_ON' : 'BUZZER_OFF', 'USER']);
        res.json({ message: `Buzzer ${on ? 'ON' : 'OFF'}` });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Set control mode
app.post("/api/devices/:id/mode", async (req, res) => {
    try {
        const { mode } = req.body;
        const deviceId = parseInt(req.params.id);
        if (!['AUTO', 'MANUAL'].includes(mode)) return res.status(400).json({ error: "Mode must be AUTO or MANUAL" });
        await query('UPDATE devices SET control_mode = $1 WHERE id = $2', [mode, deviceId]);
        await publishMQTT(deviceId, 'mode', mode);
        res.json({ message: `Control mode set to ${mode}` });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Get sensor history
app.get("/api/devices/:id/sensor-history", async (req, res) => {
    try {
        const limit = parseInt(req.query.limit) || 100;
        const r = await query('SELECT * FROM sensor_data WHERE device_id = $1 ORDER BY timestamp DESC LIMIT $2', [req.params.id, limit]);
        res.json(r.rows);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Get device actions
app.get("/api/devices/:id/actions", async (req, res) => {
    try {
        const limit = parseInt(req.query.limit) || 50;
        const r = await query('SELECT * FROM device_actions WHERE device_id = $1 ORDER BY timestamp DESC LIMIT $2', [req.params.id, limit]);
        res.json(r.rows);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Get device alerts
app.get("/api/devices/:id/alerts", async (req, res) => {
    try {
        const limit = parseInt(req.query.limit) || 50;
        const r = await query('SELECT * FROM alerts WHERE device_id = $1 ORDER BY created_at DESC LIMIT $2', [req.params.id, limit]);
        res.json(r.rows);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Get active alerts
app.get("/api/alerts", async (_req, res) => {
    try {
        const r = await query('SELECT * FROM v_active_alerts');
        res.json(r.rows);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Resolve alert
app.post("/api/alerts/:id/resolve", async (req, res) => {
    try {
        await query('UPDATE alerts SET resolved = true, resolved_at = NOW() WHERE id = $1', [req.params.id]);
        res.json({ message: "Alert resolved" });
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// Voice command logging (Flutter app already executes via MQTT, this just logs)
app.post("/api/voice/command", async (req, res) => {
    try {
        const { text, device_id } = req.body;
        if (!text) return res.status(400).json({ error: "Missing text" });

        const deviceIdToUse = device_id || 1;

        // Parse command for logging purposes (optional - won't block on failure)
        const normalized = text.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
        let actionName = 'VOICE_CMD';

        if (/bat.*(den|dien).*(san|he)|bat.*(san|he).*(den|dien)|(san|he).*bat.*(den|dien)|mo.*(den|dien).*(san|he)|mo.*(san|he).*(den|dien)/.test(normalized)) actionName = 'LED_ON';
        else if (/tat.*(den|dien).*(san|he)|tat.*(san|he).*(den|dien)|(san|he).*tat.*(den|dien)|dong.*(den|dien).*(san|he)/.test(normalized)) actionName = 'LED_OFF';
        else if (/bat.*quat|mo.*quat/.test(normalized)) actionName = 'MOTOR_FORWARD';
        else if (/tat.*quat|dong.*quat/.test(normalized)) actionName = 'MOTOR_STOP';
        else if (/bat.*coi|bat.*buzzer/.test(normalized)) actionName = 'BUZZER_ON';
        else if (/tat.*coi|tat.*buzzer/.test(normalized)) actionName = 'BUZZER_OFF';
        else if (/tien/.test(normalized)) actionName = 'MOTOR_FORWARD';
        else if (/lui/.test(normalized)) actionName = 'MOTOR_REVERSE';
        else if (/dung|ngung|stop/.test(normalized)) actionName = 'MOTOR_STOP';

        // Always log, even if command is not recognized (for voice history)
        await query(
            'INSERT INTO device_actions (device_id, action, triggered_by) VALUES ($1,$2,$3)',
            [deviceIdToUse, actionName, 'VOICE']
        );

        console.log(`🎙️ Voice logged: "${text}" -> ${actionName} (device ${deviceIdToUse})`);
        res.json({ success: true, action: actionName });
    } catch (e) {
        console.error("❌ Voice log error:", e.message);
        res.status(500).json({ error: e.message });
    }
});

// Legacy endpoints
app.get("/api/sensor/latest", async (_req, res) => {
    try {
        const r = await query('SELECT * FROM sensor_data ORDER BY timestamp DESC LIMIT 1');
        res.json(r.rows[0] || {});
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

app.get("/api/logs/latest", async (_req, res) => {
    try {
        const r = await query('SELECT * FROM device_logs ORDER BY timestamp DESC LIMIT 10');
        res.json(r.rows);
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
});

// ======= Start Application =======
startApplication();

// ======= Graceful Shutdown =======
process.on('SIGINT', () => {
    console.log('\n🛑 Shutting down gracefully...');
    mqttClient.end();
    pool.end();
    process.exit(0);
});
