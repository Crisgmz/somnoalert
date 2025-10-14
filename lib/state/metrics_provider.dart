import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/metrics_payload.dart';

class MetricsNotifier extends Notifier<MetricsPayload?> {
  @override
  MetricsPayload? build() => null;

  void update(MetricsPayload payload) => state = payload;
}

final metricsProvider = NotifierProvider<MetricsNotifier, MetricsPayload?>(
  MetricsNotifier.new,
);
