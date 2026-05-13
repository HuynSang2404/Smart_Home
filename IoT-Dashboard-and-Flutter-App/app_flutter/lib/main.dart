// ============================================================
// IoT Smart Home Controller — Cross-Platform (Web + Android)
// Modern UI with Dark/Light mode
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'history_page.dart';
import 'wifi_setup_page.dart';
import 'voice_service.dart';

// Conditional import for web MQTT
import 'package:mqtt_client/mqtt_browser_client.dart';

// =================== CONFIG ===================
class AppConfig {
  // IP máy tính chạy backend (thay đổi khi test trên thiết bị thật)
  // - Web: dùng localhost
  // - Android emulator: dùng 10.0.2.2
  // - Thiết bị thật (Android/iOS): dùng IP LAN máy tính (vd: 192.168.1.x)
  static const String lanIP = '10.17.236.242';

  static String get apiBase =>
      kIsWeb ? 'http://localhost:8080' : 'http://$lanIP:8080';
  static String get mlApiBase =>
      kIsWeb ? 'http://localhost:5000' : 'http://$lanIP:5000';
}

void main() => runApp(const IoTApp());

// =================== THEME ===================
class AppColors {
  // Dark theme
  static const darkBg = Color(0xFF0D1117);
  static const darkCard = Color(0xFF161B22);
  static const darkCardBorder = Color(0xFF30363D);
  static const darkSurface = Color(0xFF21262D);

  // Light theme
  static const lightBg = Color(0xFFF6F8FA);
  static const lightCard = Colors.white;
  static const lightCardBorder = Color(0xFFD0D7DE);

  // Accent
  static const accent = Color(0xFF7C3AED);
  static const accentLight = Color(0xFFA78BFA);
  static const cyan = Color(0xFF06B6D4);
  static const emerald = Color(0xFF10B981);
  static const rose = Color(0xFFF43F5E);
  static const amber = Color(0xFFF59E0B);
  static const blue = Color(0xFF3B82F6);
}

// =================== APP ROOT ===================
class IoTApp extends StatefulWidget {
  const IoTApp({super.key});
  @override
  State<IoTApp> createState() => _IoTAppState();
}

class _IoTAppState extends State<IoTApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
    SharedPreferences.getInstance().then((p) {
      p.setBool('darkMode', _themeMode == ThemeMode.dark);
    });
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final isDark = p.getBool('darkMode') ?? true;
      setState(() => _themeMode = isDark ? ThemeMode.dark : ThemeMode.light);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nhà Thông Minh IoT',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: AppColors.accent,
        scaffoldBackgroundColor: AppColors.lightBg,
        textTheme: GoogleFonts.interTextTheme(),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: AppColors.accent,
        scaffoldBackgroundColor: AppColors.darkBg,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: DashboardPage(
        topic: 'demo/room1',
        name: 'Phòng khách',
        onToggleTheme: _toggleTheme,
        isDark: _themeMode == ThemeMode.dark,
      ),
    );
  }
}

// =================== BOOTSTRAP ===================
class _BootstrapPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;
  const _BootstrapPage({required this.onToggleTheme, required this.isDark});
  @override
  State<_BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<_BootstrapPage> {
  bool _loading = true;
  String? _savedTopic;
  String? _savedName;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    _savedTopic = prefs.getString('topic');
    _savedName = prefs.getString('device_name');
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_savedTopic != null && _savedTopic!.isNotEmpty) {
      return DashboardPage(
        topic: _savedTopic!,
        name: _savedName ?? 'Thiết bị',
        onToggleTheme: widget.onToggleTheme,
        isDark: widget.isDark,
      );
    }
    return RegisterPage(
      onToggleTheme: widget.onToggleTheme,
      isDark: widget.isDark,
    );
  }
}

// =================== REGISTER PAGE ===================
class RegisterPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;
  const RegisterPage(
      {super.key, required this.onToggleTheme, required this.isDark});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with SingleTickerProviderStateMixin {
  final _nameCtrl = TextEditingController();
  final _topicCtrl = TextEditingController();
  bool _loading = false;
  late AnimationController _fadeCtrl;

  String get _apiBase => AppConfig.apiBase;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _nameCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _nameCtrl.text.trim();
    final rawTopic = _topicCtrl.text.trim();
    if (name.isEmpty || rawTopic.isEmpty) {
      _showSnack('⚠️ Vui lòng nhập thông tin thiết bị');
      return;
    }
    final topic = rawTopic.startsWith('demo/') ? rawTopic : 'demo/$rawTopic';
    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/api/devices'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_name': name, 'topic': topic}),
      );
      if (res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('topic', topic);
        await prefs.setString('device_name', name);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DashboardPage(
                topic: topic,
                name: name,
                onToggleTheme: widget.onToggleTheme,
                isDark: widget.isDark),
          ),
        );
      } else {
        _showSnack('❌ Lỗi server: ${res.statusCode}');
      }
    } catch (e) {
      _showSnack('❌ Không thể kết nối server');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeCtrl,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF0F0C29),
                      const Color(0xFF302B63),
                      const Color(0xFF24243E)
                    ]
                  : [
                      const Color(0xFFE8EAF6),
                      const Color(0xFFC5CAE9),
                      const Color(0xFF9FA8DA)
                    ],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _GlassCard(
                isDark: isDark,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // Theme toggle
                    Align(
                      alignment: Alignment.topRight,
                      child: _ThemeToggle(
                        isDark: widget.isDark,
                        onToggle: widget.onToggleTheme,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Icon
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppColors.accent, AppColors.cyan],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withAlpha(102),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.home_rounded,
                          size: 48, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    Text('Nhà Thông Minh IoT',
                        style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.accent)),
                    const SizedBox(height: 8),
                    Text('Đăng ký & kết nối thiết bị',
                        style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54)),
                    const SizedBox(height: 32),
                    _ModernTextField(
                      controller: _nameCtrl,
                      label: 'Tên thiết bị',
                      icon: Icons.devices_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),
                    _ModernTextField(
                      controller: _topicCtrl,
                      label: 'Mã thiết bị (vd: room1)',
                      icon: Icons.qr_code_rounded,
                      isDark: isDark,
                      suffixIcon: PopupMenuButton<String>(
                        icon: const Icon(Icons.arrow_drop_down_rounded,
                            color: AppColors.accent),
                        onSelected: (val) => _topicCtrl.text = val,
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'room1',
                              child: Text('Phòng khách (room1)')),
                          PopupMenuItem(
                              value: 'room2', child: Text('Nhà bếp (room2)')),
                          PopupMenuItem(
                              value: 'room3', child: Text('Sân vườn (room3)')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: _GradientButton(
                        onPressed: _loading ? null : _register,
                        label: _loading
                            ? 'Đang kết nối...'
                            : 'Kết nối & Mở Bảng điều khiển',
                        icon: _loading ? null : Icons.rocket_launch_rounded,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =================== DASHBOARD PAGE ===================
class DashboardPage extends StatefulWidget {
  final String topic;
  final String name;
  final VoidCallback onToggleTheme;
  final bool isDark;
  const DashboardPage({
    super.key,
    required this.topic,
    required this.name,
    required this.onToggleTheme,
    required this.isDark,
  });
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  // MQTT
  MqttClient? _mqttClient;
  bool _mqttConnected = false;
  bool _deviceOnline = false;

  // Device states
  String _light = 'off';
  String _light2 = 'off';  // Đèn phòng khách
  int _motor = 0;
  String _buzzer = 'off';
  String _controlMode = 'AUTO';
  DateTime? _voiceCmdGraceUntil; // Bỏ qua MQTT state update trong grace period

  // Sensor data
  double? _temp, _hum, _gas, _lux;
  double? _gasLPG, _gasCO, _gasSmoke;
  bool _motion = false;
  int? _rssi;
  String _fw = '--';

  // Fire prediction
  String _fireRisk = 'Chưa rõ';
  String _fireReason = '';
  bool _firePredicting = false;
  DateTime? _lastPrediction;

  int? _deviceId;

  // Alerts
  final List<Map<String, dynamic>> _alerts = [];

  // WiFi status stream for WiFi setup page
  final StreamController<Map<String, dynamic>> _wifiStatusCtrl =
      StreamController<Map<String, dynamic>>.broadcast();

  // Animation
  late AnimationController _pulseCtrl;

  // Voice Control
  final VoiceService _voiceService = VoiceService();
  bool _isListening = false;
  String _lastVoiceText = '';
  final List<String> _voiceLog = [];

  String get _apiBase => AppConfig.apiBase;
  String get _mlApiBase => AppConfig.mlApiBase;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _fetchDeviceId();
    _connectMQTT();
    _initVoice();
  }

  // --------- VOICE INIT ---------
  void _initVoice() {
    if (!kIsWeb) return; // Chỉ hỗ trợ Web
    _voiceService.onResult = (text, isFinal) {
      if (!mounted) return;
      setState(() => _lastVoiceText = text);
      if (isFinal) {
        _handleVoiceCommand(text);
      }
    };
    _voiceService.onStatusChanged = (listening) {
      if (!mounted) return;
      setState(() => _isListening = listening);
    };
    // Mặc định bật mic khi mở app
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _voiceService.start();
    });
  }

  Future<void> _fetchDeviceId() async {
    try {
      final url = '$_apiBase/api/devices';
      debugPrint('🔍 Fetching devices from: $url');
      debugPrint('🔍 Looking for topic: "${widget.topic}"');
      final res = await http.get(Uri.parse(url));
      debugPrint('🔍 Response status: ${res.statusCode}');
      if (res.statusCode == 200) {
        final List devices = jsonDecode(res.body);
        debugPrint('🔍 Found ${devices.length} devices:');
        for (final dev in devices) {
          debugPrint(
              '   - id=${dev['id']}, topic="${dev['topic']}", name="${dev['device_name']}"');
        }
        final d = devices.firstWhere((x) => x['topic'] == widget.topic,
            orElse: () => null);
        if (d != null && mounted) {
          debugPrint('✅ Matched device ID: ${d['id']}');
          setState(() => _deviceId = d['id']);
        } else {
          debugPrint('❌ No device found with topic "${widget.topic}"');
        }
      } else {
        debugPrint('❌ API error: ${res.statusCode} - ${res.body}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching device ID: $e');
    }
  }

  @override
  void dispose() {
    _voiceService.dispose();
    _pulseCtrl.dispose();
    _wifiStatusCtrl.close();
    try {
      _mqttClient?.disconnect();
    } catch (_) {}
    super.dispose();
  }

  // --------- MQTT ---------
  Future<void> _connectMQTT() async {
    final clientId = 'flutter_iot_${DateTime.now().millisecondsSinceEpoch}';

    if (kIsWeb) {
      _mqttClient = MqttBrowserClient('wss://broker.emqx.io/mqtt', clientId)
        ..port = 8084
        ..keepAlivePeriod = 30
        ..autoReconnect = true
        ..logging(on: false);
    } else {
      _mqttClient = MqttServerClient('broker.emqx.io', clientId)
        ..port = 1883
        ..keepAlivePeriod = 30
        ..autoReconnect = true
        ..logging(on: false);
    }

    _mqttClient!.onConnected = () {
      setState(() => _mqttConnected = true);
      _subscribeTopics();
    };
    _mqttClient!.onDisconnected = () {
      setState(() => _mqttConnected = false);
    };

    try {
      await _mqttClient!.connect();
    } catch (e) {
      debugPrint('MQTT connect error: $e');
      setState(() => _mqttConnected = false);
    }
  }

  void _subscribeTopics() {
    final ns = widget.topic;
    final topics = [
      '$ns/sensor/state',
      '$ns/device/state',
      '$ns/sys/online',
      '$ns/motion',
      '$ns/gas',
      '$ns/wifi/status',
    ];
    for (final t in topics) {
      _mqttClient!.subscribe(t, MqttQos.atLeastOnce);
    }
    _mqttClient!.updates?.listen((msgs) {
      for (final m in msgs) {
        final payload = MqttPublishPayload.bytesToStringAsString(
            (m.payload as MqttPublishMessage).payload.message);
        _handleMessage(m.topic, payload);
      }
    });
  }

  void _handleMessage(String topic, String payload) {
    try {
      if (topic.endsWith('/sensor/state')) {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        setState(() {
          _temp = _toDouble(data['temp_c']);
          _hum = _toDouble(data['hum_pct']);
          _gas = _toDouble(data['gas_ppm'] ?? data['gas_lpg'] ?? data['gas']);
          _gasLPG = _toDouble(data['gas_lpg']);
          _gasCO = _toDouble(data['gas_co']);
          _gasSmoke = _toDouble(data['gas_smoke']);
          _lux = _toDouble(data['lux'] ?? data['light_level']);
          if (data['motion'] != null) {
            _motion = data['motion'] == true || data['motion'] == 1;
          }
          _rssi = data['rssi'] as int?;
        });
        _checkGasAlert();
        _predictFireRisk();
      } else if (topic.endsWith('/device/state')) {
        // Nếu đang trong grace period sau voice command → bỏ qua device state
        if (_voiceCmdGraceUntil != null &&
            DateTime.now().isBefore(_voiceCmdGraceUntil!)) {
          // Chỉ cập nhật fw, rssi, mode — KHÔNG ghi đè light/motor/buzzer
          final data = jsonDecode(payload) as Map<String, dynamic>;
          setState(() {
            _fw = data['fw']?.toString() ?? _fw;
            _rssi = data['rssi'] as int? ?? _rssi;
            _controlMode = data['mode']?.toString() ?? _controlMode;
          });
        } else {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          setState(() {
            _light = data['light']?.toString() ?? _light;
            _light2 = data['light2']?.toString() ?? _light2;
            if (data['motor'] != null) {
              _motor = int.tryParse(data['motor'].toString()) ?? _motor;
            }
            _buzzer = data['buzzer']?.toString() ?? _buzzer;
            _fw = data['fw']?.toString() ?? _fw;
            _rssi = data['rssi'] as int? ?? _rssi;
            _controlMode = data['mode']?.toString() ?? _controlMode;
          });
        }
      } else if (topic.endsWith('/sys/online')) {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        setState(() => _deviceOnline = data['online'] == true);
      } else if (topic.endsWith('/motion')) {
        setState(() => _motion = payload == '1' || payload == 'true');
      } else if (topic.endsWith('/gas')) {
        setState(() => _gas = double.tryParse(payload));
        _checkGasAlert();
      } else if (topic.endsWith('/wifi/status')) {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        _wifiStatusCtrl.add(data);
      }
    } catch (_) {}
  }

  double? _toDouble(dynamic v) =>
      v == null ? null : double.tryParse(v.toString());

  // --------- SEND COMMAND ---------
  void _sendCmd(String device, String action) {
    if (!_mqttConnected || _mqttClient == null) {
      _showSnack('⚠️ MQTT chưa kết nối');
      return;
    }
    final topic = '${widget.topic}/device/cmd';
    final payload = jsonEncode({device: action});
    final builder = MqttClientPayloadBuilder()..addString(payload);
    _mqttClient!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    _showSnack('📤 $device → $action');
  }

  void _controlLED(bool on) => _sendCmd('light', on ? 'ON' : 'OFF');
  void _controlLED2(bool on) => _sendCmd('light2', on ? 'ON' : 'OFF');
  void _controlMotor(int s) => _sendCmd('motor', s.toString());
  void _controlBuzzer(bool on) => _sendCmd('buzzer', on ? 'ON' : 'OFF');
  void _setMode(String m) {
    setState(() => _controlMode = m);
    _sendCmd('mode', m);
  }

  // --------- ALERTS ---------
  void _checkGasAlert() {
    final g = _gas ?? 0;
    if (g >= 1500) {
      // Đồng bộ với backend threshold
      _addAlert('GAS_HIGH', 'Gas cao: ${g.toInt()} ppm');
    } else {
      _removeAlert('GAS_HIGH');
    }
  }

  void _addAlert(String type, String msg) {
    if (!_alerts.any((a) => a['type'] == type)) {
      setState(() =>
          _alerts.add({'type': type, 'message': msg, 'time': DateTime.now()}));
    }
  }

  void _removeAlert(String type) {
    setState(() => _alerts.removeWhere((a) => a['type'] == type));
  }

  // --------- ML PREDICTION ---------
  Future<void> _predictFireRisk({bool manual = false}) async {
    if (_firePredicting) return;
    final now = DateTime.now();
    if (!manual &&
        _lastPrediction != null &&
        now.difference(_lastPrediction!) < const Duration(seconds: 15)) return;

    setState(() => _firePredicting = true);
    _lastPrediction = now;

    try {
      final body = jsonEncode({
        'sensor1': _gas ?? 0,
        'sensor2': _gasLPG ?? _gas ?? 0,
        'sensor3': _gasCO ?? 0,
        'sensor4': _gasSmoke ?? 0,
        'sensor5': _temp ?? 25,
        'sensor6': _hum ?? 50,
        'sensor7': _lux ?? 0,
        'sensor8': (_gas ?? 0) * 0.8,
        'temperature': _temp ?? 25,
        'humidity': _hum ?? 50,
      });
      debugPrint('Sending ML prediction request to: $_mlApiBase/predict');
      final res = await http.post(
        Uri.parse('$_mlApiBase/predict'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      debugPrint('ML response: ${res.statusCode} - ${res.body}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final prediction = data['prediction']?.toString() ?? '';
        final isRisk = prediction.contains('Fire Risk');
        String reason = '';
        if (isRisk) {
          final t = _temp ?? 0;
          final g = _gas ?? 0;
          if (t >= 35 && g >= 1000) {
            reason = 'Nhiệt độ ($t°C) & Khí gas ($g ppm) quá cao';
          } else if (t >= 35) {
            reason = 'Nhiệt độ môi trường tăng cao bất thường ($t°C)';
          } else if (g >= 1000) {
            reason = 'Nồng độ khí gas ở mức cực kỳ nguy hiểm ($g ppm)';
          } else {
            reason = 'Phát hiện tín hiệu bất thường từ cảm biến';
          }
        } else {
          reason = 'Các chỉ số môi trường ở mức an toàn';
        }

        setState(() {
          _fireRisk = isRisk ? 'NGUY CƠ CHÁY' : 'An toàn';
          _fireReason = reason;
        });

        if (isRisk) {
          _addAlert('FIRE_ML', '🔥 AI: Nguy cơ cháy ($reason)');
          // Chỉ cảnh báo UI, KHÔNG tự bật buzzer - ESP32 xử lý locally
        } else {
          _removeAlert('FIRE_ML');
        }
      }
    } catch (e) {
      debugPrint('ML API Error: $e');
    } finally {
      setState(() => _firePredicting = false);
    }
  }

  // --------- LOGOUT ---------
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('topic');
    await prefs.remove('device_name');
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => _BootstrapPage(
          onToggleTheme: widget.onToggleTheme,
          isDark: widget.isDark,
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }

  // --------- VOICE COMMAND HANDLER ---------
  String _lastExecutedCmd = '';
  DateTime? _lastCmdTime;

  Future<void> _handleVoiceCommand(String text) async {
    final normalized = text.toLowerCase().trim();
    final noDiacritics = _removeDiacritics(normalized);
    final words = noDiacritics.split(RegExp(r'\s+'));

    // *** Bỏ qua câu dài (hội thoại, không phải lệnh) ***
    if (words.length > 8) return;

    debugPrint('🎙️ Voice cmd: "$text" -> $words');

    String? device;
    String? action;
    String? displayMsg;

    // --- Proximity matching: hành động + thiết bị phải GẦN nhau (≤ 3 từ) ---
    const actOn = ['bat', 'bac', 'bap', 'mo', 'moi'];
    const actOff = ['tat', 'tac', 'dong'];
    const devLight = ['san', 'he'];  // Đèn ngoài sân - phải có từ 'sân' hoặc 'hè'
    const devLight2 = ['khach', 'phong'];  // Đèn phòng khách
    const devFan = ['quat'];
    const devBuzzer = ['coi', 'buzzer'];

    // Tìm cặp (hành động + 'đèn') gần nhau, rồi kiểm tra có 'sân/hè' không
    final hasLightWord = words.any((w) => ['den', 'dien'].contains(w));
    final hasSanHe = words.any((w) => devLight.contains(w));
    final matchLightOn = hasLightWord && hasSanHe && _findNearbyPair(words, actOn, ['den', 'dien'], 5);
    final matchLightOff = hasLightWord && hasSanHe && _findNearbyPair(words, actOff, ['den', 'dien'], 5);
    // Đèn phòng khách
    final hasKhach = words.any((w) => devLight2.contains(w));
    final matchLight2On = hasLightWord && hasKhach && _findNearbyPair(words, actOn, ['den', 'dien'], 5);
    final matchLight2Off = hasLightWord && hasKhach && _findNearbyPair(words, actOff, ['den', 'dien'], 5);
    final matchFanOn = _findNearbyPair(words, actOn, devFan, 3);
    final matchFanOff = _findNearbyPair(words, actOff, devFan, 3);
    final matchBuzOn = _findNearbyPair(words, actOn, devBuzzer, 3);
    final matchBuzOff = _findNearbyPair(words, actOff, devBuzzer, 3);

    final textNoAccent = words.join(' ');
    final matchAllOn = textNoAccent.contains('bat tat ca') || textNoAccent.contains('mo tat ca') || textNoAccent.contains('bat het') || textNoAccent.contains('mo het');
    final matchAllOff = textNoAccent.contains('tat tat ca') || textNoAccent.contains('dong tat ca') || textNoAccent.contains('tat het') || textNoAccent.contains('dong het');

    // Tất cả thiết bị (đèn 1, đèn 2, quạt)
    if (matchAllOff) {
      device = 'all';
      action = 'OFF';
      displayMsg = '🏠 Tắt tất cả thiết bị';
    } else if (matchAllOn) {
      device = 'all';
      action = 'ON';
      displayMsg = '🏠 Bật tất cả thiết bị';
    }
    // Đèn phòng khách (check trước đèn ngoài sân vì cả hai có từ 'đèn')
    else if (matchLight2Off) {
      device = 'light2';
      action = 'OFF';
      displayMsg = '💡 Tắt đèn phòng khách';
    } else if (matchLight2On) {
      device = 'light2';
      action = 'ON';
      displayMsg = '💡 Bật đèn phòng khách';
    }
    // Đèn ngoài sân
    else if (matchLightOff) {
      device = 'light';
      action = 'OFF';
      displayMsg = '💡 Tắt đèn ngoài sân';
    } else if (matchLightOn) {
      device = 'light';
      action = 'ON';
      displayMsg = '💡 Bật đèn ngoài sân';
    }
    // Quạt
    else if (matchFanOff) {
      device = 'fan';
      action = 'OFF';
      displayMsg = '🌀 Tắt quạt';
    } else if (matchFanOn) {
      device = 'fan';
      action = 'ON';
      displayMsg = '🌀 Bật quạt';
    }
    // Còi
    else if (matchBuzOff) {
      device = 'buzzer';
      action = 'OFF';
      displayMsg = '🔔 Tắt còi';
    } else if (matchBuzOn) {
      device = 'buzzer';
      action = 'ON';
      displayMsg = '🔔 Bật còi';
    }
    // Motor: từ đơn
    else if (_anyWord(words, ['tien'])) {
      device = 'motor';
      action = '1';
      displayMsg = '⚙️ Tiến';
    } else if (_anyWord(words, ['lui'])) {
      device = 'motor';
      action = '-1';
      displayMsg = '⚙️ Lùi';
    } else if (_anyWord(words, ['dung', 'ngung', 'stop'])) {
      device = 'motor';
      action = '0';
      displayMsg = '⚙️ Dừng';
    }

    if (device == null || action == null) return;

    // Debounce: bỏ qua lệnh trùng trong 1.5 giây
    final cmdKey = '$device:$action';
    final now = DateTime.now();
    if (_lastExecutedCmd == cmdKey &&
        _lastCmdTime != null &&
        now.difference(_lastCmdTime!) < const Duration(milliseconds: 1500)) {
      return;
    }
    _lastExecutedCmd = cmdKey;
    _lastCmdTime = now;

    // Gửi MQTT
    if (device == 'all') {
      // Gửi 1 gói JSON gộp để tránh ESP32 debounce bỏ qua lệnh
      final topic = '${widget.topic}/device/cmd';
      final payload = jsonEncode({
        'light': action,
        'light2': action,
        'fan': action,
      });
      final builder = MqttClientPayloadBuilder()..addString(payload);
      _mqttClient!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      _showSnack('📤 Tất cả → $action');
    } else {
      _sendCmd(device, action);
    }

    // Restart recognition ngay để xóa buffer, lệnh tiếp theo bắt đầu sạch
    _voiceService.restartSession();

    // Cập nhật UI state để toggle đồng bộ
    // Grace period: bỏ qua MQTT state update trong 3 giây
    _voiceCmdGraceUntil = DateTime.now().add(const Duration(seconds: 3));

    setState(() {
      if (device == 'all') {
        _light = action == 'ON' ? 'on' : 'off';
        _light2 = action == 'ON' ? 'on' : 'off';
        _motor = action == 'ON' ? 1 : 0;
      } else {
        if (device == 'light') _light = action == 'ON' ? 'on' : 'off';
        if (device == 'light2') _light2 = action == 'ON' ? 'on' : 'off';
        if (device == 'buzzer') _buzzer = action == 'ON' ? 'on' : 'off';
        if (device == 'motor') _motor = int.tryParse(action!) ?? 0;
        if (device == 'fan') _motor = action == 'ON' ? 1 : 0;
      }
      _voiceLog.insert(0, '$displayMsg');
      if (_voiceLog.length > 3) _voiceLog.removeLast();
    });

    // Log lên backend (fire-and-forget, không block)
    http.post(
      Uri.parse('$_apiBase/api/voice/command'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'device_id': _deviceId ?? 1}),
    ).catchError((_) => http.Response('', 200));
  }

  /// Kiểm tra 2 nhóm từ khóa có xuất hiện GẦN nhau (≤ maxDist từ) không
  bool _findNearbyPair(List<String> words, List<String> groupA,
      List<String> groupB, int maxDist) {
    for (int i = 0; i < words.length; i++) {
      final bool isA = groupA.any((k) => words[i] == k || words[i].contains(k));
      if (!isA) continue;
      // Tìm groupB trong phạm vi ±maxDist
      for (int j = (i - maxDist).clamp(0, words.length);
          j < (i + maxDist + 1).clamp(0, words.length);
          j++) {
        if (i == j) continue;
        if (groupB.any((k) => words[j] == k || words[j].contains(k))) {
          return true;
        }
      }
    }
    return false;
  }

  /// Kiểm tra từ khóa đơn (motor commands)
  bool _anyWord(List<String> words, List<String> keywords) {
    return words.any((w) => keywords.any((k) => w == k));
  }

  /// Kiểm tra xem bất kỳ từ nào trong words có chứa/bằng keyword không
  bool _anyContains(List<String> words, List<String> keywords) {
    for (final w in words) {
      for (final kw in keywords) {
        if (w == kw || w.contains(kw)) return true;
      }
    }
    return false;
  }

  /// Bỏ dấu tiếng Việt để so khớp lệnh
  String _removeDiacritics(String str) {
    const diacritics =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const nonDiacritics =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    var result = str;
    for (int i = 0; i < diacritics.length; i++) {
      result = result.replaceAll(diacritics[i], nonDiacritics[i]);
    }
    return result;
  }

  // =================== UI ===================
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF0F0C29), AppColors.darkBg]
                : [const Color(0xFFE8EAF6), AppColors.lightBg],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // App Bar
              SliverToBoxAdapter(child: _buildAppBar(isDark)),
              // Content
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 8),
                    _buildStatusRow(isDark),
                    const SizedBox(height: 16),
                    if (kIsWeb) _buildVoiceCard(isDark),
                    if (kIsWeb) const SizedBox(height: 16),
                    _buildSensorGrid(isDark),
                    const SizedBox(height: 16),
                    _buildControlsCard(isDark),
                    const SizedBox(height: 16),
                    _buildCombinedAlertsCard(isDark),
                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------- APP BAR ---------
  Widget _buildAppBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.cyan]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: AppColors.accent.withAlpha(77), blurRadius: 12),
              ],
            ),
            child:
                const Icon(Icons.home_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.name,
                    style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87)),
                Text(widget.topic,
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38)),
              ],
            ),
          ),
          _buildIconBtn(Icons.history_rounded, () {
            debugPrint(
                '📋 Opening History - deviceId: $_deviceId, topic: ${widget.topic}');
            if (_deviceId == null) {
              _showSnack('⚠️ Đang tải ID thiết bị... thử lại sau');
              _fetchDeviceId(); // retry fetching
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistoryPage(
                  deviceId: _deviceId,
                  topic: widget.topic,
                  name: widget.name,
                  isDark: widget.isDark,
                ),
              ),
            );
          }, widget.isDark),
          const SizedBox(width: 8),
          if (kIsWeb) _buildMicButton(isDark),
          if (kIsWeb) const SizedBox(width: 8),
          _ThemeToggle(isDark: widget.isDark, onToggle: widget.onToggleTheme),
        ],
      ),
    );
  }

  Widget _buildIconBtn(IconData icon, VoidCallback onTap, bool isDark) {
    return Material(
      color: isDark ? AppColors.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(
                color: isDark
                    ? AppColors.darkCardBorder
                    : AppColors.lightCardBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon,
              size: 20, color: isDark ? Colors.white54 : Colors.black54),
        ),
      ),
    );
  }

  // --------- STATUS ROW ---------
  Widget _buildStatusRow(bool isDark) {
    return Row(
      children: [
        Expanded(
            child: _StatusChip(
                label: 'MQTT',
                connected: _mqttConnected,
                icon: Icons.cloud_rounded,
                isDark: isDark,
                pulseCtrl: _pulseCtrl)),
        const SizedBox(width: 10),
        Expanded(
            child: _StatusChip(
                label: 'ESP32',
                connected: _deviceOnline,
                icon: Icons.memory_rounded,
                isDark: isDark,
                pulseCtrl: _pulseCtrl)),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WifiSetupPage(
                    isDark: widget.isDark,
                    mqttConnected: _mqttConnected,
                    currentSSID: null,
                    currentRSSI: _rssi,
                    onMqttPublish: _mqttConnected
                        ? (topic, payload) {
                            final fullTopic = '${widget.topic}/$topic';
                            final builder = MqttClientPayloadBuilder()
                              ..addString(payload);
                            _mqttClient?.publishMessage(
                                fullTopic, MqttQos.atLeastOnce, builder.payload!);
                          }
                        : null,
                    wifiStatusStream: _wifiStatusCtrl.stream,
                  ),
                ),
              );
            },
            child: _GlassCard(
              isDark: isDark,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Column(
                children: [
                  const Icon(Icons.wifi_rounded, size: 24, color: AppColors.cyan),
                  const SizedBox(height: 4),
                  const Text('WIFI',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.cyan)),
                  Text('Cấu hình',
                      style: TextStyle(
                          fontSize: 9,
                          color: AppColors.cyan.withOpacity(0.7))),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --------- MIC BUTTON (APP BAR) ---------
  Widget _buildMicButton(bool isDark) {
    return Material(
      color: _isListening
          ? AppColors.emerald.withOpacity(0.15)
          : (isDark ? AppColors.darkCard : Colors.white),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _voiceService.toggle(),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(
                color: _isListening
                    ? AppColors.emerald
                    : (isDark
                        ? AppColors.darkCardBorder
                        : AppColors.lightCardBorder)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              _isListening ? Icons.mic_rounded : Icons.mic_off_rounded,
              key: ValueKey(_isListening),
              size: 20,
              color: _isListening ? AppColors.emerald : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  // --------- VOICE CONTROL CARD ---------
  Widget _buildVoiceCard(bool isDark) {
    return _GlassCard(
      isDark: isDark,
      borderColor: _isListening ? AppColors.emerald.withAlpha(128) : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isListening
                          ? AppColors.emerald.withAlpha(38)
                          : Colors.grey.withAlpha(38),
                      boxShadow: _isListening
                          ? [
                              BoxShadow(
                                  color: AppColors.emerald.withAlpha(
                                      (77 * _pulseCtrl.value).toInt()),
                                  blurRadius: 20)
                            ]
                          : null,
                    ),
                    child: Icon(
                        _isListening
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded,
                        color: _isListening ? AppColors.emerald : Colors.grey,
                        size: 24),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Điều khiển giọng nói',
                          style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87)),
                      Text(
                          _isListening
                              ? '🟢 Đang nghe... Hãy nói lệnh'
                              : '🔴 Đã tắt mic — Nhấn để bật',
                          style: TextStyle(
                              fontSize: 11,
                              color: _isListening
                                  ? AppColors.emerald
                                  : (isDark
                                      ? Colors.white38
                                      : Colors.black38))),
                    ],
                  ),
                ),
                // Toggle button
                GestureDetector(
                  onTap: () => _voiceService.toggle(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isListening
                          ? AppColors.rose.withOpacity(0.15)
                          : AppColors.emerald.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _isListening
                              ? AppColors.rose.withOpacity(0.5)
                              : AppColors.emerald.withOpacity(0.5)),
                    ),
                    child: Text(_isListening ? 'Tắt mic' : 'Bật mic',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _isListening
                                ? AppColors.rose
                                : AppColors.emerald)),
                  ),
                ),
              ],
            ),

            // Live text
            if (_lastVoiceText.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _isListening
                          ? AppColors.emerald.withOpacity(0.3)
                          : (isDark
                              ? AppColors.darkCardBorder
                              : AppColors.lightCardBorder)),
                ),
                child: Row(
                  children: [
                    Text('🗣️ ', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: Text(
                        '"$_lastVoiceText"',
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Voice log
            if (_voiceLog.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...(_voiceLog.map((log) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(log,
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white38 : Colors.black38)),
                  ))),
            ],

            // Supported commands hint
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accent.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💡 Các lệnh hỗ trợ:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.accentLight
                              : AppColors.accent)),
                  const SizedBox(height: 6),
                  Text(
                    '• "Bật/Tắt đèn ngoài sân" (hoặc "đèn sân", "đèn hè")\n'
                    '• "Bật/Tắt đèn phòng khách"\n'
                    '• "Bật/Tắt quạt" hoặc "Mở/Đóng quạt"\n'
                    '• "Bật/Tắt còi"\n'
                    '• "Tiến" / "Lùi" / "Dừng" (motor)',
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: isDark ? Colors.white54 : Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------- FIRE CARD (REMOVED - MERGED WITH ALERTS) ---------
  // --------- SENSOR GRID ---------
  Widget _buildSensorGrid(bool isDark) {
    return _GlassCard(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.sensors_rounded,
                  color: AppColors.cyan, size: 22),
              const SizedBox(width: 10),
              Text('Dữ liệu cảm biến',
                  style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87)),
            ]),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SensorTile(
                      icon: Icons.thermostat_rounded,
                      label: 'Nhiệt độ',
                      value: _temp != null
                          ? '${_temp!.toStringAsFixed(1)}°C'
                          : '--',
                      color: AppColors.rose,
                      isDark: isDark),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SensorTile(
                      icon: Icons.water_drop_rounded,
                      label: 'Độ ẩm',
                      value:
                          _hum != null ? '${_hum!.toStringAsFixed(1)}%' : '--',
                      color: AppColors.blue,
                      isDark: isDark),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SensorTile(
                      icon: Icons.gas_meter_rounded,
                      label: 'Khí gas',
                      value: _gas != null ? '${_gas!.toInt()} ppm' : '--',
                      color: AppColors.amber,
                      isDark: isDark,
                      alert: (_gas ?? 0) >= 1000),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SensorTile(
                      icon: Icons.directions_run_rounded,
                      label: 'Chuyển động',
                      value: _motion ? 'PHÁT HIỆN' : 'Không',
                      color: _motion ? AppColors.rose : AppColors.emerald,
                      isDark: isDark,
                      alert: _motion),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _SensorTile(
                  icon: Icons.wifi_rounded,
                  label: 'Tín hiệu',
                  value: _rssi != null ? '$_rssi dBm' : '--',
                  color: AppColors.cyan,
                  isDark: isDark),
            ),
          ],
        ),
      ),
    );
  }

  // --------- CONTROLS CARD ---------
  Widget _buildControlsCard(bool isDark) {
    return _GlassCard(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.gamepad_rounded,
                  color: AppColors.accent, size: 22),
              const SizedBox(width: 10),
              Text('Điều khiển',
                  style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87)),
            ]),
            const SizedBox(height: 20),
            // LED - Đèn ngoài sân
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_rounded,
                          color: _light == 'on' ? AppColors.amber : Colors.grey, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Đèn ngoài sân',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : Colors.black87)),
                      ),
                      Switch.adaptive(
                        value: _light == 'on',
                        activeColor: AppColors.amber,
                        onChanged: _controlMode == 'AUTO'
                            ? null
                            : (_) => _controlLED(_light != 'on'),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Divider(height: 1, thickness: 1),
                  ),
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          color: _controlMode == 'AUTO' ? AppColors.emerald : Colors.grey,
                          size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Chế độ Tự động',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white70 : Colors.black87)),
                      ),
                      Switch.adaptive(
                        value: _controlMode == 'AUTO',
                        activeColor: AppColors.emerald,
                        onChanged: (_) =>
                            _setMode(_controlMode == 'AUTO' ? 'MANUAL' : 'AUTO'),
                      ),
                    ],
                  ),
                  if (_controlMode == 'AUTO')
                    Padding(
                      padding: const EdgeInsets.only(left: 32, bottom: 4),
                      child: Text('Sáng khi có chuyển động, tắt sau 30s',
                          style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: AppColors.emerald.withOpacity(0.8))),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Đèn phòng khách
            _ControlRow(
              label: 'Đèn phòng khách',
              icon: Icons.lightbulb_rounded,
              isOn: _light2 == 'on',
              color: AppColors.cyan,
              isDark: isDark,
              onToggle: () => _controlLED2(_light2 != 'on'),
            ),
            const SizedBox(height: 12),
            // Motor
            _buildMotorControl(isDark),
            const SizedBox(height: 12),
            // Buzzer
            _ControlRow(
              label: 'Buzzer / Còi',
              icon: Icons.notifications_active_rounded,
              isOn: _buzzer == 'on',
              color: AppColors.rose,
              isDark: isDark,
              onToggle: () => _controlBuzzer(_buzzer != 'on'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMotorControl(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color:
                isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.settings_rounded,
                  color: _motor != 0 ? AppColors.cyan : Colors.grey, size: 22),
              const SizedBox(width: 10),
              Text('Quạt / Động cơ',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _motor != 0
                      ? AppColors.cyan.withOpacity(0.15)
                      : Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                    _motor == 1
                        ? 'QUAY THUẬN'
                        : _motor == -1
                            ? 'QUAY NGƯỢC'
                            : 'DỪNG',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _motor != 0 ? AppColors.cyan : Colors.grey)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MotorBtn(
                  icon: Icons.fast_rewind_rounded,
                  label: 'Lùi',
                  active: _motor == -1,
                  onTap: () => _controlMotor(-1)),
              const SizedBox(width: 8),
              _MotorBtn(
                  icon: Icons.stop_circle_rounded,
                  label: 'Dừng',
                  active: _motor == 0,
                  color: AppColors.rose,
                  onTap: () => _controlMotor(0)),
              const SizedBox(width: 8),
              _MotorBtn(
                  icon: Icons.fast_forward_rounded,
                  label: 'Tiến',
                  active: _motor == 1,
                  onTap: () => _controlMotor(1)),
            ],
          ),
        ],
      ),
    );
  }

  // --------- COMBINED ALERTS & FIRE CARD ---------
  Widget _buildCombinedAlertsCard(bool isDark) {
    final isRisk = _fireRisk == 'NGUY CƠ CHÁY';
    final isUnknown = _fireRisk == 'Chưa rõ';
    final color = isRisk
        ? AppColors.rose
        : isUnknown
            ? (isDark ? Colors.white38 : Colors.black38)
            : AppColors.emerald;

    final alertsWithoutFireML =
        _alerts.where((a) => a['type'] != 'FIRE_ML').toList();

    return _GlassCard(
      isDark: isDark,
      borderColor: color.withAlpha(128),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- FIRE AI HEADER ---
            Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, child) => Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withAlpha(38),
                      boxShadow: isRisk
                          ? [
                              BoxShadow(
                                  color: color.withAlpha(
                                      (77 * _pulseCtrl.value).toInt()),
                                  blurRadius: 20)
                            ]
                          : null,
                    ),
                    child: Icon(
                        isRisk
                            ? Icons.local_fire_department_rounded
                            : Icons.shield_rounded,
                        color: color,
                        size: 28),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cảnh báo cháy',
                          style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87)),
                      Text('Dự đoán bằng trí tuệ nhân tạo',
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white38 : Colors.black38)),
                    ],
                  ),
                ),
                if (_firePredicting)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 16),

            // --- FIRE STATUS BOX ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withAlpha(26),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withAlpha(77)),
              ),
              child: Column(
                children: [
                  Icon(
                    isRisk
                        ? Icons.warning_amber_rounded
                        : isUnknown
                            ? Icons.help_outline_rounded
                            : Icons.check_circle_rounded,
                    size: 40,
                    color: color,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isRisk
                        ? '⚠️ NGUY CƠ CHÁY'
                        : isUnknown
                            ? 'Đang chờ dữ liệu...'
                            : 'AN TOÀN',
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                  if (_fireReason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_fireReason,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: color.withOpacity(0.8))),
                    ),
                ],
              ),
            ),

            // --- CHECK BUTTON ---
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _firePredicting
                    ? null
                    : () => _predictFireRisk(manual: true),
                icon: Icon(Icons.refresh_rounded, size: 18, color: color),
                label: Text(
                    _firePredicting ? 'Đang phân tích...' : 'Kiểm tra ngay',
                    style: TextStyle(color: color)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: color.withAlpha(128)),
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            // --- ALERTS LIST ---
            if (alertsWithoutFireML.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.rose, size: 20),
                const SizedBox(width: 10),
                Text('Sự cố khác (${alertsWithoutFireML.length})',
                    style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.rose)),
              ]),
              const SizedBox(height: 12),
              ...alertsWithoutFireML.map((a) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.rose.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: AppColors.rose.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.rose, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(a['message'],
                              style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87))),
                    ]),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// =================== REUSABLE WIDGETS ===================

// Glass Card
class _GlassCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final EdgeInsets? padding;
  final Color? borderColor;
  const _GlassCard(
      {required this.child,
      required this.isDark,
      this.padding,
      this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkCard.withOpacity(0.8)
            : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor ??
              (isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// Status Chip
class _StatusChip extends StatelessWidget {
  final String label;
  final bool connected;
  final IconData icon;
  final bool isDark;
  final AnimationController pulseCtrl;
  const _StatusChip(
      {required this.label,
      required this.connected,
      required this.icon,
      required this.isDark,
      required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppColors.emerald : AppColors.rose;
    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (_, __) => _GlassCard(
        isDark: isDark,
        borderColor: connected ? color.withOpacity(0.5) : null,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Container(
              decoration: connected
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: color.withOpacity(0.3 * pulseCtrl.value),
                            blurRadius: 12)
                      ],
                    )
                  : null,
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color)),
            Text(connected ? 'Đã kết nối' : 'Ngoại tuyến',
                style: TextStyle(fontSize: 9, color: color.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }
}

// Theme Toggle
class _ThemeToggle extends StatelessWidget {
  final bool isDark;
  final VoidCallback onToggle;
  const _ThemeToggle({required this.isDark, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(
                color: isDark
                    ? AppColors.darkCardBorder
                    : AppColors.lightCardBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              key: ValueKey(isDark),
              size: 20,
              color: isDark ? AppColors.amber : AppColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

// Modern TextField
class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isDark;
  final Widget? suffixIcon;
  const _ModernTextField(
      {required this.controller,
      required this.label,
      required this.icon,
      required this.isDark,
      this.suffixIcon});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
        prefixIcon: Icon(icon, color: AppColors.accent),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: isDark
            ? AppColors.darkSurface.withOpacity(0.5)
            : Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
      ),
    );
  }
}

// Gradient Button
class _GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  const _GradientButton({this.onPressed, required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: onPressed != null
            ? const LinearGradient(colors: [AppColors.accent, AppColors.cyan])
            : null,
        color: onPressed == null ? Colors.grey : null,
        borderRadius: BorderRadius.circular(14),
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                    color: AppColors.accent.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4))
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon, color: Colors.white, size: 20),
                if (icon != null) const SizedBox(width: 10),
                Text(label,
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Sensor Tile
class _SensorTile extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  final bool isDark;
  final bool alert;
  const _SensorTile(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color,
      required this.isDark,
      this.alert = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: alert
              ? color.withOpacity(0.6)
              : (isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.black38)),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: alert
                      ? color
                      : (isDark ? Colors.white : Colors.black87))),
        ],
      ),
    );
  }
}

// Control Row
class _ControlRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isOn;
  final Color color;
  final bool isDark;
  final VoidCallback? onToggle;
  final String? subtitle;
  const _ControlRow(
      {required this.label,
      required this.icon,
      required this.isOn,
      required this.color,
      required this.isDark,
      this.onToggle,
      this.subtitle});

  @override
  Widget build(BuildContext context) {
    final isDisabled = onToggle == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color:
                isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: isOn ? color : Colors.grey, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ),
              Switch.adaptive(
                value: isOn,
                activeColor: color,
                onChanged: isDisabled ? null : (_) => onToggle!(),
              ),
            ],
          ),
          if (subtitle != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 2, bottom: 4),
              child: Text(subtitle!,
                  style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.emerald.withOpacity(0.8))),
            ),
          ],
        ],
      ),
    );
  }
}

// Motor Button
class _MotorBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _MotorBtn(
      {required this.icon,
      required this.label,
      required this.active,
      this.color = AppColors.cyan,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: active ? color.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                  color: active ? color : Colors.grey.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Icon(icon, color: active ? color : Colors.grey, size: 20),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: active ? color : Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Mode Button
class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  const _ModeButton(
      {required this.label,
      required this.icon,
      required this.active,
      required this.color,
      required this.isDark,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? color.withOpacity(0.15)
          : (isDark ? AppColors.darkSurface : Colors.grey.shade50),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(
                color: active ? color : Colors.grey.withOpacity(0.3),
                width: active ? 2 : 1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, color: active ? color : Colors.grey, size: 28),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: active ? color : Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

// (Using Flutter's built-in AnimatedBuilder)
