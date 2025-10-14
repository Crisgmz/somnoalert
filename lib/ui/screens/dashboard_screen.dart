import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/events.dart';
import '../../state/events_provider.dart';
import '../../state/metrics_provider.dart';
import '../../state/ws_provider.dart';
import '../widgets/controls_panel.dart';
import '../widgets/events_panel.dart';
import '../widgets/live_view.dart';
import '../widgets/metrics_panel.dart';
import '../widgets/windows_panel.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listen<DrowsyEvent?>(eventsProvider.select((state) => state.toastEvent), (prev, next) {
        if (next != null) {
          _showToast(next);
          ref.read(eventsProvider.notifier).clearToast();
        }
      });
    });
  }

  void _showToast(DrowsyEvent event) {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    String title;
    String subtitle;
    Color color;

    if (event is MicroSleep) {
      title = 'Micro-sueño detectado';
      subtitle = 'Duración: ${event.duration.toStringAsFixed(1)} s';
      color = Colors.redAccent;
    } else if (event is PitchDown) {
      title = 'Cabeceo detectado';
      subtitle = 'Duración: ${event.duration.toStringAsFixed(1)} s';
      color = Colors.orangeAccent;
    } else if (event is YawnEvent) {
      title = 'Bostezo detectado';
      subtitle = 'Duración: ${event.duration.toStringAsFixed(1)} s';
      color = Colors.deepPurpleAccent;
    } else if (event is EyeRub) {
      title = 'Frote de ojos';
      subtitle = 'Mano: ${event.hand} · ${event.duration.toStringAsFixed(1)} s';
      color = Colors.blueAccent;
    } else {
      return;
    }

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
            const SizedBox(height: 2),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dashboardSyncProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0C1021),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return _buildVerticalLayout();
            }
            return _buildHorizontalLayout();
          },
        ),
      ),
    );
  }

  Widget _buildHorizontalLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(
          flex: 3,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: LiveView(),
          ),
        ),
        Expanded(
          flex: 2,
          child: Container(
            margin: const EdgeInsets.only(right: 16, top: 16, bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF161B2E),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const _SidePanels(),
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalLayout() {
    return SingleChildScrollView(
      child: Column(
        children: const [
          Padding(
            padding: EdgeInsets.all(16),
            child: LiveView(),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _SidePanels(),
          ),
        ],
      ),
    );
  }
}

class _SidePanels extends StatelessWidget {
  const _SidePanels();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          WindowsPanel(),
          SizedBox(height: 16),
          EventsPanel(),
          SizedBox(height: 16),
          MetricsPanel(),
          SizedBox(height: 16),
          ControlsPanel(),
        ],
      ),
    );
  }
}
