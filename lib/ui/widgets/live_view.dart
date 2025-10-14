import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/base64_image.dart';
import '../../models/metrics_payload.dart';
import '../../state/metrics_provider.dart';
import '../../state/ws_provider.dart';

class LiveView extends ConsumerStatefulWidget {
  const LiveView({super.key});

  @override
  ConsumerState<LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends ConsumerState<LiveView> with AutomaticKeepAliveClientMixin {
  bool _showProcessed = true;
  String? _lastRaw;
  String? _lastProcessed;
  Uint8List? _rawBytes;
  Uint8List? _processedBytes;
  DateTime? _lastFrameAt;

  @override
  bool get wantKeepAlive => true;

  void _updateFrames(MetricsPayload? payload) {
    final raw = payload?.rawFrameB64;
    if (raw != null && raw != _lastRaw) {
      final decoded = decodeBase64Image(raw);
      if (decoded != null) {
        _rawBytes = decoded;
        _lastRaw = raw;
      }
    }

    final processed = payload?.processedFrameB64;
    if (processed != null && processed != _lastProcessed) {
      final decoded = decodeBase64Image(processed);
      if (decoded != null) {
        _processedBytes = decoded;
        _lastProcessed = processed;
      }
    }

    if (payload != null) {
      _lastFrameAt = payload.receivedAt;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final metrics = ref.watch(metricsProvider);
    _updateFrames(metrics);

    final connection = ref.watch(socketConnectionProvider);

    _SocketStatus socketStatus = _SocketStatus.connecting;
    connection.when(
      data: (value) {
        socketStatus = value ? _SocketStatus.connected : _SocketStatus.disconnected;
      },
      error: (_, __) {
        socketStatus = _SocketStatus.disconnected;
      },
      loading: () {
        socketStatus = _SocketStatus.connecting;
      },
    );

    final imageBytes = _showProcessed ? _processedBytes ?? _rawBytes : _rawBytes ?? _processedBytes;
    final hasFrame = imageBytes != null;
    final lastFrameAt = _lastFrameAt;
    final isStale = metrics?.isStale ??
        (lastFrameAt == null
            ? true
            : DateTime.now().difference(lastFrameAt) > const Duration(seconds: 5));
    final waitingForFrames = !hasFrame && socketStatus != _SocketStatus.disconnected;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161B2E),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vista en vivo',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          _showProcessed ? 'Procesado con overlay' : 'Frame sin procesar',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _ConnectionBadge(status: socketStatus),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: ToggleButtons(
                      isSelected: [_showProcessed, !_showProcessed],
                      borderRadius: BorderRadius.circular(30),
                      fillColor: Colors.blueAccent,
                      selectedColor: Colors.white,
                      color: Colors.white70,
                      constraints: const BoxConstraints(minHeight: 36, minWidth: 80),
                      onPressed: (index) {
                        setState(() {
                          _showProcessed = index == 0;
                        });
                      },
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('Procesado'),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('Raw'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageBytes != null)
                      Image.memory(
                        imageBytes,
                        gaplessPlayback: true,
                        fit: BoxFit.cover,
                      )
                    else
                      Container(
                        color: const Color(0xFF0F1423),
                        child: const Center(
                          child: Icon(Icons.videocam_off, color: Colors.white38, size: 64),
                        ),
                      ),
                    _OverlayMetrics(metrics: metrics),
                    if (socketStatus != _SocketStatus.connected)
                      _StatusBanner(
                        icon: Icons.wifi_tethering_off,
                        message: socketStatus == _SocketStatus.connecting
                            ? 'Conectando con el backend...'
                            : 'Conexión perdida. Reintentando...',
                      )
                    else if (waitingForFrames)
                      const _StatusBanner(
                        icon: Icons.hourglass_top,
                        message: 'Esperando primeros frames... Asegúrate de que la cámara esté activa.',
                      )
                    else if (isStale)
                      _StatusBanner(
                        icon: Icons.schedule,
                        message: 'Sin datos recientes · ${_humanizeDelay(_lastFrameAt)}',
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _humanizeDelay(DateTime? instant) {
  if (instant == null) return '--';
  final diff = DateTime.now().difference(instant).inSeconds;
  if (diff < 1) return 'instante';
  if (diff == 1) return '1 s';
  if (diff < 60) return '$diff s';
  final minutes = (diff / 60).floor();
  if (minutes == 1) return '1 min';
  return '$minutes min';
}

enum _SocketStatus { connected, connecting, disconnected }

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.status});

  final _SocketStatus status;

  Color get _color {
    switch (status) {
      case _SocketStatus.connected:
        return Colors.greenAccent;
      case _SocketStatus.connecting:
        return Colors.orangeAccent;
      case _SocketStatus.disconnected:
        return Colors.redAccent;
    }
  }

  String get _label {
    switch (status) {
      case _SocketStatus.connected:
        return 'Conectado';
      case _SocketStatus.connecting:
        return 'Conectando';
      case _SocketStatus.disconnected:
        return 'Sin conexión';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _color.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            _label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayMetrics extends StatelessWidget {
  const _OverlayMetrics({required this.metrics});

  final MetricsPayload? metrics;

  Color _statusColor(BuildContext context) {
    if (metrics?.isDrowsy == true) return Colors.redAccent;
    if ((metrics?.fusedScore ?? 0) > ((metrics?.thresholds['fusion'] as num?)?.toDouble() ?? 0.7)) {
      return Colors.orangeAccent;
    }
    return Colors.greenAccent;
  }

  @override
  Widget build(BuildContext context) {
    if (metrics == null) {
      return const SizedBox.shrink();
    }

    final textTheme = Theme.of(context).textTheme;
    final reason = metrics!.reason;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _statusColor(context).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _statusColor(context)),
                ),
                child: Text(
                  metrics!.isDrowsy ? 'ALERTA' : 'Atento',
                  style: textTheme.labelLarge?.copyWith(
                    color: _statusColor(context),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (reason.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    reason.join(' · '),
                    style: textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ),
            ],
          ),
          const Spacer(),
          Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: DefaultTextStyle(
                style: (textTheme.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(color: Colors.white),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _metricRow('EAR', metrics!.ear),
                    _metricRow('MAR', metrics!.mar),
                    _metricRow('Pitch', metrics!.pitch),
                    _metricRow('Fused', metrics!.fusedScore),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String label, double? value) {
    final formatted = value != null ? value.toStringAsFixed(2) : '--';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 60, child: Text(label)),
          Text(formatted, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
