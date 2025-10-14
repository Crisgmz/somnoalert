abstract class DrowsyEvent {
  final DateTime ts;
  DrowsyEvent(this.ts);
}

class EyeBlink extends DrowsyEvent {
  EyeBlink(super.ts);
}

class MicroSleep extends DrowsyEvent {
  final double duration;
  MicroSleep(super.ts, this.duration);
}

class YawnEvent extends DrowsyEvent {
  final double duration;
  YawnEvent(super.ts, this.duration);
}

class PitchDown extends DrowsyEvent {
  final double duration;
  PitchDown(super.ts, this.duration);
}

class EyeRub extends DrowsyEvent {
  final String hand;
  final double duration;
  EyeRub(super.ts, this.hand, this.duration);
}

class ReportWindow extends DrowsyEvent {
  final int windowS;
  final Map<String, dynamic> counts;
  final Map<String, dynamic> durations;
  ReportWindow(super.ts, this.windowS, this.counts, this.durations);
}
