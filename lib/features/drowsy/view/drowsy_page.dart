import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../model.dart';
import '../state/drowsy_controller.dart';

class DrowsyPage extends ConsumerStatefulWidget {
  const DrowsyPage({super.key});

  @override
  ConsumerState<DrowsyPage> createState() => _DrowsyPageState();
}

class _DrowsyPageState extends ConsumerState<DrowsyPage> {
  final _backendCtrl = TextEditingController(text: 'http://127.0.0.1:8000');
  double _threshold = 0.20;
  double _frames = 50;
  bool _localAlarm = true;

  Uint8List? _lastRawFrame;
  Uint8List? _lastProcessedFrame;
  bool _wasAlerting = false;
  final List<_AlertLogEntry> _alertLog = [];

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<DrowsyMetrics?>>(drowsyControllerProvider, _onMetrics);
    final state = ref.watch(drowsyControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drowsiness Monitor'),
        actions: [
          Switch(
            value: _localAlarm,
            onChanged: (v) {
              setState(() => _localAlarm = v);
              ref.read(drowsyControllerProvider.notifier).toggleLocalAlarm(v);
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _buildConnectionControls(),
            const SizedBox(height: 16),
            state.when(
              data: (metrics) => _buildDashboard(metrics),
              loading: () => const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SizedBox(
                height: 160,
                child: Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onMetrics(
    AsyncValue<DrowsyMetrics?>? previous,
    AsyncValue<DrowsyMetrics?> next,
  ) {
    next.whenData((metrics) {
      final isDrowsy = metrics?.isDrowsy ?? false;
      if (isDrowsy != _wasAlerting) {
        if (!mounted) {
          _wasAlerting = isDrowsy;
          return;
        }
        final earText = metrics?.ear != null ? metrics!.ear!.toStringAsFixed(3) : '--';
        final message =
            isDrowsy ? 'Somnolencia detectada (EAR: $earText)' : 'Alerta despejada';
        setState(() {
          _alertLog.insert(
            0,
            _AlertLogEntry(
              timestamp: DateTime.now(),
              message: message,
              isAlert: isDrowsy,
            ),
          );
          if (_alertLog.length > 20) {
            _alertLog.removeLast();
          }
          _wasAlerting = isDrowsy;
        });
      } else {
        _wasAlerting = isDrowsy;
      }
    });
  }

  Widget _buildConnectionControls() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _backendCtrl,
            decoration: const InputDecoration(
              labelText: 'Backend URL (http://IP:8000)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () {
            ref
                .read(drowsyControllerProvider.notifier)
                .setBackendBase(_backendCtrl.text.trim());
          },
          child: const Text('Conectar'),
        ),
      ],
    );
  }

  Widget _buildDashboard(DrowsyMetrics? metrics) {
    final earValue = metrics?.ear;
    final earText =
        earValue != null ? earValue.toStringAsFixed(3) : '--';
    final closedFrames = metrics?.closedFrames ?? 0;
    final isDrowsy = metrics?.isDrowsy ?? false;
    final currentThreshold = metrics?.threshold ?? _threshold;
    final currentFrames = metrics?.consecFrames ?? _frames.toInt();

    _threshold = currentThreshold;
    _frames = currentFrames.toDouble();

    if (metrics?.rawFrame != null) {
      _lastRawFrame = metrics!.rawFrame;
    }
    if (metrics?.processedFrame != null) {
      _lastProcessedFrame = metrics!.processedFrame;
    }

    final rawFrame = metrics?.rawFrame ?? _lastRawFrame;
    final processedFrame = metrics?.processedFrame ?? _lastProcessedFrame;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _alertBanner(
          isDrowsy: isDrowsy,
          earText: earText,
          closedFrames: closedFrames,
        ),
        const SizedBox(height: 16),
        _cameraGrid(
          rawFrame: rawFrame,
          processedFrame: processedFrame,
          isAlert: isDrowsy,
          earText: earText,
          closedFrames: closedFrames,
        ),
        const SizedBox(height: 16),
        _metricsCard(
          earText: earText,
          closedFrames: closedFrames,
          isDrowsy: isDrowsy,
          threshold: currentThreshold,
          consecutiveFrames: currentFrames,
        ),
        const SizedBox(height: 16),
        _configurationCard(),
        if (_alertLog.isNotEmpty) ...[
          const SizedBox(height: 16),
          _alertsTimeline(),
        ],
      ],
    );
  }
  Widget _alertBanner({
    required bool isDrowsy,
    required String earText,
    required int closedFrames,
  }) {
    final color = isDrowsy ? Colors.redAccent : Colors.green;
    final background = isDrowsy
        ? Colors.redAccent.withOpacity(0.12)
        : Colors.green.withOpacity(0.12);
    final icon = isDrowsy
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline;
    final title = isDrowsy
        ? 'ALERTA DE SOMNOLENCIA'
        : 'Monitoreo estable';
    final subtitle = isDrowsy
        ? 'Ojos cerrados detectados durante $closedFrames frames consecutivos.'
        : 'EAR actual $earText · Frames cerrados: $closedFrames';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5), width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraGrid({
    required Uint8List? rawFrame,
    required Uint8List? processedFrame,
    required bool isAlert,
    required String earText,
    required int closedFrames,
  }) {
    final cards = <Widget>[];
    if (rawFrame != null) {
      cards.add(
        _cameraCard(
          title: 'Cámara',
          bytes: rawFrame,
          isAlert: isAlert,
          earText: earText,
          closedFrames: closedFrames,
        ),
      );
    }
    if (processedFrame != null) {
      cards.add(
        _cameraCard(
          title: 'Procesada',
          bytes: processedFrame,
          isAlert: isAlert,
          earText: earText,
          closedFrames: closedFrames,
        ),
      );
    }

    if (cards.isEmpty) {
      return _cameraPlaceholder();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600 && cards.length > 1;
        final itemWidth =
            isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map((card) => SizedBox(width: itemWidth, child: card))
              .toList(),
        );
      },
    );
  }

  Widget _cameraCard({
    required String title,
    required Uint8List bytes,
    required bool isAlert,
    required String earText,
    required int closedFrames,
  }) {
    final earStyle = TextStyle(
      color: isAlert ? Colors.orangeAccent : Colors.white,
      fontWeight: FontWeight.w700,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.memory(
              bytes,
              gaplessPlayback: true,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: AnimatedOpacity(
              opacity: isAlert ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'ALERTA',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black87,
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.remove_red_eye_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text('EAR $earText', style: earStyle),
                  const Spacer(),
                  Text(
                    'Frames cerrados: $closedFrames',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraPlaceholder() {
    final theme = Theme.of(context);
    return Card(
      child: SizedBox(
        height: 220,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.videocam_off_outlined,
                size: 42,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                'Conecta el backend para ver las cámaras en vivo.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricsCard({
    required String earText,
    required int closedFrames,
    required bool isDrowsy,
    required double threshold,
    required int consecutiveFrames,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Métricas en vivo',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _metric('EAR actual', earText),
            _metric(
              'Frames con ojos cerrados',
              '$closedFrames',
              isAlert: closedFrames > 0,
            ),
            _metric(
              'Estado',
              isDrowsy ? 'ALERTA de somnolencia' : 'Sin alertas',
              isAlert: isDrowsy,
            ),
            const Divider(height: 24),
            _metric(
              'Umbral EAR configurado',
              threshold.toStringAsFixed(3),
            ),
            _metric(
              'Frames consecutivos configurados',
              '$consecutiveFrames',
            ),
          ],
        ),
      ),
    );
  }

  Widget _configurationCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ajustes del detector',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _slider(
              label: 'Umbral EAR',
              value: _threshold,
              min: 0.05,
              max: 0.5,
              step: 0.005,
              onChanged: (v) => setState(() => _threshold = v),
              onSubmit: () => ref
                  .read(drowsyControllerProvider.notifier)
                  .setConfig(earThreshold: _threshold),
            ),
            const SizedBox(height: 16),
            _sliderInt(
              label: 'Frames consecutivos',
              value: _frames.toInt(),
              min: 5,
              max: 120,
              step: 1,
              onChanged: (v) => setState(() => _frames = v.toDouble()),
              onSubmit: () => ref
                  .read(drowsyControllerProvider.notifier)
                  .setConfig(consecFrames: _frames.toInt()),
            ),
            const SizedBox(height: 8),
            Text(
              'Los cambios se envían al backend al presionar "Aplicar".',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
  Widget _metric(String k, String v, {bool isAlert = false}) {
    final color = isAlert ? Colors.orangeAccent : Colors.black87;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            '$k: ',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
    required VoidCallback onSubmit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(value.toStringAsFixed(3)),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: onSubmit, child: const Text('Aplicar')),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _sliderInt({
    required String label,
    required int value,
    required int min,
    required int max,
    required int step,
    required ValueChanged<int> onChanged,
    required VoidCallback onSubmit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('$value'),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: onSubmit, child: const Text('Aplicar')),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: ((max - min) / step).round(),
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }

  Widget _alertsTimeline() {
    final theme = Theme.of(context);
    final entries = _alertLog.take(6).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Historial de alertas',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Text(
                'Aún no hay alertas registradas.',
                style: theme.textTheme.bodyMedium,
              ),
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 16),
              _alertLogTile(entries[i], theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _alertLogTile(_AlertLogEntry entry, ThemeData theme) {
    final color = entry.isAlert ? Colors.redAccent : Colors.green;
    final icon =
        entry.isAlert ? Icons.warning_amber_rounded : Icons.check_circle_outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.message,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatTime(entry.timestamp),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _AlertLogEntry {
  const _AlertLogEntry({
    required this.timestamp,
    required this.message,
    required this.isAlert,
  });

  final DateTime timestamp;
  final String message;
  final bool isAlert;
}
