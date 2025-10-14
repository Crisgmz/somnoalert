import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/config_api.dart';
import '../models/config_model.dart';
import '../models/metrics_payload.dart';

class ConfigState {
  const ConfigState({this.config, this.loading = false, this.error, this.liveSnapshot});

  final ConfigModel? config;
  final bool loading;
  final String? error;
  final MetricsConfigSnapshot? liveSnapshot;

  ConfigState copyWith({
    ConfigModel? config,
    bool? loading,
    String? error,
    MetricsConfigSnapshot? liveSnapshot,
  }) {
    return ConfigState(
      config: config ?? this.config,
      loading: loading ?? this.loading,
      error: error,
      liveSnapshot: liveSnapshot ?? this.liveSnapshot,
    );
  }
}

class ConfigNotifier extends Notifier<ConfigState> {
  late final ConfigApi _api;

  @override
  ConfigState build() {
    _api = ref.watch(configApiProvider);
    // Load initial config asynchronously
    Future.microtask(load);
    return const ConfigState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final config = await _api.getConfig();
      state = state.copyWith(config: config, loading: false, error: null);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<bool> save(ConfigModel config) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final updated = await _api.updateConfig(config);
      state = state.copyWith(config: updated, loading: false, error: null);
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
      return false;
    }
  }

  void hydrateFromMetrics(MetricsPayload payload) {
    final thresholds = payload.thresholds;
    final weights = payload.weights;

    ConfigModel updated = (state.config ?? ConfigModel.defaults()).copy();
    bool changed = state.config == null;

    double? _asDouble(dynamic value) => (value as num?)?.toDouble();

    final ear = thresholds.tier('drowsy').ear;
    if (ear != updated.earThr) {
      updated.earThr = ear;
      changed = true;
    }

    final mar = thresholds.tier('drowsy').mar;
    if (mar != updated.marThr) {
      updated.marThr = mar;
      changed = true;
    }

    final pitch = thresholds.tier('drowsy').pitch;
    if (pitch != updated.pitchThr) {
      updated.pitchThr = pitch;
      changed = true;
    }

    final fusion = thresholds.tier('drowsy').fusion;
    if (fusion != updated.fusionThr) {
      updated.fusionThr = fusion;
      changed = true;
    }

    if (payload.consecFrames > 0 && payload.consecFrames != updated.consecFrames) {
      updated.consecFrames = payload.consecFrames;
      changed = true;
    }

    final wEar = _asDouble(weights['ear']);
    if (wEar != null && wEar != updated.wEar) {
      updated.wEar = wEar;
      changed = true;
    }

    final wMar = _asDouble(weights['mar']);
    if (wMar != null && wMar != updated.wMar) {
      updated.wMar = wMar;
      changed = true;
    }

    final wPose = _asDouble(weights['pose']);
    if (wPose != null && wPose != updated.wPose) {
      updated.wPose = wPose;
      changed = true;
    }

    final remoteAlarm = payload.configSnapshot?.usePythonAlarm;
    if (remoteAlarm != null && remoteAlarm != updated.usePythonAlarm) {
      updated.usePythonAlarm = remoteAlarm;
      changed = true;
    }

    final liveSnapshot = payload.configSnapshot ?? state.liveSnapshot;

    if (changed || liveSnapshot != state.liveSnapshot) {
      state = state.copyWith(
        config: updated,
        loading: false,
        error: null,
        liveSnapshot: liveSnapshot,
      );
    }
  }
}

final configProvider = NotifierProvider<ConfigNotifier, ConfigState>(ConfigNotifier.new);

final configApiProvider = Provider<ConfigApi>((ref) {
  final baseUrl = ref.watch(backendBaseUrlProvider);
  return ConfigApi(baseUrl);
});

final backendBaseUrlProvider = Provider<String>((ref) {
  const defaultUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8000');
  return defaultUrl;
});
