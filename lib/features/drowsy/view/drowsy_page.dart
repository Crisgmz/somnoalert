import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../state/drowsy_controller.dart';

class DrowsyPage extends ConsumerStatefulWidget {
  const DrowsyPage({super.key});

  @override
  ConsumerState<DrowsyPage> createState() => _DrowsyPageState();
}

class _DrowsyPageState extends ConsumerState<DrowsyPage> {
  final _backendCtrl = TextEditingController(text: "http://127.0.0.1:8000");
  double _threshold = 0.20;
  double _frames = 50;
  bool _localAlarm = true;

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
    final state = ref.watch(drowsyControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Drowsiness Monitor"),
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
            // Backend URL
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _backendCtrl,
                    decoration: const InputDecoration(
                      labelText: "Backend URL (http://IP:8000)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    ref.read(drowsyControllerProvider.notifier).setBackendBase(_backendCtrl.text.trim());
                  },
                  child: const Text("Conectar"),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Métricas en vivo
            state.when(
              data: (m) {
                final ear = m?.ear?.toStringAsFixed(3) ?? "--";
                final frames = m?.closedFrames ?? 0;
                final isDrowsy = m?.isDrowsy ?? false;
                final thr = m?.threshold ?? _threshold;
                final cf = m?.consecFrames ?? _frames.toInt();

                _threshold = thr;
                _frames = cf.toDouble();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _metric("EAR", ear, isAlert: false),
                    _metric("Closed Frames", "$frames", isAlert: frames > 0),
                    _badge(isDrowsy ? "ALERTA: Despierta!" : "OK", alert: isDrowsy),
                    const SizedBox(height: 16),
                    // Sliders
                    _slider(
                      label: "EAR Threshold",
                      value: _threshold,
                      min: 0.05, max: 0.5, step: 0.005,
                      onChanged: (v) => setState(() => _threshold = v),
                      onSubmit: () => ref.read(drowsyControllerProvider.notifier)
                        .setConfig(earThreshold: _threshold),
                    ),
                    _sliderInt(
                      label: "Consecutive Frames",
                      value: _frames.toInt(),
                      min: 5, max: 120, step: 1,
                      onChanged: (v) => setState(() => _frames = v.toDouble()),
                      onSubmit: () => ref.read(drowsyControllerProvider.notifier)
                        .setConfig(consecFrames: _frames.toInt()),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text("Error: $e"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String k, String v, {bool isAlert = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text("$k: ", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          Text(
            v,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isAlert ? Colors.orange : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, {bool alert = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: alert ? Colors.red[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: alert ? Colors.red : Colors.green, width: 1.4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: alert ? Colors.red[800] : Colors.green[800],
          fontWeight: FontWeight.bold,
        ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(value.toStringAsFixed(3)),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: onSubmit, child: const Text("Aplicar")),
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
        ),
      ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text("$value"),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: onSubmit, child: const Text("Aplicar")),
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
        ),
      ),
    );
  }
}
