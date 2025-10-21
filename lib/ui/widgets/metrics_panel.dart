import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/metrics_payload.dart';
import '../../models/thresholds.dart';
import '../../state/metrics_provider.dart';

class MetricsPanel extends ConsumerWidget {
  const MetricsPanel({super.key});

  Color _colorForValue(
    double? value,
    double threshold, {
    bool inverse = false,
  }) {
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
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white54),
            )
          else ...[
            _StageSummary(metrics: metrics),
            const SizedBox(height: 16),
            Builder(
              builder: (context) {
                final drowsy = metrics.thresholds.tier('drowsy');
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricTile(
                      label: 'EAR',
                      value: metrics.ear,
                      threshold: drowsy.ear,
                      color: _colorForValue(metrics.ear, drowsy.ear),
                    ),
                    _MetricTile(
                      label: 'MAR',
                      value: metrics.mar,
                      threshold: drowsy.mar,
                      color: _colorForValue(
                        metrics.mar,
                        drowsy.mar,
                        inverse: true,
                      ),
                    ),
                    _MetricTile(
                      label: 'Pitch',
                      value: metrics.pitch,
                      threshold: drowsy.pitch,
                      color: _colorForValue(
                        metrics.pitch,
                        drowsy.pitch,
                        inverse: true,
                      ),
                      suffix: '°',
                    ),
                    _MetricTile(
                      label: 'Fusión',
                      value: metrics.fusedScore,
                      threshold: drowsy.fusion,
                      color: _colorForValue(
                        metrics.fusedScore,
                        drowsy.fusion,
                        inverse: true,
                      ),
                    ),
                    _MetricTile(
                      label: 'Frames cerrados',
                      value: metrics.closedFrames.toDouble(),
                      threshold: drowsy.consecFrames.toDouble(),
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
                );
              },
            ),
            const SizedBox(height: 16),
            _ThresholdsCard(thresholds: metrics.thresholds),
          ],
          const SizedBox(height: 12),
          if (metrics != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _WeightsCard(weights: metrics.weights)),
                const SizedBox(width: 12),
                Expanded(
                  child: _ReasonsCard(
                    reasons: metrics.stageReasons.isNotEmpty
                        ? metrics.stageReasons
                        : metrics.reason,
                  ),
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
    final thresholdText = threshold == 0
        ? ''
        : 'Umbral ${threshold.toStringAsFixed(2)}';

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
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (suffix != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(
                    suffix!,
                    style: theme.textTheme.labelLarge?.copyWith(color: color),
                  ),
                ),
            ],
          ),
          if (thresholdText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                thresholdText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white38,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StageSummary extends StatelessWidget {
  const _StageSummary({required this.metrics});

  final MetricsPayload metrics;

  String get _stage =>
      metrics.drowsinessLevel ?? (metrics.isDrowsy ? 'drowsy' : 'normal');

  Color get _color {
    switch (_stage) {
      case 'drowsy':
        return Colors.redAccent;
      case 'signs':
        return Colors.orangeAccent;
      default:
        return Colors.greenAccent;
    }
  }

  IconData get _icon {
    switch (_stage) {
      case 'drowsy':
        return Icons.warning_amber_rounded;
      case 'signs':
        return Icons.visibility_rounded;
      default:
        return Icons.check_circle_outline;
    }
  }

  String get _label {
    switch (_stage) {
      case 'drowsy':
        return 'Somnolencia detectada';
      case 'signs':
        return 'Signos de somnolencia';
      default:
        return 'Estado normal';
    }
  }

  List<String> get _reasons =>
      metrics.stageReasons.isNotEmpty ? metrics.stageReasons : metrics.reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF20263C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withOpacity(0.4), width: 1.2),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: _color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: _color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (metrics.fusedScore != null)
                Text(
                  'Fusión ${metrics.fusedScore!.toStringAsFixed(2)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
            ],
          ),
          if (_reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _reasons
                  .map(
                    (reason) => Chip(
                      backgroundColor: Colors.white12,
                      labelStyle: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                      label: Text(reason),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThresholdsCard extends StatelessWidget {
  const _ThresholdsCard({required this.thresholds});

  final ThresholdsConfig thresholds;

  String _labelFor(String key) {
    switch (key) {
      case 'signs':
        return 'Signos de somnolencia';
      case 'drowsy':
        return 'Somnolencia';
      default:
        return 'Normal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
            'Umbrales por nivel',
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          for (final tierKey in thresholds.order) ...[
            _ThresholdTierRow(
              label: _labelFor(tierKey),
              tier: thresholds.tier(tierKey),
            ),
            if (tierKey != thresholds.order.last)
              const Divider(color: Colors.white10, height: 20),
          ],
        ],
      ),
    );
  }
}

class _ThresholdTierRow extends StatelessWidget {
  const _ThresholdTierRow({required this.label, required this.tier});

  final String label;
  final ThresholdTierConfig tier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _ThresholdChip(label: 'EAR ≤', value: tier.ear.toStringAsFixed(2)),
            _ThresholdChip(label: 'MAR ≥', value: tier.mar.toStringAsFixed(2)),
            _ThresholdChip(
              label: '|Pitch| ≥',
              value: '${tier.pitch.toStringAsFixed(1)}°',
            ),
            _ThresholdChip(
              label: 'Fusión ≥',
              value: tier.fusion.toStringAsFixed(2),
            ),
            _ThresholdChip(label: 'Frames ≥', value: '${tier.consecFrames}'),
          ],
        ),
      ],
    );
  }
}

class _ThresholdChip extends StatelessWidget {
  const _ThresholdChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2134),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.white70),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
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
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: Colors.white70),
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
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white54),
                    ),
                  ),
                  Text(
                    (entry.value as num?)?.toStringAsFixed(2) ?? '--',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white),
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
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          if (reasons.isEmpty)
            Text(
              'Sin alertas activas',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white38),
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
                      labelStyle: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}
