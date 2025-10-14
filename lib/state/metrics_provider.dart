import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/metrics_payload.dart';

class MetricsNotifier extends StateNotifier<MetricsPayload?> {
  MetricsNotifier() : super(null);

  void update(MetricsPayload payload) {
    state = payload;
  }
}

final metricsProvider = StateNotifierProvider<MetricsNotifier, MetricsPayload?>(
  (ref) => MetricsNotifier(),
);
