import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/config_api.dart';
import '../models/config_model.dart';

class ConfigState {
  const ConfigState({this.config, this.loading = false, this.error});

  final ConfigModel? config;
  final bool loading;
  final String? error;

  ConfigState copyWith({
    ConfigModel? config,
    bool? loading,
    String? error,
  }) {
    return ConfigState(
      config: config ?? this.config,
      loading: loading ?? this.loading,
      error: error,
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
