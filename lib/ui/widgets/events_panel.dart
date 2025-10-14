import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/events.dart';
import '../../state/events_provider.dart';

class EventsPanel extends ConsumerWidget {
  const EventsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(eventsProvider);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF311B92), Color(0xFF4527A0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Eventos inmediatos',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          _EventList(
            title: 'Micro-sueños',
            icon: Icons.bedtime_rounded,
            color: Colors.redAccent,
            events: state.microSleeps,
            subtitleBuilder: (event) =>
                'Duración: ${event?.duration?.toStringAsFixed(1) ?? "0.0"} s',
          ),
          const SizedBox(height: 12),
          _EventList(
            title: 'Cabeceos',
            icon: Icons.screen_rotation_alt,
            color: Colors.orangeAccent,
            events: state.pitchDowns,
            subtitleBuilder: (event) =>
                'Duración: ${event?.duration?.toStringAsFixed(1) ?? "0.0"} s',
          ),
          const SizedBox(height: 12),
          _EventList(
            title: 'Bostezos',
            icon: Icons.face_retouching_natural,
            color: Colors.deepPurpleAccent,
            events: state.yawns,
            subtitleBuilder: (event) =>
                'Duración: ${event?.duration?.toStringAsFixed(1) ?? "0.0"} s',
          ),
          const SizedBox(height: 12),
          _EyeRubList(events: state.eyeRubs ?? []),
        ],
      ),
    );
  }
}

class _EventList<T extends DrowsyEvent> extends StatelessWidget {
  const _EventList({
    required this.title,
    required this.icon,
    required this.color,
    required this.events,
    required this.subtitleBuilder,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<T> events;
  final String Function(T event) subtitleBuilder;

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ExpansionTile(
        collapsedIconColor: Colors.white70,
        iconColor: Colors.white,
        collapsedBackgroundColor: Colors.black12,
        backgroundColor: Colors.black26,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.only(bottom: 12),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: color,
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
            ),
            Text(
              events.length.toString().padLeft(2, '0'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: Colors.white70),
            ),
          ],
        ),
        children: [
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Sin eventos recientes',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white54),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: events.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: Colors.white12, height: 8, indent: 60),
              itemBuilder: (context, index) {
                final event = events[index];
                return ListTile(
                  dense: true,
                  leading: Icon(icon, color: color),
                  title: Text(
                    subtitleBuilder(event),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Hora: ${_formatTime(event.ts)}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _EyeRubList extends StatelessWidget {
  const _EyeRubList({required this.events});

  final List<EyeRub> events;

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: const Icon(Icons.pan_tool, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                'Frote de ojos',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
              const Spacer(),
              Text(
                events.length.toString().padLeft(2, '0'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            Text(
              'Sin eventos recientes',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white54),
            )
          else
            ...events.map(
              (event) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        event.hand.toUpperCase(),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: Colors.blueAccent),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Duración: ${event.duration.toStringAsFixed(1)} s',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                    Text(
                      _formatTime(event.ts),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white70),
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
