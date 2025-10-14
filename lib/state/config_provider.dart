import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

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

class ConfigNotifier extends StateNotifier<ConfigState> {
  ConfigNotifier(this._api) : super(const ConfigState()) {
    load();
  }

  final ConfigApi _api;

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
    final weights = payload.weights;

    ConfigModel updated = (state.config ?? ConfigModel.defaults()).copy();
    bool changed = state.config == null;

    bool _diff(double a, double b) => (a - b).abs() > 1e-4;

    final remoteThresholds = payload.thresholds;
    for (final tierKey in remoteThresholds.order) {
      final remoteTier = remoteThresholds.tier(tierKey);
      final localTier = updated.thresholds.tier(tierKey);
      final differs =
          _diff(remoteTier.ear, localTier.ear) ||
          _diff(remoteTier.mar, localTier.mar) ||
          _diff(remoteTier.pitch, localTier.pitch) ||
          _diff(remoteTier.fusion, localTier.fusion) ||
          remoteTier.consecFrames != localTier.consecFrames;
      if (differs) {
        updated.updateTier(tierKey, remoteTier);
        changed = true;
      }
    }

    double? _asDouble(dynamic value) => (value as num?)?.toDouble();

    if (payload.consecFrames > 0 && payload.consecFrames != updated.consecFrames) {
      updated.consecFrames = payload.consecFrames;
      changed = true;
    }

    final wEar = _asDouble(weights['ear']);
    if (wEar != null && _diff(wEar, updated.wEar)) {
      updated.wEar = wEar;
      changed = true;
    }

    final wMar = _asDouble(weights['mar']);
    if (wMar != null && _diff(wMar, updated.wMar)) {
      updated.wMar = wMar;
      changed = true;
    }

    final wPose = _asDouble(weights['pose']);
    if (wPose != null && _diff(wPose, updated.wPose)) {
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

final configProvider = StateNotifierProvider<ConfigNotifier, ConfigState>((ref) {
  final api = ref.watch(configApiProvider);
  return ConfigNotifier(api);
});

final configApiProvider = Provider<ConfigApi>((ref) {
  final baseUrl = ref.watch(backendBaseUrlProvider);
  return ConfigApi(baseUrl);
});

final backendBaseUrlProvider = Provider<String>((ref) {
  const defaultUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8000');
  return defaultUrl;
});
