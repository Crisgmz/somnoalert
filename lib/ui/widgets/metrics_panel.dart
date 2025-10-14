import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/metrics_payload.dart';
import '../../state/metrics_provider.dart';

class MetricsPanel extends ConsumerWidget {
  const MetricsPanel({super.key});

  Color _colorForValue(double? value, double threshold, {bool inverse = false}) {
    if (value == null) return Colors.grey;
    if (inverse) {
      if (value >= threshold) return Colors.redAccent;
      if (value >= threshold * 0.8) return Colors.orangeAccent;
      return Colors.greenAccent;
    }
    if (value <= threshold) return Colors.redAccent;
    if (value <= threshold * 1.2) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(metricsProvider);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F33),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Panel de métricas',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          if (metrics == null)
            Text(
              'Esperando datos del detector...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricTile(
                  label: 'EAR',
                  value: metrics.ear,
                  threshold: (metrics.thresholds['ear'] as num?)?.toDouble() ?? 0.0,
                  color: _colorForValue(metrics.ear, (metrics.thresholds['ear'] as num?)?.toDouble() ?? 0.0),
                ),
                _MetricTile(
                  label: 'MAR',
                  value: metrics.mar,
                  threshold: (metrics.thresholds['mar'] as num?)?.toDouble() ?? 0.0,
                  color: _colorForValue(metrics.mar, (metrics.thresholds['mar'] as num?)?.toDouble() ?? 0.0, inverse: true),
                ),
                _MetricTile(
                  label: 'Pitch',
                  value: metrics.pitch,
                  threshold: (metrics.thresholds['pitch'] as num?)?.toDouble() ?? 0.0,
                  color: _colorForValue(metrics.pitch, (metrics.thresholds['pitch'] as num?)?.toDouble() ?? 0.0, inverse: true),
                  suffix: '°',
                ),
                _MetricTile(
                  label: 'Fused',
                  value: metrics.fusedScore,
                  threshold: (metrics.thresholds['fusion'] as num?)?.toDouble() ?? 0.0,
                  color: _colorForValue(metrics.fusedScore, (metrics.thresholds['fusion'] as num?)?.toDouble() ?? 0.0, inverse: true),
                ),
                _MetricTile(
                  label: 'Frames cerrados',
                  value: metrics.closedFrames.toDouble(),
                  threshold: 0,
                  color: Colors.blueAccent,
                  decimals: 0,
                ),
                _MetricTile(
                  label: 'Yaw',
                  value: metrics.yaw,
                  threshold: 0,
                  color: Colors.blueGrey,
                  suffix: '°',
                ),
                _MetricTile(
                  label: 'Roll',
                  value: metrics.roll,
                  threshold: 0,
                  color: Colors.blueGrey,
                  suffix: '°',
                ),
              ],
            ),
          const SizedBox(height: 12),
          if (metrics != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _WeightsCard(weights: metrics.weights),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ReasonsCard(reasons: metrics.reason),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.threshold,
    required this.color,
    this.decimals = 2,
    this.suffix,
  });

  final String label;
  final double? value;
  final double threshold;
  final Color color;
  final int decimals;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted = value == null ? '--' : value!.toStringAsFixed(decimals);
    final thresholdText = threshold == 0 ? '' : 'Umbral ${threshold.toStringAsFixed(2)}';

    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF20263C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.6), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatted,
                style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.bold),
              ),
              if (suffix != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(suffix!, style: theme.textTheme.labelLarge?.copyWith(color: color)),
                ),
            ],
          ),
          if (thresholdText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                thresholdText,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeightsCard extends StatelessWidget {
  const _WeightsCard({required this.weights});

  final Map<String, dynamic> weights;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF20263C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pesos',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          ...weights.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key.toUpperCase(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
                    ),
                  ),
                  Text(
                    (entry.value as num?)?.toStringAsFixed(2) ?? '--',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonsCard extends StatelessWidget {
  const _ReasonsCard({required this.reasons});

  final List<String> reasons;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF20263C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Razones',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          if (reasons.isEmpty)
            Text(
              'Sin alertas activas',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white38),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: reasons
                  .map(
                    (reason) => Chip(
                      label: Text(reason),
                      backgroundColor: Colors.redAccent.withOpacity(0.15),
                      labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}
