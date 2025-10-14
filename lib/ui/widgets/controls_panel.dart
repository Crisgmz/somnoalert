import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/config_model.dart';
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
