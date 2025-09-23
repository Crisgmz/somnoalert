class DrowsyMetrics {
  final double? ear;
  final int closedFrames;
  final double threshold;
  final int consecFrames;
  final bool isDrowsy;

  DrowsyMetrics({
    required this.ear,
    required this.closedFrames,
    required this.threshold,
    required this.consecFrames,
    required this.isDrowsy,
  });

  factory DrowsyMetrics.fromMap(Map<String, dynamic> m) {
    return DrowsyMetrics(
      ear: (m['ear'] as num?)?.toDouble(),
      closedFrames: (m['closed_frames'] as num?)?.toInt() ?? 0,
      threshold: (m['threshold'] as num?)?.toDouble() ?? 0.2,
      consecFrames: (m['consec_frames'] as num?)?.toInt() ?? 50,
      isDrowsy: (m['is_drowsy'] as bool?) ?? false,
    );
  }
}
