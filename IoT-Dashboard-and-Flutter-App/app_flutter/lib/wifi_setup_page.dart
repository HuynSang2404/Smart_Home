import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // AppColors

class WifiSetupPage extends StatefulWidget {
  final bool isDark;
  final Function(String topic, String payload)? onMqttPublish;
  final bool mqttConnected;
  final int? currentRSSI;
  final String? currentSSID;

  // These are unused now but kept for compatibility
  final Stream<Map<String, dynamic>>? wifiStatusStream;

  const WifiSetupPage({
    super.key,
    required this.isDark,
    this.onMqttPublish,
    this.mqttConnected = false,
    this.currentRSSI,
    this.currentSSID,
    this.wifiStatusStream,
  });

  @override
  State<WifiSetupPage> createState() => _WifiSetupPageState();
}

class _WifiSetupPageState extends State<WifiSetupPage> {
  final TextEditingController _ssidCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _sending = false;
  bool _sent = false;
  List<Map<String, String>> _savedNetworks = [];

  @override
  void initState() {
    super.initState();
    _loadSavedNetworks();
  }

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // Load saved WiFi history from SharedPreferences
  Future<void> _loadSavedNetworks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('wifi_history') ?? [];
    setState(() {
      _savedNetworks = raw.map((s) {
        final parts = s.split('||');
        return {
          'ssid': parts[0],
          'time': parts.length > 1 ? parts[1] : '',
        };
      }).toList();
    });
  }

  // Save a new WiFi entry to history
  Future<void> _saveToHistory(String ssid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('wifi_history') ?? [];

    // Remove duplicate if exists
    raw.removeWhere((s) => s.startsWith('$ssid||'));

    // Add to front
    final now = DateTime.now();
    final timeStr =
        '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    raw.insert(0, '$ssid||$timeStr');

    // Keep max 10
    if (raw.length > 10) raw.removeLast();

    await prefs.setStringList('wifi_history', raw);
    _loadSavedNetworks();
  }

  // Remove a saved WiFi entry
  Future<void> _removeFromHistory(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('wifi_history') ?? [];
    if (index < raw.length) {
      raw.removeAt(index);
      await prefs.setStringList('wifi_history', raw);
      _loadSavedNetworks();
    }
  }

  // Send WiFi credentials to ESP32 via MQTT
  void _sendWifiToDevice() {
    final ssid = _ssidCtrl.text.trim();
    final pass = _passCtrl.text;

    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng nhập tên WiFi')));
      return;
    }

    if (!widget.mqttConnected || widget.onMqttPublish == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('MQTT chưa kết nối. Không thể gửi lệnh.')));
      return;
    }

    setState(() {
      _sending = true;
      _sent = false;
    });

    final cmd = jsonEncode({
      'wifi_set': {
        'ssid': ssid,
        'password': pass,
      }
    });
    widget.onMqttPublish!('device/cmd', cmd);

    // Save to history
    _saveToHistory(ssid);

    // Show success after a short delay (ESP32 will restart)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _sending = false;
          _sent = true;
        });
      }
    });
  }

  // Use a saved network (fill in SSID)
  void _useSavedNetwork(String ssid) {
    _ssidCtrl.text = ssid;
    _passCtrl.clear();
    // Scroll to top
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã chọn "$ssid". Nhập mật khẩu rồi nhấn Kết nối.'),
            duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text('Cài đặt WiFi',
            style: GoogleFonts.inter(
                color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: _sent
          ? _buildSuccessView(isDark, textColor, subColor)
          : _buildMainView(isDark, textColor, subColor),
    );
  }

  // ============ SUCCESS ============
  Widget _buildSuccessView(bool isDark, Color textColor, Color subColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.emerald.withOpacity(0.15),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.emerald, size: 64),
            ),
            const SizedBox(height: 24),
            Text('Đã gửi lệnh!',
                style: GoogleFonts.inter(
                    fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 8),
            Text(
                'ESP32 sẽ khởi động lại và kết nối WiFi "${_ssidCtrl.text}".\nVui lòng chờ vài giây...',
                textAlign: TextAlign.center,
                style: TextStyle(color: subColor, fontSize: 14, height: 1.5)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Quay lại Dashboard'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _sent = false),
              child: Text('Kết nối WiFi khác',
                  style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      ),
    );
  }

  // ============ MAIN ============
  Widget _buildMainView(bool isDark, Color textColor, Color subColor) {
    final cardColor = isDark ? AppColors.darkCard.withOpacity(0.8) : Colors.white;
    final borderColor =
        isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder;
    final inputFill =
        isDark ? AppColors.darkSurface.withOpacity(0.5) : Colors.grey.shade100;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -- MQTT status --
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: widget.mqttConnected
                  ? AppColors.emerald.withOpacity(0.1)
                  : AppColors.rose.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.mqttConnected
                    ? AppColors.emerald.withOpacity(0.4)
                    : AppColors.rose.withOpacity(0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.mqttConnected
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  color: widget.mqttConnected ? AppColors.emerald : AppColors.rose,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.mqttConnected
                        ? 'MQTT đã kết nối — Sẵn sàng gửi lệnh'
                        : 'MQTT chưa kết nối — Không thể gửi lệnh',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.mqttConnected
                          ? AppColors.emerald
                          : AppColors.rose,
                    ),
                  ),
                ),
                if (widget.currentRSSI != null)
                  Text('${widget.currentRSSI} dBm',
                      style: TextStyle(fontSize: 12, color: subColor)),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // -- INPUT FORM --
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black26 : Colors.black.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.wifi_rounded,
                          color: AppColors.accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text('Kết nối WiFi mới',
                        style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: textColor)),
                  ],
                ),
                const SizedBox(height: 20),

                // SSID
                TextField(
                  controller: _ssidCtrl,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'Tên WiFi (SSID)',
                    labelStyle: TextStyle(color: subColor),
                    prefixIcon: const Icon(Icons.wifi_rounded,
                        color: AppColors.accent, size: 20),
                    filled: true,
                    fillColor: inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.accent, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Password
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
                    labelStyle: TextStyle(color: subColor),
                    prefixIcon: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.accent, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePass
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: subColor,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                    filled: true,
                    fillColor: inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.accent, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Connect button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        (_sending || !widget.mqttConnected) ? null : _sendWifiToDevice,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
                    label: Text(_sending ? 'Đang gửi...' : 'Kết nối'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade300,
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: GoogleFonts.inter(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // -- SAVED NETWORKS --
          if (_savedNetworks.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.history_rounded, size: 20, color: AppColors.cyan),
                const SizedBox(width: 8),
                Text('WiFi đã kết nối',
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: textColor)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${_savedNetworks.length}',
                      style: const TextStyle(
                          color: AppColors.cyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_savedNetworks.length, (i) {
              final net = _savedNetworks[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.wifi_rounded,
                        color: AppColors.cyan, size: 20),
                  ),
                  title: Text(net['ssid'] ?? '',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: textColor)),
                  subtitle: Text(net['time'] ?? '',
                      style: TextStyle(fontSize: 12, color: subColor)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Use this network
                      IconButton(
                        icon: const Icon(Icons.login_rounded,
                            color: AppColors.accent, size: 20),
                        tooltip: 'Sử dụng',
                        onPressed: () => _useSavedNetwork(net['ssid'] ?? ''),
                      ),
                      // Delete
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: subColor, size: 18),
                        tooltip: 'Xóa',
                        onPressed: () => _removeFromHistory(i),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
