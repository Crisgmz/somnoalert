import 'dart:typed_data';
import 'package:flutter/foundation.dart';
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

  // Umbrales y pesos locales (se actualizan con lo que llega del backend)
  double _threshold = 0.20; // EAR
  double _frames = 50;
  double _marThr = 0.60;
  double _pitchThr = 20;
  double _fusionThr = 0.70;
  double _wEar = 0.5, _wMar = 0.3, _wPose = 0.2;

  bool _localAlarm = true;
  bool _isAutoConnecting = false;

  Uint8List? _lastRawFrame;
  Uint8List? _lastProcessedFrame;
  bool _wasAlerting = false;
  final List<_AlertLogEntry> _alertLog = [];

  // Runner log buffer (solo para desktop)
  final List<String> _runnerLogs = [];
  late final Stream<String> _runnerLogStream;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WakelockPlus.enable();
    }

    // Logs solo en desktop
    if (!kIsWeb) {
      _runnerLogStream = ref.read(drowsyControllerProvider.notifier).runnerLogs;
      _runnerLogStream.listen((line) {
        if (mounted) {
          setState(() {
            _runnerLogs.insert(0, line.trimRight());
            if (_runnerLogs.length > 200) _runnerLogs.removeLast();
          });
        }
      });
    }

    // Auto-conectar en web
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoConnectWeb();
      });
    }
  }

  Future<void> _autoConnectWeb() async {
    setState(() => _isAutoConnecting = true);
    try {
      final controller = ref.read(drowsyControllerProvider.notifier);
      await controller.setBackendBase(_backendCtrl.text);

      await Future.delayed(const Duration(seconds: 2));

      final isHealthy = await controller.checkBackendHealth();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isHealthy
                  ? 'Conectado al backend automáticamente'
                  : 'No se pudo conectar al backend. Verifica que esté ejecutándose.',
            ),
            backgroundColor: isHealthy ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al conectar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAutoConnecting = false);
    }
  }

  @override
  void dispose() {
    _backendCtrl.dispose();
    if (!kIsWeb) {
      WakelockPlus.disable();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<DrowsyMetrics?>>(
      drowsyControllerProvider,
      _onMetrics,
    );

    final state = ref.watch(drowsyControllerProvider);
    final backendUp = ref.watch(backendRunningProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(kIsWeb ? 'Drowsiness Monitor (Web)' : 'Drowsiness Monitor'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Row(
            children: [
              const Text('Alarma local'),
              const SizedBox(width: 8),
              Switch(
                value: _localAlarm,
                onChanged: (v) {
                  setState(() => _localAlarm = v);
                  ref
                      .read(drowsyControllerProvider.notifier)
                      .toggleLocalAlarm(v);
                },
              ),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            if (kIsWeb)
              _buildWebConnectionControls()
            else
              _buildConnectionControls(backendUp),
            const SizedBox(height: 16),
            state.when(
              data: (metrics) => _buildDashboard(metrics),
              loading: () => SizedBox(
                height: 220,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _isAutoConnecting
                            ? 'Conectando automáticamente...'
                            : 'Conectando al backend...',
                      ),
                    ],
                  ),
                ),
              ),
              error: (e, _) => SizedBox(
                height: 160,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Error de conexión',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          '$e',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _autoConnectWeb,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar conexión'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!kIsWeb) _logsCard(),
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
      if (metrics == null) return;

      // Actualizar sliders con lo que mande el backend (si viene)
      _marThr = metrics.marThreshold ?? _marThr;
      _pitchThr = metrics.pitchDegThreshold ?? _pitchThr;
      _fusionThr = metrics.fusionThreshold ?? _fusionThr;
      _wEar = metrics.wEar ?? _wEar;
      _wMar = metrics.wMar ?? _wMar;
      _wPose = metrics.wPose ?? _wPose;

      final isDrowsy = metrics.isDrowsy;
      if (isDrowsy != _wasAlerting) {
        if (!mounted) {
          _wasAlerting = isDrowsy;
          return;
        }
        final earText = metrics.ear != null
            ? metrics.ear!.toStringAsFixed(3)
            : '--';
        final message = isDrowsy
            ? 'Somnolencia detectada (EAR: $earText)'
            : 'Alerta despejada';
        setState(() {
          _alertLog.insert(
            0,
            _AlertLogEntry(
              timestamp: DateTime.now(),
              message: message,
              isAlert: isDrowsy,
            ),
          );
          if (_alertLog.length > 20) _alertLog.removeLast();
          _wasAlerting = isDrowsy;
        });
      } else {
        _wasAlerting = isDrowsy;
      }
    });
  }

  Widget _buildWebConnectionControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.web, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Conexión Web al Backend',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Instrucciones para ejecutar el backend:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. Abre una terminal en la carpeta "drowsy-backend"\n'
                    '2. Ejecuta: .venv\\Scripts\\python.exe -m uvicorn app:app --host 0.0.0.0 --port 8000\n'
                    '3. Verifica que aparezca "Application startup complete"',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.blue[700],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_isAutoConnecting)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Conectando automáticamente...',
                      style: TextStyle(color: Colors.orange[700]),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _backendCtrl,
                    decoration: const InputDecoration(
                      labelText: 'URL del Backend',
                      hintText: 'http://127.0.0.1:8000',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isAutoConnecting
                      ? null
                      : () {
                          final url = _backendCtrl.text.trim();
                          if (url.isNotEmpty) {
                            ref
                                .read(drowsyControllerProvider.notifier)
                                .setBackendBase(url);
                          }
                        },
                  icon: const Icon(Icons.connect_without_contact),
                  label: const Text('Conectar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isAutoConnecting
                      ? null
                      : () async {
                          final controller = ref.read(
                            drowsyControllerProvider.notifier,
                          );
                          final isHealthy = await controller
                              .checkBackendHealth();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isHealthy
                                      ? 'Backend funcionando correctamente'
                                      : 'Backend no disponible',
                                ),
                                backgroundColor: isHealthy
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.health_and_safety),
                  label: const Text('Verificar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'La aplicación web se conecta automáticamente al iniciarse. Asegúrate de que el backend esté ejecutándose.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionControls(bool backendUp) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conexión al Backend',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final ok = await ref
                          .read(drowsyControllerProvider.notifier)
                          .startLocalBackend(setUrlAndConnect: true);
                      if (ok) {
                        _backendCtrl.text = 'http://127.0.0.1:8000';
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Backend iniciado')),
                          );
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No se pudo iniciar el backend'),
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.play_circle_fill),
                  label: const Text('Arrancar backend local'),
                ),
                ElevatedButton.icon(
                  onPressed: backendUp
                      ? () async {
                          await ref
                              .read(drowsyControllerProvider.notifier)
                              .stopLocalBackend();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Backend detenido')),
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Detener backend'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                  ),
                ),
                backendUp
                    ? const Chip(
                        label: Text('Backend activo'),
                        avatar: Icon(Icons.check_circle, color: Colors.green),
                      )
                    : const Chip(
                        label: Text('Backend inactivo'),
                        avatar: Icon(Icons.cancel, color: Colors.redAccent),
                      ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _backendCtrl,
                    decoration: const InputDecoration(
                      labelText: 'URL del Backend',
                      hintText: 'http://192.168.1.100:8000',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    final url = _backendCtrl.text.trim();
                    if (url.isNotEmpty) {
                      ref
                          .read(drowsyControllerProvider.notifier)
                          .setBackendBase(url);
                    }
                  },
                  icon: const Icon(Icons.connect_without_contact),
                  label: const Text('Conectar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Si usas un dispositivo móvil, usa la IP de tu computadora (ej: 192.168.1.100:8000)',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(DrowsyMetrics? metrics) {
    final earValue = metrics?.ear;
    final marValue = metrics?.mar;
    final yaw = metrics?.yaw, pitch = metrics?.pitch, roll = metrics?.roll;
    final fused = metrics?.fusedScore;
    final reasons = metrics?.reason ?? [];

    final earText = earValue != null ? earValue.toStringAsFixed(3) : '--';
    final marText = marValue != null ? marValue.toStringAsFixed(3) : '--';
    final poseText = (pitch != null || yaw != null || roll != null)
        ? 'P:${pitch?.toStringAsFixed(1) ?? "--"}°  '
              'Y:${yaw?.toStringAsFixed(1) ?? "--"}°  '
              'R:${roll?.toStringAsFixed(1) ?? "--"}°'
        : '--';
    final fusedText = fused != null ? fused.toStringAsFixed(2) : '--';

    final closedFrames = metrics?.closedFrames ?? 0;
    final isDrowsy = metrics?.isDrowsy ?? false;

    final currentThreshold = metrics?.threshold ?? _threshold; // EAR
    final currentFrames = metrics?.consecFrames ?? _frames.toInt();

    // Actualizar UI local con valores más recientes
    _threshold = currentThreshold;
    _frames = currentFrames.toDouble();
    _marThr = metrics?.marThreshold ?? _marThr;
    _pitchThr = metrics?.pitchDegThreshold ?? _pitchThr;
    _fusionThr = metrics?.fusionThreshold ?? _fusionThr;
    _wEar = metrics?.wEar ?? _wEar;
    _wMar = metrics?.wMar ?? _wMar;
    _wPose = metrics?.wPose ?? _wPose;

    if (metrics?.rawFrame != null) _lastRawFrame = metrics!.rawFrame;
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
          info: isDrowsy
              ? (reasons.isEmpty
                    ? 'Alertas: —'
                    : 'Alertas: ${reasons.join(", ")}')
              : 'EAR $earText · Frames cerrados: $closedFrames',
        ),
        const SizedBox(height: 16),
        _cameraGrid(
          rawFrame: rawFrame,
          processedFrame: processedFrame,
          isAlert: isDrowsy,
          earText: earText,
          marText: marText,
          closedFrames: closedFrames,
        ),
        const SizedBox(height: 16),
        _metricsCard(
          earText: earText,
          marText: marText,
          poseText: poseText,
          fusedText: fusedText,
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

  Widget _alertBanner({required bool isDrowsy, required String info}) {
    final color = isDrowsy ? Colors.redAccent : Colors.green;
    final background = isDrowsy
        ? Colors.redAccent.withOpacity(0.12)
        : Colors.green.withOpacity(0.12);
    final icon = isDrowsy
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline;
    final title = isDrowsy ? 'ALERTA DE SOMNOLENCIA' : 'Monitoreo estable';

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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(icon, key: ValueKey(isDrowsy), color: color, size: 32),
          ),
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
                Text(info, style: Theme.of(context).textTheme.bodyMedium),
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
    required String marText,
    required int closedFrames,
  }) {
    final cards = <Widget>[];
    if (rawFrame != null) {
      cards.add(
        _cameraCard(
          title: 'Cámara Original',
          bytes: rawFrame,
          isAlert: isAlert,
          earText: earText,
          marText: marText,
          closedFrames: closedFrames,
        ),
      );
    }
    if (processedFrame != null) {
      cards.add(
        _cameraCard(
          title: 'Análisis Facial',
          bytes: processedFrame,
          isAlert: isAlert,
          earText: earText,
          marText: marText,
          closedFrames: closedFrames,
        ),
      );
    }
    if (cards.isEmpty) return _cameraPlaceholder();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600 && cards.length > 1;
        final itemWidth = isWide
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map((c) => SizedBox(width: itemWidth, child: c))
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
    required String marText,
    required int closedFrames,
  }) {
    final earStyle = TextStyle(
      color: isAlert ? Colors.orangeAccent : Colors.white,
      fontWeight: FontWeight.w700,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isAlert ? 8 : 2,
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
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'ALERTA',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.remove_red_eye_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text('EAR $earText', style: earStyle),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.mood_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'MAR $marText',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Frames: $closedFrames',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
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
        height: 280,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.videocam_off_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                kIsWeb
                    ? 'Esperando conexión al backend'
                    : 'Conecta al backend para ver las cámaras',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                kIsWeb
                    ? 'Asegúrate de ejecutar el backend Python\ny permitir permisos de cámara en el navegador'
                    : 'Verifica que el servidor esté ejecutándose\ny que la URL sea correcta',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
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
    required String marText,
    required String poseText,
    required String fusedText,
    required int closedFrames,
    required bool isDrowsy,
    required double threshold,
    required int consecutiveFrames,
  }) {
    final theme = Theme.of(context);
    final fusedVal = double.tryParse(fusedText) ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: theme.primaryColor),
                const SizedBox(width: 8),
                Text('Métricas en vivo', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            _metric('EAR actual', earText, icon: Icons.visibility),
            _metric('MAR actual', marText, icon: Icons.mood),
            _metric(
              'Pose (yaw/pitch/roll)',
              poseText,
              icon: Icons.threed_rotation,
            ),
            _metric(
              'Score de fusión',
              fusedText,
              isAlert: fusedVal >= _fusionThr,
              icon: Icons.auto_graph,
            ),
            _metric(
              'Frames con ojos cerrados',
              '$closedFrames',
              isAlert: closedFrames > 0,
              icon: Icons.timelapse,
            ),
            _metric(
              'Estado del sistema',
              isDrowsy ? 'ALERTA de somnolencia' : 'Sin alertas',
              isAlert: isDrowsy,
              icon: isDrowsy ? Icons.warning : Icons.check_circle,
            ),
            const Divider(height: 24),
            _metric(
              'Umbral EAR',
              threshold.toStringAsFixed(3),
              icon: Icons.tune,
            ),
            _metric('Umbral MAR', _marThr.toStringAsFixed(3), icon: Icons.tune),
            _metric(
              'Umbral Pitch (°)',
              _pitchThr.toStringAsFixed(0),
              icon: Icons.tune,
            ),
            _metric(
              'Umbral Fusión',
              _fusionThr.toStringAsFixed(2),
              icon: Icons.merge_type,
            ),
            _metric(
              'Pesos (EAR/MAR/Pose)',
              '${_wEar.toStringAsFixed(2)}/${_wMar.toStringAsFixed(2)}/${_wPose.toStringAsFixed(2)}',
              icon: Icons.scale,
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
            Row(
              children: [
                Icon(Icons.settings, color: theme.primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Configuración del Detector',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 20),
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
            const SizedBox(height: 20),
            _slider(
              label: 'Umbral MAR (bostezo)',
              value: _marThr,
              min: 0.3,
              max: 1.2,
              step: 0.01,
              onChanged: (v) => setState(() => _marThr = v),
              onSubmit: () => ref
                  .read(drowsyControllerProvider.notifier)
                  .setConfig(marThreshold: _marThr),
            ),
            const SizedBox(height: 20),
            _slider(
              label: 'Umbral Pitch (°) (cabeceo)',
              value: _pitchThr,
              min: 5,
              max: 45,
              step: 1,
              onChanged: (v) => setState(() => _pitchThr = v),
              onSubmit: () => ref
                  .read(drowsyControllerProvider.notifier)
                  .setConfig(pitchDegThreshold: _pitchThr),
            ),
            const SizedBox(height: 20),
            _slider(
              label: 'Umbral de Fusión (0–1)',
              value: _fusionThr,
              min: 0.3,
              max: 0.95,
              step: 0.01,
              onChanged: (v) => setState(() => _fusionThr = v),
              onSubmit: () => ref
                  .read(drowsyControllerProvider.notifier)
                  .setConfig(fusionThreshold: _fusionThr),
            ),
            const SizedBox(height: 20),
            _textWeightsInfo(),
            _weightsSliders(),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Los cambios se aplican al presionar los botones "Aplicar".',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textWeightsInfo() {
    final sum = (_wEar + _wMar + _wPose);
    final ok = (sum - 1.0).abs() < 0.02;
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Pesos de fusión (deben sumar ~1.0). Suma actual: ${sum.toStringAsFixed(2)}',
            style: TextStyle(
              color: ok ? Colors.green[700] : Colors.orange[700],
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => setState(() {
            final s = _wEar + _wMar + _wPose;
            if (s > 0) {
              _wEar /= s;
              _wMar /= s;
              _wPose /= s;
            }
          }),
          icon: const Icon(Icons.balance),
          label: const Text('Normalizar'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => ref
              .read(drowsyControllerProvider.notifier)
              .setConfig(wEar: _wEar, wMar: _wMar, wPose: _wPose),
          icon: const Icon(Icons.send),
          label: const Text('Aplicar'),
        ),
      ],
    );
  }

  Widget _weightsSliders() {
    return Column(
      children: [
        const SizedBox(height: 8),
        _slider(
          label: 'Peso EAR',
          value: _wEar,
          min: 0,
          max: 1,
          step: 0.01,
          onChanged: (v) => setState(() => _wEar = v),
          onSubmit: () {}, // se aplica con el botón "Aplicar" de arriba
        ),
        const SizedBox(height: 10),
        _slider(
          label: 'Peso MAR',
          value: _wMar,
          min: 0,
          max: 1,
          step: 0.01,
          onChanged: (v) => setState(() => _wMar = v),
          onSubmit: () {},
        ),
        const SizedBox(height: 10),
        _slider(
          label: 'Peso Pose',
          value: _wPose,
          min: 0,
          max: 1,
          step: 0.01,
          onChanged: (v) => setState(() => _wPose = v),
          onSubmit: () {},
        ),
      ],
    );
  }

  Widget _metric(String k, String v, {bool isAlert = false, IconData? icon}) {
    final color = isAlert ? Colors.orangeAccent : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color ?? Colors.grey[600]),
            const SizedBox(width: 8),
          ],
          Text(
            '$k: ',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color ?? Colors.black87,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value.toStringAsFixed(3),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: onSubmit,
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Aplicar'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) / step).round(),
          onChanged: onChanged,
          activeColor: Theme.of(context).primaryColor,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$value',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: onSubmit,
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Aplicar'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: ((max - min) / step).round(),
          onChanged: (v) => onChanged(v.round()),
          activeColor: Theme.of(context).primaryColor,
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
            Row(
              children: [
                Icon(Icons.history, color: theme.primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Historial de Alertas',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      'Aún no hay alertas registradas.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const Divider(height: 20),
              _alertLogTile(entries[i], theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _alertLogTile(_AlertLogEntry entry, ThemeData theme) {
    final color = entry.isAlert ? Colors.redAccent : Colors.green;
    final icon = entry.isAlert
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _formatTime(entry.timestamp),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logsCard() {
    if (_runnerLogs.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        title: const Text('Logs del backend (local)'),
        children: [
          SizedBox(
            height: 180,
            child: ListView.builder(
              reverse: true,
              itemCount: _runnerLogs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: Text(
                  _runnerLogs[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
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
