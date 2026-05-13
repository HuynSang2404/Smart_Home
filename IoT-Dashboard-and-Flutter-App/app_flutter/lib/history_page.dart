import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'main.dart'; // import AppColors, AppConfig

class HistoryPage extends StatefulWidget {
  final int? deviceId;
  final String topic;
  final String name;
  final bool isDark;

  const HistoryPage({
    super.key,
    required this.deviceId,
    required this.topic,
    required this.name,
    required this.isDark,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = false;
  List<dynamic> _actions = [];
  List<dynamic> _sensors = [];
  List<dynamic> _alerts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (widget.deviceId == null) {
      debugPrint('❌ History: deviceId is null!');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lỗi: Không tìm thấy ID thiết bị')));
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final String baseUrl = AppConfig.apiBase;
      final id = widget.deviceId;

      debugPrint('📋 History: Loading data for device $id from $baseUrl');

      // Parallel fetch
      final responses = await Future.wait([
        http.get(Uri.parse('$baseUrl/api/devices/$id/actions?limit=50')),
        http.get(Uri.parse('$baseUrl/api/devices/$id/sensor-history?limit=50')),
        http.get(Uri.parse('$baseUrl/api/devices/$id/alerts?limit=50')),
      ]);

      debugPrint('📋 Actions response: ${responses[0].statusCode} - ${responses[0].body.length} bytes');
      debugPrint('📋 Sensors response: ${responses[1].statusCode} - ${responses[1].body.length} bytes');
      debugPrint('📋 Alerts response: ${responses[2].statusCode} - ${responses[2].body.length} bytes');

      if (mounted) {
        setState(() {
          if (responses[0].statusCode == 200) {
            _actions = jsonDecode(responses[0].body);
            debugPrint('📋 Actions loaded: ${_actions.length} items');
          } else {
            debugPrint('❌ Actions error: ${responses[0].statusCode} - ${responses[0].body}');
          }
          if (responses[1].statusCode == 200) {
            _sensors = jsonDecode(responses[1].body);
            debugPrint('📋 Sensors loaded: ${_sensors.length} items');
          } else {
            debugPrint('❌ Sensors error: ${responses[1].statusCode} - ${responses[1].body}');
          }
          if (responses[2].statusCode == 200) {
            _alerts = jsonDecode(responses[2].body);
            debugPrint('📋 Alerts loaded: ${_alerts.length} items');
          } else {
            debugPrint('❌ Alerts error: ${responses[2].statusCode} - ${responses[2].body}');
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Không thể tải lịch sử: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '--';
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      final now = DateTime.now();
      final isToday = dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day;
      
      final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (isToday) return 'Hôm nay $timeStr';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} $timeStr';
    } catch (e) {
      return timestamp.split('T').first;
    }
  }

  // --- Map Action Names ---
  Map<String, dynamic> _parseAction(String actionCode, String trigger) {
    String title = actionCode;
    IconData icon = Icons.info_outline;
    Color color = Colors.grey;

    switch (actionCode) {
      case 'LED_ON':
        title = 'Bật đèn';
        icon = Icons.lightbulb;
        color = AppColors.amber;
        break;
      case 'LED_OFF':
        title = 'Tắt đèn';
        icon = Icons.lightbulb_outline;
        color = Colors.grey;
        break;
      case 'MOTOR_FORWARD':
        title = 'Quạt quay thuận';
        icon = Icons.cyclone;
        color = AppColors.cyan;
        break;
      case 'MOTOR_REVERSE':
        title = 'Quạt quay ngược';
        icon = Icons.cyclone;
        color = AppColors.cyan;
        break;
      case 'MOTOR_STOP':
        title = 'Dừng quạt';
        icon = Icons.stop_circle_rounded;
        color = Colors.grey;
        break;
      case 'BUZZER_ON':
        title = 'Bật còi báo động';
        icon = Icons.notifications_active;
        color = AppColors.rose;
        break;
      case 'BUZZER_OFF':
        title = 'Tắt còi báo động';
        icon = Icons.notifications_off;
        color = Colors.grey;
        break;
    }

    String triggerStr = trigger == 'USER'
        ? '👤 Người dùng'
        : trigger == 'AUTO'
            ? '🤖 Tự động'
            : trigger == 'VOICE'
                ? '🎙️ Giọng nói'
                : '⚙️ Hệ thống';

    return {'title': title, 'icon': icon, 'color': color, 'trigger': triggerStr};
  }

  // --- Map Alerts ---
  Map<String, dynamic> _parseAlert(String type, String level) {
    String title = type;
    IconData icon = Icons.warning_amber_rounded;
    Color color = AppColors.amber;

    switch (type) {
      case 'GAS_HIGH':
        title = 'Khí gas vượt ngưỡng';
        icon = Icons.gas_meter_rounded;
        color = AppColors.rose;
        break;
      case 'TEMP_HIGH':
        title = 'Nhiệt độ quá cao';
        icon = Icons.thermostat_rounded;
        color = AppColors.rose;
        break;
      case 'MOTION_DETECTED':
        title = 'Phát hiện chuyển động';
        icon = Icons.directions_run_rounded;
        color = AppColors.cyan;
        break;
    }
    return {'title': title, 'icon': icon, 'color': color};
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? AppColors.darkBg : AppColors.lightBg;
    final cardColor = widget.isDark ? AppColors.darkCard : AppColors.lightCard;
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subTextColor = widget.isDark ? Colors.white54 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: widget.isDark ? AppColors.darkSurface : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text('Lịch sử - ${widget.name}',
            style: GoogleFonts.inter(
                color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.accent,
          unselectedLabelColor: subTextColor,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(text: 'Hành động', icon: Icon(Icons.touch_app_rounded, size: 20)),
            Tab(text: 'Cảm biến', icon: Icon(Icons.sensors_rounded, size: 20)),
            Tab(text: 'Cảnh báo', icon: Icon(Icons.warning_rounded, size: 20)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildActionsTab(cardColor, textColor, subTextColor),
                _buildSensorsTab(cardColor, textColor, subTextColor),
                _buildAlertsTab(cardColor, textColor, subTextColor),
              ],
            ),
    );
  }

  Widget _buildActionsTab(Color cardColor, Color textColor, Color subColor) {
    final filteredActions = _actions.where((a) => a['action'] != 'BUZZER_ON' && a['action'] != 'BUZZER_OFF').toList();
    if (filteredActions.isEmpty) return _emptyState('Không có hành động nào gần đây');
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredActions.length,
        itemBuilder: (context, i) {
          final act = filteredActions[i];
          final parsed = _parseAction(act['action'] ?? '', act['triggered_by'] ?? '');
          return Card(
            color: cardColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: widget.isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
            ),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: parsed['color'].withOpacity(0.2),
                child: Icon(parsed['icon'], color: parsed['color']),
              ),
              title: Text(parsed['title'], style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              subtitle: Text('${parsed['trigger']} • ${_formatTime(act['timestamp'])}', style: TextStyle(color: subColor, fontSize: 12)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSensorsTab(Color cardColor, Color textColor, Color subColor) {
    if (_sensors.isEmpty) return _emptyState('Không có dữ liệu cảm biến');
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _sensors.length,
        itemBuilder: (context, i) {
          final s = _sensors[i];
          final t = double.tryParse(s['temp_c']?.toString() ?? '') ?? 0;
          final h = double.tryParse(s['hum_pct']?.toString() ?? '') ?? 0;
          final g = double.tryParse(s['gas_level']?.toString() ?? '') ?? 0;
          
          return Card(
            color: cardColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: widget.isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
            ),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sensorItem('🌡️', '${t.toStringAsFixed(1)}°C', textColor),
                      _sensorItem('💧', '${h.toStringAsFixed(0)}%', textColor),
                      _sensorItem('💨', '${g.toInt()} ppm', textColor),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('🕒 ${_formatTime(s['timestamp'])}', 
                    style: TextStyle(color: subColor, fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sensorItem(String emoji, String val, Color color) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 4),
        Text(val, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildAlertsTab(Color cardColor, Color textColor, Color subColor) {
    final combinedAlerts = [
      ..._alerts.map((a) => {
            'isAction': false,
            'title': _parseAlert(a['alert_type'] ?? '', a['alert_level'] ?? '')['title'],
            'icon': _parseAlert(a['alert_type'] ?? '', a['alert_level'] ?? '')['icon'],
            'color': _parseAlert(a['alert_type'] ?? '', a['alert_level'] ?? '')['color'],
            'message': a['message'] ?? '',
            'time': a['created_at'],
            'resolved': a['resolved'] ?? false,
          }),
      ..._actions
          .where((a) => a['action'] == 'BUZZER_ON' || a['action'] == 'BUZZER_OFF')
          .map((a) => {
                'isAction': true,
                'title': _parseAction(a['action'] ?? '', a['triggered_by'] ?? '')['title'],
                'icon': _parseAction(a['action'] ?? '', a['triggered_by'] ?? '')['icon'],
                'color': _parseAction(a['action'] ?? '', a['triggered_by'] ?? '')['color'],
                'message': '${_parseAction(a['action'] ?? '', a['triggered_by'] ?? '')['trigger']}',
                'time': a['timestamp'],
                'resolved': a['action'] == 'BUZZER_OFF',
              })
    ];
    
    combinedAlerts.sort((a, b) {
      final tA = DateTime.parse(a['time'] ?? '1970-01-01');
      final tB = DateTime.parse(b['time'] ?? '1970-01-01');
      return tB.compareTo(tA);
    });

    if (combinedAlerts.isEmpty) return _emptyState('Tuyệt vời! Không có cảnh báo nào');
    
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: combinedAlerts.length,
        itemBuilder: (context, i) {
          final item = combinedAlerts[i];
          final bool isAction = item['isAction'];
          final bool resolved = item['resolved'];
          
          return Card(
            color: cardColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: widget.isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder),
            ),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Icon(item['icon'], color: item['color'], size: 32),
              title: Text(item['title'], style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(item['message'], style: TextStyle(color: subColor, fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(_formatTime(item['time']), style: TextStyle(color: subColor, fontSize: 12)),
                      const SizedBox(width: 8),
                      if (isAction)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                          child: Text(resolved ? 'Đã tắt' : 'Đang bật', style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      else if (resolved)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.emerald.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                          child: const Text('Đã giải quyết', style: TextStyle(color: AppColors.emerald, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.rose.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                          child: const Text('Đang bị lỗi', style: TextStyle(color: AppColors.rose, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                    ],
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 64, color: widget.isDark ? Colors.white24 : Colors.black26),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: widget.isDark ? Colors.white54 : Colors.black54)),
        ],
      ),
    );
  }
}
