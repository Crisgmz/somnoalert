import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/ws_service.dart';
import '../model.dart';

/// URL base del backend (cámbiala desde UI).
final backendUrlProvider = NotifierProvider<BackendUrlNotifier, String>(
  BackendUrlNotifier.new,
);

class BackendUrlNotifier extends Notifier<String> {
  @override
  String build() => "http://127.0.0.1:8000";

  void setUrl(String url) => state = url;
}

/// WS derivado de la URL base.
final wsUrlProvider = Provider<String>((ref) {
  final base = ref.watch(backendUrlProvider);
  return "${base.replaceFirst("http", "ws")}/ws";
});

/// Provider principal con Riverpod 3 (AsyncNotifier)
final drowsyControllerProvider =
    AsyncNotifierProvider<DrowsyController, DrowsyMetrics?>(
      DrowsyController.new,
    );

class DrowsyController extends AsyncNotifier<DrowsyMetrics?> {
  WsService? _ws;
  final _player = AudioPlayer();
  bool _playLocalAlarm = true;
  Timer? _reconnectTimer;

  @override
  Future<DrowsyMetrics?> build() async {
    // Conectamos al WS según la URL actual
    final wsUrl = ref.watch(wsUrlProvider);

    // Si cambia el backend/WS, reconstruimos y reconectamos automáticamente
    await _connect(wsUrl);

    // Limpiar recursos al destruir el provider
    ref.onDispose(() async {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _ws?.dispose();
      _ws = null;
      await _player.stop();
      await _player.dispose();
    });

    // Estado inicial
    return null;
  }

  Future<void> _connect(String wsUrl) async {
    // Cierra if exist
    _reconnectTimer?.cancel();
    _ws?.dispose();

    _ws = WsService(wsUrl);

    // Muestra estado "cargando" durante la conexión
    state = const AsyncLoading();

    _ws!.connect(
      (map) async {
        final metrics = DrowsyMetrics.fromMap(map);

        // Publica nuevas métricas
        state = AsyncValue.data(metrics);

        // Alarma local opcional
        if (_playLocalAlarm && metrics.isDrowsy) {
          if (_player.state != PlayerState.playing) {
            await _player.setReleaseMode(ReleaseMode.loop);
            await _player.play(AssetSource('audio/alarma.mp3'));
          }
        } else {
          if (_player.state == PlayerState.playing) {
            await _player.stop();
          }
        }
      },
      onDone: () => _scheduleReconnect(),
      onError: (_) => _scheduleReconnect(),
    );
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    // Pequeño backoff fijo; puedes hacerlo exponencial si quieres
    _reconnectTimer = Timer(const Duration(seconds: 2), () async {
      final wsUrl = ref.read(wsUrlProvider);
      await _connect(wsUrl);
    });
  }

  /// Cambia el backend. El rebuild del provider se encarga de reconectar.
  Future<void> setBackendBase(String url) async {
    // Detén audio para evitar loops en el cambio
    if (_player.state == PlayerState.playing) {
      await _player.stop();
    }
    ref.read(backendUrlProvider.notifier).setUrl(url);
  }

  /// Cambia configuración del backend (umbral y frames).
  Future<void> setConfig({double? earThreshold, int? consecFrames}) async {
    final base = ref.read(backendUrlProvider);
    final uri = Uri.parse("$base/config");
    final body = <String, dynamic>{};
    if (earThreshold != null) body['EAR_THRESHOLD'] = earThreshold;
    if (consecFrames != null) body['CONSEC_FRAMES'] = consecFrames;

    await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }

  /// Habilita/Deshabilita alarma local en el dispositivo Flutter.
  void toggleLocalAlarm(bool v) => _playLocalAlarm = v;
}
