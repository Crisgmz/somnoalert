import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ws/drowsy_socket.dart';
import '../models/events.dart';
import '../models/metrics_payload.dart';
import 'config_provider.dart';

Uri _buildWsUri(String baseUrl) {
  final base = Uri.parse(baseUrl);
  final scheme = base.scheme == 'https' ? 'wss' : 'ws';
  final segments = [
    ...base.pathSegments.where((segment) => segment.isNotEmpty),
    'ws',
  ];

  return Uri(
    scheme: scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    pathSegments: segments,
  );
}

final drowsySocketProvider = Provider<DrowsySocket>((ref) {
  final baseUrl = ref.watch(backendBaseUrlProvider);
  final socket = DrowsySocket(_buildWsUri(baseUrl));
  ref.onDispose(socket.dispose);
  return socket;
});

final metricsStreamProvider = StreamProvider<MetricsPayload>((ref) {
  final socket = ref.watch(drowsySocketProvider);
  return socket.metricsStream;
});

final eventsStreamProvider = StreamProvider<DrowsyEvent>((ref) {
  final socket = ref.watch(drowsySocketProvider);
  return socket.eventsStream;
});
