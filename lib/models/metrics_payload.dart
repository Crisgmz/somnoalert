class MetricsPayload {
  final double? ear;
  final double? mar;
  final double? yaw;
  final double? pitch;
  final double? roll;
  final double? fusedScore;
  final int closedFrames;
  final bool isDrowsy;
  final Map<String, dynamic> thresholds;
  final Map<String, dynamic> weights;
  final String? rawFrameB64;
  final String? processedFrameB64;
  final List<String> reason;

  MetricsPayload({
    this.ear,
    this.mar,
    this.yaw,
    this.pitch,
    this.roll,
    this.fusedScore,
    this.rawFrameB64,
    this.processedFrameB64,
    this.reason = const [],
    this.closedFrames = 0,
    this.isDrowsy = false,
    this.thresholds = const {},
    this.weights = const {},
  });

  factory MetricsPayload.fromJson(Map<String, dynamic> json) {
    return MetricsPayload(
      ear: (json['ear'] as num?)?.toDouble(),
      mar: (json['mar'] as num?)?.toDouble(),
      yaw: (json['yaw'] as num?)?.toDouble(),
      pitch: (json['pitch'] as num?)?.toDouble(),
      roll: (json['roll'] as num?)?.toDouble(),
      fusedScore: (json['fusedScore'] as num?)?.toDouble(),
      closedFrames: (json['closedFrames'] ?? 0) as int,
      isDrowsy: (json['isDrowsy'] ?? false) as bool,
      thresholds: (json['thresholds'] ?? {}) as Map<String, dynamic>,
      weights: (json['weights'] ?? {}) as Map<String, dynamic>,
      rawFrameB64: json['rawFrame'] as String?,
      processedFrameB64: json['processedFrame'] as String?,
      reason: (json['reason'] as List?)?.cast<String>() ?? const [],
    );
  }
}
