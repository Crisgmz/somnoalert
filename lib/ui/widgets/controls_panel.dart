import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/config_model.dart';
import '../../models/metrics_payload.dart';
import '../../state/config_provider.dart';

class ControlsPanel extends ConsumerStatefulWidget {
  const ControlsPanel({super.key});

  @override
  ConsumerState<ControlsPanel> createState() => _ControlsPanelState();
}

class _ControlsPanelState extends ConsumerState<ControlsPanel> {
  ConfigModel? _editing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listen<ConfigState>(configProvider, (previous, next) {
        if (next.config != null && previous?.config != next.config) {
          setState(() {
            _editing = next.config!.copy();
          });
        }
        if (next.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al sincronizar configuración: ${next.error}'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      });
    });
  }

  double get _weightsSum {
    final cfg = _editing;
    if (cfg == null) return 0;
    return cfg.wEar + cfg.wMar + cfg.wPose;
  }

  Future<void> _save() async {
    final cfg = _editing;
    if (cfg == null) return;

    final success = await ref.read(configProvider.notifier).save(cfg);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Configuración guardada exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar la configuración'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(configProvider);
    _editing ??= state.config?.copy();
    final cfg = _editing;
    final cameraSnapshot = state.liveSnapshot?.camera;

    if (cfg == null) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F33),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(),
              SizedBox(width: 12),
              Text('Cargando configuración...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final weightsOk = (_weightsSum - 1).abs() <= 0.1;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F33),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Controles',
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          if (cameraSnapshot != null) ...[
            const SizedBox(height: 12),
            _CameraSummary(camera: cameraSnapshot),
          ],
          const SizedBox(height: 16),
          _SliderRow(
            label: 'EAR Threshold',
            value: cfg.earThr,
            min: 0.05,
            max: 0.4,
            onChanged: (value) => setState(() {
              final updated = cfg.copy();
              updated.earThr = value;
              _editing = updated;
            }),
          ),
          _SliderRow(
            label: 'MAR Threshold',
            value: cfg.marThr,
            min: 0.2,
            max: 1.0,
            onChanged: (value) => setState(() {
              final updated = cfg.copy();
              updated.marThr = value;
              _editing = updated;
            }),
          ),
          _SliderRow(
            label: 'Pitch Threshold',
            value: cfg.pitchThr,
            min: 5,
            max: 40,
            onChanged: (value) => setState(() {
              final updated = cfg.copy();
              updated.pitchThr = value;
              _editing = updated;
            }),
            suffix: '°',
          ),
          _SliderRow(
            label: 'Fusión Threshold',
            value: cfg.fusionThr,
            min: 0.1,
            max: 1,
            onChanged: (value) => setState(() {
              final updated = cfg.copy();
              updated.fusionThr = value;
              _editing = updated;
            }),
          ),
          _SliderRow(
            label: 'Frames consecutivos',
            value: cfg.consecFrames.toDouble(),
            min: 10,
            max: 120,
            divisions: 22,
            onChanged: (value) => setState(() {
              final updated = cfg.copy();
              updated.consecFrames = value.round();
              _editing = updated;
            }),
            decimals: 0,
          ),
          const Divider(color: Colors.white12, height: 32),
          Text('Pesos de fusión', style: theme.textTheme.titleSmall?.copyWith(color: Colors.white70)),
          const SizedBox(height: 12),
          _SliderRow(
            label: 'Peso EAR',
            value: cfg.wEar,
            min: 0,
            max: 1,
            onChanged: (value) => setState(() {
              final updated = cfg.copy();
              updated.wEar = value;
              _editing = updated;
            }),
          ),
          _SliderRow(
            label: 'Peso MAR',
            value: cfg.wMar,
            min: 0,
            max: 1,
            onChanged: (value) => setState(() {
              final updated = cfg.copy();
              updated.wMar = value;
              _editing = updated;
            }),
          ),
          _SliderRow(
            label: 'Peso Pose',
            value: cfg.wPose,
            min: 0,
            max: 1,
            onChanged: (value) => setState(() {
              final updated = cfg.copy();
              updated.wPose = value;
              _editing = updated;
            }),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Suma: ${_weightsSum.toStringAsFixed(2)}',
              style: theme.textTheme.bodySmall?.copyWith(color: weightsOk ? Colors.greenAccent : Colors.redAccent),
            ),
          ),
          const Divider(color: Colors.white12, height: 32),
          SwitchListTile.adaptive(
            value: cfg.usePythonAlarm,
            contentPadding: EdgeInsets.zero,
            title: Text('Usar alarma Python', style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white)),
            subtitle: Text(
              'Controla el sonido del backend ante eventos críticos',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
            activeColor: Colors.greenAccent,
            onChanged: (value) => setState(() {
              final updated = cfg.copy();
              updated.usePythonAlarm = value;
              _editing = updated;
            }),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: state.loading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: state.loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                    )
                  : const Icon(Icons.save, color: Colors.white),
              label: Text(
                state.loading ? 'Guardando...' : 'Guardar',
                style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.decimals = 2,
    this.suffix,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final int decimals;
  final String? suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ),
              Text(
                '${value.toStringAsFixed(decimals)}${suffix ?? ''}',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(decimals),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _CameraSummary extends StatelessWidget {
  const _CameraSummary({required this.camera});

  final CameraConfigSnapshot camera;

  String _describeState(String label, CameraStateSnapshot? state) {
    if (state == null) {
      return '$label: --';
    }

    final parts = <String>[];
    if (state.index != null) parts.add('#${state.index}');
    if (state.width != null && state.height != null) {
      parts.add('${state.width}x${state.height}');
    }
    if (state.fps != null) parts.add('${state.fps} fps');
    if (state.codec != null) parts.add(state.codec!);
    if (state.orientation != null && state.orientation != 'none') {
      parts.add('rot ${state.orientation}');
    }
    final description = parts.isEmpty ? '--' : parts.join(' · ');
    return '$label: $description';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = camera.options;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF20263C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estado de cámara',
            style: theme.textTheme.titleSmall?.copyWith(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            _describeState('Activa', camera.active),
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            _describeState('Solicitada', camera.requested),
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
          ),
          if (options.codecs.isNotEmpty || options.resolutions.isNotEmpty || options.fps.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (options.codecs.isNotEmpty)
                  _InfoChip(text: 'Codecs: ${options.codecs.take(3).join(', ')}'),
                if (options.resolutions.isNotEmpty)
                  _InfoChip(
                    text: 'Resoluciones: ${options.resolutions.take(3).map((e) => '${e[0]}x${e[1]}').join(', ')}',
                  ),
                if (options.fps.isNotEmpty)
                  _InfoChip(text: 'FPS: ${options.fps.take(3).join('/')}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
      ),
    );
  }
}
