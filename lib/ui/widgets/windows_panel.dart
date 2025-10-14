import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/events.dart';
import '../../state/events_provider.dart';

class WindowsPanel extends ConsumerWidget {
  const WindowsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(eventsProvider);
    final flickersWindow = state.reportWindows[60];
    final yawnsWindow = state.reportWindows[180];
    final eyeRubWindow = state.reportWindows[300];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reportes por ventana',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        _ReportCard(
          color: Colors.purpleAccent,
          title: '60 s · Flickers',
          icon: Icons.visibility,
          description: 'Parpadeos y microsueños recientes',
          count: _extractCount(flickersWindow?.counts['flickers']).toString(),
          secondary: flickersWindow == null
              ? 'Sin datos'
              : 'Microsueños: ${_extractCount(flickersWindow.counts['microsleeps'])}',
        ),
        const SizedBox(height: 12),
        _ReportCard(
          color: Colors.tealAccent,
          title: '180 s · Bostezos',
          icon: Icons.self_improvement,
          description: 'Seguimiento de bostezos prolongados',
          count: _extractCount(yawnsWindow?.counts['yawns'] ?? yawnsWindow?.counts['yawn']).toString(),
          secondary: yawnsWindow == null
              ? 'Sin datos'
              : _formatDurations('Duraciones', yawnsWindow.durations['yawns'] ?? yawnsWindow.durations['yawn']),
        ),
        const SizedBox(height: 12),
        _EyeRubCard(window: eyeRubWindow),
      ],
    );
  }
}

int _extractCount(dynamic value, [String? hand]) {
  if (value is num) return value.toInt();
  if (value is Map) {
    if (hand != null) {
      final handValue = value[hand];
      return _extractCount(handValue);
    }
    return value.values.fold<int>(0, (acc, v) => acc + _extractCount(v));
  }
  if (value is List) {
    return value.length;
  }
  return 0;
}

String _formatDurations(String label, dynamic value) {
  if (value is List) {
    final durations = value.map((e) => (e as num).toDouble()).toList();
    if (durations.isEmpty) return '$label: --';
    final avg = durations.reduce((a, b) => a + b) / durations.length;
    return '$label: ${avg.toStringAsFixed(1)} s prom';
  }
  if (value is Map) {
    final entries = value.entries
        .map((entry) => '${entry.key}: ${_formatDurations(label, entry.value).split(':').last.trim()}')
        .join(' · ');
    return '$label: $entries';
  }
  return '$label: --';
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.color,
    required this.title,
    required this.icon,
    required this.description,
    required this.count,
    required this.secondary,
  });

  final Color color;
  final String title;
  final IconData icon;
  final String description;
  final String count;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2540),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.6), width: 1.2),
        boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  secondary,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            count,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

class _EyeRubCard extends StatelessWidget {
  const _EyeRubCard({required this.window});

  final ReportWindow? window;

  Map<String, int> _countsByHand() {
    final raw = window?.counts['eye_rub'];
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), _extractCount(value)));
    }
    if (raw is num) {
      return {'total': raw.toInt()};
    }
    return const {};
  }

  Map<String, String> _durationsByHand() {
    final raw = window?.durations['eye_rub'];
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), _formatDurations('Duración', value)));
    }
    if (raw is List) {
      return {'total': _formatDurations('Duración', raw)};
    }
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    final counts = _countsByHand();
    final durations = _durationsByHand();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2540),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.6), width: 1.2),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 6))],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.all(12),
                child: const Icon(Icons.pan_tool, color: Colors.blueAccent, size: 32),
              ),
              const SizedBox(width: 16),
              Text(
                '300 s · Eye Rub',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Text(
                _extractCount(window?.counts['eye_rub']).toString(),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.blueAccent, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (window == null)
            Text(
              'Sin datos',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: counts.entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              entry.key.toUpperCase(),
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.blueAccent),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Eventos: ${entry.value}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                            ),
                          ),
                          if (durations.containsKey(entry.key))
                            Text(
                              durations[entry.key]!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                            )
                          else if (durations.containsKey('total'))
                            Text(
                              durations['total']!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}
