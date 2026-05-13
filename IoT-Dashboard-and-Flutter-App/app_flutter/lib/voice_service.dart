// ============================================================
// Voice Recognition Service — Web Speech API (Chrome)
// Approach: Inject JS via eval(), poll results from Dart
// ============================================================

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Callback khi nhận diện được văn bản giọng nói
typedef VoiceResultCallback = void Function(String text, bool isFinal);

/// Callback khi trạng thái thay đổi
typedef VoiceStatusCallback = void Function(bool isListening);

/// JS helper: evaluate a JS expression and return result
@JS('eval')
external JSAny? _jsEval(JSString code);

/// Service điều khiển giọng nói qua Web Speech API
class VoiceService {
  bool _isListening = false;
  bool _shouldListen = false;
  bool _initialized = false;
  VoiceResultCallback? onResult;
  VoiceStatusCallback? onStatusChanged;

  bool get isListening => _isListening;

  /// Kiểm tra trình duyệt có hỗ trợ Speech API không
  bool get isSupported {
    try {
      final result = _jsEval(
          "'webkitSpeechRecognition' in window || 'SpeechRecognition' in window"
              .toJS);
      return result != null && (result as JSBoolean).toDart;
    } catch (_) {
      return false;
    }
  }

  /// Khởi tạo recognition instance trong JS global scope
  void _initRecognition() {
    if (_initialized) return;

    try {
      _jsEval(r"""
(function() {
  var SR = window.webkitSpeechRecognition || window.SpeechRecognition;
  if (!SR) return;
  window._flutterSR = new SR();
  window._flutterSR.continuous = true;
  window._flutterSR.interimResults = true;
  window._flutterSR.lang = 'vi-VN';
  window._flutterSR.maxAlternatives = 1;

  // Chỉ lưu 1 kết quả final gần nhất — Dart sẽ poll và reset
  window._flutterSR_finalText = '';
  window._flutterSR_hasFinal = false;
  window._flutterSR_interimText = '';
  window._flutterSR_isListening = false;
  window._flutterSR_shouldListen = false;
  // Dedup: track kết quả final cuối cùng để tránh gửi trùng
  window._flutterSR_lastFinalText = '';
  window._flutterSR_lastFinalTime = 0;

  window._flutterSR.onresult = function(e) {
    var latestFinal = '';
    var latestInterim = '';
    for (var i = e.resultIndex; i < e.results.length; i++) {
      var result = e.results[i];
      var text = result[0].transcript;
      if (result.isFinal) {
        latestFinal = text;
      } else {
        latestInterim = text;
      }
    }
    window._flutterSR_interimText = latestInterim;
    if (latestFinal) {
      var now = Date.now();
      // Dedup: bỏ qua nếu cùng text trong vòng 2 giây
      if (latestFinal === window._flutterSR_lastFinalText &&
          (now - window._flutterSR_lastFinalTime) < 2000) {
        return;
      }
      window._flutterSR_finalText = latestFinal;
      window._flutterSR_hasFinal = true;
      window._flutterSR_interimText = '';
      window._flutterSR_lastFinalText = latestFinal;
      window._flutterSR_lastFinalTime = now;
    }
  };

  window._flutterSR.onstart = function() {
    window._flutterSR_isListening = true;
  };

  window._flutterSR.onend = function() {
    window._flutterSR_isListening = false;
    if (window._flutterSR_shouldListen) {
      setTimeout(function() {
        if (window._flutterSR_shouldListen) {
          try { window._flutterSR.start(); } catch(e) {}
        }
      }, 100);
    }
  };

  window._flutterSR.onerror = function(e) {
    // no-speech / aborted are normal
  };
})()
"""
          .toJS);

      _initialized = true;
    } catch (e) {
      // Could not initialize
    }
  }

  /// Bắt đầu lắng nghe
  void start() {
    _shouldListen = true;
    _initRecognition();
    if (!_initialized) return;

    try {
      _jsEval(r"""
(function() {
  window._flutterSR_shouldListen = true;
  window._flutterSR_hasFinal = false;
  window._flutterSR_finalText = '';
  window._flutterSR_interimText = '';
  window._flutterSR_lastFinalText = '';
  window._flutterSR_lastFinalTime = 0;
  try { window._flutterSR.start(); } catch(e) {}
})()
"""
          .toJS);
    } catch (_) {}

    _isListening = true;
    onStatusChanged?.call(true);
    _startPolling();
  }

  Timer? _pollTimer;

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _pollResults();
    });
  }

  void _pollResults() {
    if (!_shouldListen) {
      _pollTimer?.cancel();
      return;
    }

    try {
      // Check listening status
      final isListeningJS =
          _jsEval('window._flutterSR_isListening === true'.toJS);
      final nowListening =
          isListeningJS != null && (isListeningJS as JSBoolean).toDart;

      if (nowListening != _isListening) {
        _isListening = nowListening;
        onStatusChanged?.call(_isListening);
      }

      // Lấy interim text để hiển thị live
      final interimJS = _jsEval('window._flutterSR_interimText || ""'.toJS);
      final interim = interimJS != null ? (interimJS as JSString).toDart : '';
      if (interim.isNotEmpty) {
        onResult?.call(interim, false);
      }

      // XỬ LÝ SỚM: Nếu interim chứa lệnh rõ ràng, xử lý ngay
      // không cần chờ isFinal (tiết kiệm 1-2 giây)
      // Caller sẽ gọi restartSession() → abort session → final không bao giờ đến
      if (interim.length >= 4) {
        final normalized = _removeDiacriticsQuick(interim.toLowerCase());
        if (_isStrongCommand(normalized)) {
          // Reset interim JS để không bị poll lại
          _jsEval('window._flutterSR_interimText = ""'.toJS);
          onResult?.call(interim.trim(), true);
          return; // Không cần check final nữa
        }
      }

      // Kiểm tra có kết quả final mới không (cho các câu không match interim)
      final hasFinalJS =
          _jsEval('window._flutterSR_hasFinal === true'.toJS);
      final hasFinal =
          hasFinalJS != null && (hasFinalJS as JSBoolean).toDart;

      if (hasFinal) {
        final textJS = _jsEval('window._flutterSR_finalText'.toJS);
        final text = textJS != null ? (textJS as JSString).toDart : '';

        // Reset JS flags ngay lập tức — chỉ gửi 1 lần duy nhất
        _jsEval(
            'window._flutterSR_hasFinal = false; window._flutterSR_finalText = ""; window._flutterSR_interimText = ""'
                .toJS);

        if (text.trim().isNotEmpty) {
          onResult?.call(text.trim(), true);
        }
      }
    } catch (_) {}
  }

  /// Kiểm tra nhanh xem interim text có phải lệnh rõ ràng không
  bool _isStrongCommand(String text) {
    // Đèn ngoài sân: cần action + den + san/he
    final hasAction = RegExp(r'(bat|mo|tat|dong)').hasMatch(text);
    final hasDen = RegExp(r'(den|dien)').hasMatch(text);
    final hasSanHe = RegExp(r'(san|he)\b').hasMatch(text);
    if (hasAction && hasDen && hasSanHe) return true;

    // Đèn phòng khách: cần action + den + khach/phong
    final hasKhach = RegExp(r'(khach|phong)').hasMatch(text);
    if (hasAction && hasDen && hasKhach) return true;

    // Quạt / Còi: chỉ cần action + thiết bị
    return RegExp(r'(bat|mo|tat|dong).{0,10}(quat)').hasMatch(text) ||
           RegExp(r'(bat|mo|tat|dong).{0,10}(coi|buzzer)').hasMatch(text) ||
           RegExp(r'^(tien|lui|dung|ngung|stop)$').hasMatch(text.trim());
  }

  String _removeDiacriticsQuick(String str) {
    const diacritics = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const replacements = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final buffer = StringBuffer();
    for (final char in str.split('')) {
      final idx = diacritics.indexOf(char);
      buffer.write(idx >= 0 ? replacements[idx] : char);
    }
    return buffer.toString();
  }

  /// Dừng lắng nghe
  void stop() {
    _shouldListen = false;
    _pollTimer?.cancel();

    try {
      _jsEval(r"""
(function() {
  window._flutterSR_shouldListen = false;
  try { window._flutterSR.stop(); } catch(e) {}
})()
"""
          .toJS);
    } catch (_) {}

    _isListening = false;
    onStatusChanged?.call(false);
  }

  /// Restart session ngay lập tức để xóa sạch buffer text cũ
  /// Gọi sau khi xử lý xong 1 lệnh để lệnh tiếp theo không bị nối đuôi
  void restartSession() {
    if (!_initialized || !_shouldListen) return;
    try {
      _jsEval(r"""
(function() {
  try { window._flutterSR.abort(); } catch(e) {}
  window._flutterSR_hasFinal = false;
  window._flutterSR_finalText = '';
  window._flutterSR_interimText = '';
  window._flutterSR_lastFinalText = '';
  window._flutterSR_lastFinalTime = 0;
  setTimeout(function() {
    if (window._flutterSR_shouldListen) {
      try { window._flutterSR.start(); } catch(e) {}
    }
  }, 50);
})()
"""
          .toJS);
    } catch (_) {}
  }

  /// Toggle mic
  void toggle() {
    if (_shouldListen) {
      stop();
    } else {
      start();
    }
  }

  /// Giải phóng tài nguyên
  void dispose() {
    stop();
    _pollTimer?.cancel();
  }
}
