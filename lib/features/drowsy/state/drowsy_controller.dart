import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:somnoalert/models/events.dart';

import '../../../core/ws_service.dart';
import '../model.dart';

// -------------------- URL base y WS --------------------
final backendUrlProvider = NotifierProvider<BackendUrlNotifier, String>(
  BackendUrlNotifier.new,
);

class BackendUrlNotifier extends Notifier<String> {
  @override
  String build() => "http://127.0.0.1:8000";
  void setUrl(String url) => state = url;
}

final wsUrlProvider = Provider<String>((ref) {
  String base = ref.watch(backendUrlProvider);
  base = base.replaceFirst(RegExp(r'/+$'), ''); // sin barras finales
  final uri = Uri.parse(base);
  final wsScheme = (uri.scheme == 'https') ? 'wss' : 'ws';
  final wsBase = uri.replace(scheme: wsScheme).toString();
  return '$wsBase/ws';
});

// -------------------- Estado runner --------------------
final backendRunningProvider = NotifierProvider<BackendRunningNotifier, bool>(
  BackendRunningNotifier.new,
);

class BackendRunningNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

// -------------------- Audio unlock (solo Web) --------------------
final audioUnlockedProvider = NotifierProvider<AudioUnlockedNotifier, bool>(
  AudioUnlockedNotifier.new,
);

class AudioUnlockedNotifier extends Notifier<bool> {
  @override
  bool build() => !kIsWeb; // en desktop ya está “desbloqueado”
  void set(bool v) => state = v;
}

// -------------------- Descubrimiento de rutas --------------------
({String workDir, String pythonPath, int port}) resolveBackendPaths() {
  if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
    throw UnsupportedError('resolveBackendPaths solo disponible en desktop');
  }

  final candidates = <Directory>[
    Directory.current,
    Directory('${Directory.current.path}/../'),
    Directory('${Directory.current.path}/../../'),
  ];

  String? backendDirPath;
  for (final dir in candidates) {
    final p = Directory('${dir.path}/drowsy-backend');
    final app = File('${p.path}/app.py');
    if (p.existsSync() && app.existsSync()) {
      backendDirPath = p.path;
      break;
    }
  }
  backendDirPath ??= '${Directory.current.path}/drowsy-backend';

  late final String pythonPath;
  if (Platform.isWindows) {
    final w = File('$backendDirPath/.venv/Scripts/pythonw.exe');
    final w2 = File('$backendDirPath/venv/Scripts/pythonw.exe');
    final w3 = File('$backendDirPath/.venv/Scripts/python.exe');
    pythonPath = w.existsSync()
        ? w.path
        : (w2.existsSync() ? w2.path : (w3.existsSync() ? w3.path : 'pythonw'));
  } else if (Platform.isMacOS || Platform.isLinux) {
    final u1 = File('$backendDirPath/.venv/bin/python3');
    final u2 = File('$backendDirPath/venv/bin/python3');
    final u3 = File('$backendDirPath/.venv/bin/python');
    pythonPath = u1.existsSync()
        ? u1.path
        : (u2.existsSync() ? u2.path : (u3.existsSync() ? u3.path : 'python3'));
  } else {
    throw UnsupportedError('Runner solo en Windows/macOS/Linux');
  }

  return (workDir: backendDirPath, pythonPath: pythonPath, port: 8000);
}

// -------------------- Runner Desktop --------------------
class DrowsyBackendRunner {
  Process? _proc;
  final _logCtrl = StreamController<String>.broadcast();
  Stream<String> get logs => _logCtrl.stream;
  bool get isRunning => _proc != null;

  Future<bool> start({
    required String pythonPath,
    required String workingDir,
    int port = 8000,
  }) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      throw UnsupportedError('Runner disponible solo para Windows/macOS/Linux');
    }
    if (isRunning) return true;

    String bin = pythonPath;
    if (Platform.isWindows && pythonPath.toLowerCase().endsWith('python.exe')) {
      bin = pythonPath.replaceFirst(
        RegExp(r'python\.exe$', caseSensitive: false),
        'pythonw.exe',
      );
    }

    final args = [
      '-m',
      'uvicorn',
      'app:app',
      '--host',
      '0.0.0.0',
      '--port',
      '$port',
    ];

    _logCtrl.add('> Iniciando backend en $workingDir\n');

    _proc = await Process.start(
      bin,
      args,
      workingDirectory: workingDir,
      runInShell: false,
      mode: ProcessStartMode.detachedWithStdio,
      environment: {'PYTHONUNBUFFERED': '1'},
    );

    _proc!.stdout.transform(utf8.decoder).listen((d) => _logCtrl.add(d));
    _proc!.stderr.transform(utf8.decoder).listen((d) => _logCtrl.add(d));
    _proc!.exitCode.then((code) {
      _logCtrl.add('> Backend finalizado (code: $code)\n');
      _proc = null;
    });

    return await _healthCheck(port: port);
  }

  Future<void> stop() async {
    if (_proc == null) return;
    _proc!.kill(ProcessSignal.sigint);
    await Future.delayed(const Duration(milliseconds: 350));
    _proc?.kill(ProcessSignal.sigkill);
    _proc = null;
  }

  Future<bool> _healthCheck({required int port}) async {
    for (int i = 0; i < 10; i++) {
      try {
        final response = await http
            .get(Uri.parse('http://127.0.0.1:$port/health'))
            .timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) return true;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return false;
  }

  void dispose() => _logCtrl.close();
}

// -------------------- Controller principal --------------------
final drowsyControllerProvider =
    AsyncNotifierProvider<DrowsyController, DrowsyMetrics?>(
      DrowsyController.new,
    );

class DrowsyController extends AsyncNotifier<DrowsyMetrics?> {
  WsService? _ws;
  final _player = AudioPlayer();
  DrowsyBackendRunner? _runner;
  bool _playLocalAlarm = true;
  bool _audioUnlocked = !kIsWeb; // en web arrancamos bloqueados
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  final _eventsCtrl = StreamController<DrowsyEvent>.broadcast();

  Stream<DrowsyEvent> get events => _eventsCtrl.stream;

  @override
  Future<DrowsyMetrics?> build() async {
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
      _runner = DrowsyBackendRunner();
    }

    final wsUrl = ref.watch(wsUrlProvider);
    await _connect(wsUrl);

    ref.onDispose(() async {
      _reconnectTimer?.cancel();
      _ws?.dispose();
      await _player.stop();
      await _player.dispose();
      if (_runner != null) {
        await _runner!.stop();
        _runner!.dispose();
      }
      await _eventsCtrl.close();
    });

    return null;
  }

  // Llamar esto desde un gesto del usuario (ej: botón Conectar o switch de Alarma)
  Future<void> unlockAudioForWeb() async {
    if (!kIsWeb || _audioUnlocked) return;
    try {
      await _player.setVolume(0);
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('audio/alarma.mp3'));
      await Future.delayed(const Duration(milliseconds: 120));
      await _player.stop();
      await _player.setVolume(1);
      _audioUnlocked = true;
      ref.read(audioUnlockedProvider.notifier).set(true);
    } catch (_) {
      _audioUnlocked = false;
      ref.read(audioUnlockedProvider.notifier).set(false);
    }
  }

  Future<void> _connect(String wsUrl) async {
    _reconnectTimer?.cancel();
    _ws?.dispose();
    _ws = WsService(wsUrl);

    state = const AsyncLoading();

    try {
      _ws!.connect(
        (map) async {
          final messageType = map['message_type'] as String?;
          final rawType = map['type'] as String?;

          if (messageType == 'config') {
            return;
          }

          final effectiveType = messageType ?? rawType;
          if (_isEventType(effectiveType)) {
            final event = _parseEvent(map);
            if (event != null && !_eventsCtrl.isClosed) {
              _eventsCtrl.add(event);
            }
            return;
          }

          final metrics = DrowsyMetrics.fromMap(map);
          state = AsyncValue.data(metrics);
          _reconnectAttempts = 0;

          // ---- Alarma local ----
          if (_playLocalAlarm && metrics.isDrowsy) {
            if (_player.state != PlayerState.playing) {
              if (kIsWeb && !_audioUnlocked) {
                ref.read(audioUnlockedProvider.notifier).set(false);
              } else {
                await _player.setReleaseMode(ReleaseMode.loop);
                await _player.play(AssetSource('audio/alarma.mp3'));
              }
            }
          } else if (_player.state == PlayerState.playing) {
            await _player.stop();
          }
        },
        onDone: _scheduleReconnect,
        onError: (error) {
          print('WebSocket error: $error');
          _scheduleReconnect();
        },
      );
    } catch (e) {
      print('Connection error: $e');
      state = AsyncValue.error(e, StackTrace.current);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('Max reconnection attempts reached');
      state = AsyncValue.error(
        'Failed to connect after $_maxReconnectAttempts attempts',
        StackTrace.current,
      );
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts); // backoff
    _reconnectTimer = Timer(delay, () async {
      print('Reconnection attempt $_reconnectAttempts');
      final wsUrl = ref.read(wsUrlProvider);
      await _connect(wsUrl);
    });
  }

  Future<void> setBackendBase(String url) async {
    if (_player.state == PlayerState.playing) {
      await _player.stop();
    }
    _reconnectAttempts = 0;
    ref.read(backendUrlProvider.notifier).setUrl(url);
  }

  Future<void> setConfig({
    double? earThreshold,
    double? marThreshold,
    double? pitchDegThreshold,
    double? fusionThreshold,
    double? wEar,
    double? wMar,
    double? wPose,
    int? consecFrames,
    String? frameOrientation, // 'none' | 'rotate180' | 'flip_h' | 'flip_v'
    bool? usePythonAlarm,
    int? cameraIndex,
    int? frameWidth,
    int? frameHeight,
    int? cameraFps,
    String? cameraCodec,
  }) async {
    try {
      final base = ref.read(backendUrlProvider);
      final uri = Uri.parse("$base/config");
      final body = <String, dynamic>{};
      if (earThreshold != null) body['EAR_THRESHOLD'] = earThreshold;
      if (marThreshold != null) body['MAR_THRESHOLD'] = marThreshold;
      if (pitchDegThreshold != null) {
        body['PITCH_DEG_THRESHOLD'] = pitchDegThreshold;
      }
      if (fusionThreshold != null) body['FUSION_THRESHOLD'] = fusionThreshold;
      if (wEar != null) body['W_EAR'] = wEar;
      if (wMar != null) body['W_MAR'] = wMar;
      if (wPose != null) body['W_POSE'] = wPose;

      if (consecFrames != null) body['CONSEC_FRAMES'] = consecFrames;
      if (frameOrientation != null) body['frameOrientation'] = frameOrientation;
      if (usePythonAlarm != null) body['USE_PYTHON_ALARM'] = usePythonAlarm;
      if (cameraIndex != null) body['cameraIndex'] = cameraIndex;
      if (frameWidth != null) body['frameWidth'] = frameWidth;
      if (frameHeight != null) body['frameHeight'] = frameHeight;
      if (cameraFps != null) body['cameraFps'] = cameraFps;
      if (cameraCodec != null && cameraCodec.trim().isNotEmpty) {
        body['cameraCodec'] = cameraCodec.trim().toUpperCase();
      }

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('Failed to update config: ${response.statusCode}');
      }
    } catch (e) {
      print('Error setting config: $e');
      rethrow;
    }
  }

  void toggleLocalAlarm(bool v) => _playLocalAlarm = v;

  // -------- helpers runner expuestos a la UI --------
  Future<bool> startLocalBackend({bool setUrlAndConnect = true}) async {
    if (_runner == null) {
      throw UnsupportedError(
        'Local backend runner not available on this platform',
      );
    }
    try {
      final cfg = resolveBackendPaths();
      final ok = await _runner!.start(
        pythonPath: cfg.pythonPath,
        workingDir: cfg.workDir,
        port: cfg.port,
      );
      ref.read(backendRunningProvider.notifier).set(ok);

      if (ok && setUrlAndConnect) {
        await setBackendBase('http://127.0.0.1:${cfg.port}');
      }
      return ok;
    } catch (e) {
      print('Error starting local backend: $e');
      ref.read(backendRunningProvider.notifier).set(false);
      return false;
    }
  }

  Future<void> stopLocalBackend() async {
    if (_runner != null) {
      await _runner!.stop();
    }
    ref.read(backendRunningProvider.notifier).set(false);
  }

  Stream<String> get runnerLogs => _runner?.logs ?? const Stream.empty();

  Future<bool> checkBackendHealth() async {
    try {
      final base = ref.read(backendUrlProvider);
      final response = await http
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      print('Health check failed: $e');
      return false;
    }
  }

  static const Set<String> _knownEventTypes = {
    'eye_blink',
    'micro_sleep',
    'yawn',
    'pitch_down',
    'eye_rub',
    'report_window',
  };

  bool _isEventType(String? type) =>
      type != null && _knownEventTypes.contains(type);

  DrowsyEvent? _parseEvent(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;
    final ts = _parseTimestamp(payload['ts']);
    switch (type) {
      case 'eye_blink':
        return EyeBlink(ts);
      case 'micro_sleep':
        return MicroSleep(ts, (payload['duration_s'] as num?)?.toDouble() ?? 0);
      case 'yawn':
        return YawnEvent(ts, (payload['duration_s'] as num?)?.toDouble() ?? 0);
      case 'pitch_down':
        return PitchDown(ts, (payload['duration_s'] as num?)?.toDouble() ?? 0);
      case 'eye_rub':
        return EyeRub(
          ts,
          (payload['hand'] as String?) ?? 'unknown',
          (payload['duration_s'] as num?)?.toDouble() ?? 0,
        );
      case 'report_window':
        return ReportWindow(
          ts,
          (payload['window_s'] as num?)?.toInt() ?? 0,
          (payload['counts'] as Map<String, dynamic>?) ?? const {},
          (payload['durations'] as Map<String, dynamic>?) ?? const {},
        );
      default:
        return null;
    }
  }

  DateTime _parseTimestamp(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (value * 1000).round(),
        isUtc: true,
      ).toLocal();
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return DateTime.fromMillisecondsSinceEpoch(
          (parsed * 1000).round(),
          isUtc: true,
        ).toLocal();
      }
    }
    return DateTime.now();
  }
}
