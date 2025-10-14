import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/events.dart';

const _noToastValue = Object();

class EventsState {
  const EventsState({
    this.microSleeps = const [],
    this.pitchDowns = const [],
    this.yawns = const [],
    this.eyeRubs = const [],
    this.reportWindows = const {},
    this.lastToastAt = const {},
    this.toastEvent,
  });

  final List<MicroSleep> microSleeps;
  final List<PitchDown> pitchDowns;
  final List<YawnEvent> yawns;
  final List<EyeRub> eyeRubs;
  final Map<int, ReportWindow> reportWindows;
  final Map<String, DateTime> lastToastAt;
  final DrowsyEvent? toastEvent;

  EventsState copyWith({
    List<MicroSleep>? microSleeps,
    List<PitchDown>? pitchDowns,
    List<YawnEvent>? yawns,
    List<EyeRub>? eyeRubs,
    Map<int, ReportWindow>? reportWindows,
    Map<String, DateTime>? lastToastAt,
    Object? toastEvent = _noToastValue,
  }) {
    return EventsState(
      microSleeps: microSleeps ?? this.microSleeps,
      pitchDowns: pitchDowns ?? this.pitchDowns,
      yawns: yawns ?? this.yawns,
      eyeRubs: eyeRubs ?? this.eyeRubs,
      reportWindows: reportWindows ?? this.reportWindows,
      lastToastAt: lastToastAt ?? this.lastToastAt,
      toastEvent: toastEvent == _noToastValue ? this.toastEvent : toastEvent as DrowsyEvent?,
    );
  }
}

class EventsNotifier extends StateNotifier<EventsState> {
  EventsNotifier() : super(const EventsState());

  static const _toastThrottle = Duration(seconds: 1);

  void addEvent(DrowsyEvent event) {
    final key = event.runtimeType.toString();
    final now = DateTime.now();
    final lastToast = state.lastToastAt[key];
    final shouldToast = lastToast == null || now.difference(lastToast) > _toastThrottle;
    final toastMap = Map<String, DateTime>.from(state.lastToastAt);
    List<MicroSleep>? microSleeps;
    List<PitchDown>? pitchDowns;
    List<YawnEvent>? yawns;
    List<EyeRub>? eyeRubs;
    Map<int, ReportWindow>? windows;

    if (event is MicroSleep) {
      microSleeps = [event, ...state.microSleeps].take(20).toList();
    } else if (event is PitchDown) {
      pitchDowns = [event, ...state.pitchDowns].take(20).toList();
    } else if (event is YawnEvent) {
      yawns = [event, ...state.yawns].take(20).toList();
    } else if (event is EyeRub) {
      eyeRubs = [event, ...state.eyeRubs].take(20).toList();
    } else if (event is ReportWindow) {
      windows = Map<int, ReportWindow>.from(state.reportWindows);
      windows[event.windowS] = event;
    }

    Object? toastEvent = _noToastValue;
    if (shouldToast && event is! ReportWindow && event is! EyeBlink) {
      toastMap[key] = now;
      toastEvent = event;
    }

    state = state.copyWith(
      microSleeps: microSleeps,
      pitchDowns: pitchDowns,
      yawns: yawns,
      eyeRubs: eyeRubs,
      reportWindows: windows,
      lastToastAt: toastMap,
      toastEvent: toastEvent,
    );
  }

  void clearToast() {
    if (state.toastEvent != null) {
      state = state.copyWith(toastEvent: null);
    }
  }
}

final eventsProvider = StateNotifierProvider<EventsNotifier, EventsState>(
  (ref) => EventsNotifier(),
);
