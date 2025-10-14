import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/events.dart';
import '../../models/metrics_payload.dart';

class DrowsySocket {
  DrowsySocket(this.uri, {this.pingInterval = const Duration(seconds: 10)}) {
    _connect();
  }

  final Uri uri;
  final Duration pingInterval;

  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _retryAttempts = 0;
  bool _connected = false;

  final _metricsController = StreamController<MetricsPayload>.broadcast();
  final _eventsController = StreamController<DrowsyEvent>.broadcast();
  late final StreamController<bool> _connectionController = StreamController<bool>.broadcast(
    onListen: () {
      if (!_connectionController.isClosed) {
        _connectionController.add(_connected);
      }
    },
  );

  Stream<MetricsPayload> get metricsStream => _metricsController.stream;
  Stream<DrowsyEvent> get eventsStream => _eventsController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  void _emitConnection(bool value) {
    if (_disposed || _connectionController.isClosed) {
      return;
    }
    _connected = value;
    if (_connectionController.hasListener) {
      _connectionController.add(value);
    }
  }

  void _connect() {
    if (_disposed) return;

    try {
      _channel = WebSocketChannel.connect(uri);
      _retryAttempts = 0;
      _emitConnection(true);
      _listenChannel();
      _startPing();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _listenChannel() {
    final channel = _channel;
    if (channel == null) {
      _scheduleReconnect();
      return;
    }

    channel.stream.listen(
      (message) {
        if (message is String) {
          _handleMessage(message);
        }
      },
      onDone: _scheduleReconnect,
      onError: (_, __) => _scheduleReconnect(),
      cancelOnError: true,
    );
  }

  void _handleMessage(String message) {
    if (message == 'pong') {
      return;
    }

    if (message == 'ping') {
      _channel?.sink.add('pong');
      return;
    }

    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final messageType = decoded['message_type'] as String?;
      if (messageType == 'event' || decoded.containsKey('type')) {
        final event = _parseEvent(decoded);
        if (event != null && !_eventsController.isClosed) {
          _eventsController.add(event);
        }
        return;
      }

      if (!_metricsController.isClosed) {
        final payload = MetricsPayload.fromJson(decoded);
        _metricsController.add(payload);
      }
    } catch (_) {
      // ignore malformed messages
    }
  }

  DrowsyEvent? _parseEvent(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final ts = _parseTimestamp(json['ts']);
    if (type == null) return null;

    switch (type) {
      case 'eye_blink':
        return EyeBlink(ts);
      case 'micro_sleep':
        return MicroSleep(ts, (json['duration_s'] as num?)?.toDouble() ?? 0);
      case 'yawn':
        return YawnEvent(ts, (json['duration_s'] as num?)?.toDouble() ?? 0);
      case 'pitch_down':
        return PitchDown(ts, (json['duration_s'] as num?)?.toDouble() ?? 0);
      case 'eye_rub':
        return EyeRub(
          ts,
          (json['hand'] as String?) ?? 'unknown',
          (json['duration_s'] as num?)?.toDouble() ?? 0,
        );
      case 'report_window':
        return ReportWindow(
          ts,
          (json['window_s'] as num?)?.toInt() ?? 0,
          (json['counts'] as Map<String, dynamic>?) ?? const {},
          (json['durations'] as Map<String, dynamic>?) ?? const {},
        );
      default:
        return null;
    }
  }

  DateTime _parseTimestamp(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch((value * 1000).round(), isUtc: true).toLocal();
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return DateTime.fromMillisecondsSinceEpoch((parsed * 1000).round(), isUtc: true).toLocal();
      }
    }
    return DateTime.now();
  }

  void _startPing() {
    _pingTimer?.cancel();
    if (pingInterval == Duration.zero) return;

    _pingTimer = Timer.periodic(pingInterval, (_) {
      _channel?.sink.add('ping');
    });
  }

  void _scheduleReconnect() {
    if (_disposed) return;

    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _emitConnection(false);

    final delaySeconds = min(10, pow(2, _retryAttempts).toInt());
    _retryAttempts = min(_retryAttempts + 1, 4);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), _connect);
  }

  void dispose() {
    _disposed = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _metricsController.close();
    _eventsController.close();
    _connectionController.close();
  }
}
