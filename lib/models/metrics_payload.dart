class CameraStateSnapshot {
  const CameraStateSnapshot({
    this.index,
    this.width,
    this.height,
    this.fps,
    this.codec,
    this.orientation,
  });

  final int? index;
  final int? width;
  final int? height;
  final int? fps;
  final String? codec;
  final String? orientation;

  factory CameraStateSnapshot.fromJson(Map<String, dynamic> json) {
    int? _asInt(dynamic value) => (value as num?)?.toInt();

    return CameraStateSnapshot(
      index: _asInt(json['index']),
      width: _asInt(json['width']),
      height: _asInt(json['height']),
      fps: _asInt(json['fps']),
      codec: json['codec'] as String?,
      orientation: json['orientation'] as String?,
    );
  }
}

class CameraOptionsSnapshot {
  const CameraOptionsSnapshot({
    this.codecs = const [],
    this.resolutions = const [],
    this.fps = const [],
  });

  final List<String> codecs;
  final List<List<int>> resolutions;
  final List<int> fps;

  factory CameraOptionsSnapshot.fromJson(Map<String, dynamic> json) {
    List<List<int>> parseResolutions(dynamic value) {
      final result = <List<int>>[];
      if (value is List) {
        for (final item in value) {
          if (item is List && item.length >= 2) {
            final width = (item[0] as num?)?.toInt();
            final height = (item[1] as num?)?.toInt();
            if (width != null && height != null) {
              result.add([width, height]);
            }
          } else if (item is Map<String, dynamic>) {
            final width = (item['width'] as num?)?.toInt();
            final height = (item['height'] as num?)?.toInt();
            if (width != null && height != null) {
              result.add([width, height]);
            }
          }
        }
      }
      return result;
    }

    List<int> parseFps(dynamic value) {
      final result = <int>[];
      if (value is List) {
        for (final item in value) {
          final fps = (item as num?)?.toInt();
          if (fps != null) {
            result.add(fps);
          }
        }
      }
      return result;
    }

    return CameraOptionsSnapshot(
      codecs: (json['codecs'] as List?)?.map((e) => '$e').toList() ?? const [],
      resolutions: parseResolutions(json['resolutions']),
      fps: parseFps(json['fps']),
    );
  }
}

class CameraConfigSnapshot {
  const CameraConfigSnapshot({this.active, this.requested, this.options = const CameraOptionsSnapshot()});

  final CameraStateSnapshot? active;
  final CameraStateSnapshot? requested;
  final CameraOptionsSnapshot options;

  factory CameraConfigSnapshot.fromJson(Map<String, dynamic> json) {
    final active = json['active'];
    final requested = json['requested'];
    final options = json['options'];

    return CameraConfigSnapshot(
      active: active is Map<String, dynamic> ? CameraStateSnapshot.fromJson(active) : null,
      requested: requested is Map<String, dynamic> ? CameraStateSnapshot.fromJson(requested) : null,
      options: options is Map<String, dynamic>
          ? CameraOptionsSnapshot.fromJson(options)
          : const CameraOptionsSnapshot(),
    );
  }
}

class MetricsConfigSnapshot {
  const MetricsConfigSnapshot({this.usePythonAlarm, this.camera});

  final bool? usePythonAlarm;
  final CameraConfigSnapshot? camera;

  factory MetricsConfigSnapshot.fromJson(Map<String, dynamic> json) {
    final camera = json['camera'];

    return MetricsConfigSnapshot(
      usePythonAlarm: json['usePythonAlarm'] as bool?,
      camera: camera is Map<String, dynamic> ? CameraConfigSnapshot.fromJson(camera) : null,
    );
  }
}

class MetricsPayload {
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
    this.consecFrames = 0,
    this.isDrowsy = false,
    this.thresholds = const {},
    this.weights = const {},
    this.configSnapshot,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  final double? ear;
  final double? mar;
  final double? yaw;
  final double? pitch;
  final double? roll;
  final double? fusedScore;
  final int closedFrames;
  final int consecFrames;
  final bool isDrowsy;
  final Map<String, dynamic> thresholds;
  final Map<String, dynamic> weights;
  final String? rawFrameB64;
  final String? processedFrameB64;
  final List<String> reason;
  final MetricsConfigSnapshot? configSnapshot;
  final DateTime receivedAt;

  factory MetricsPayload.fromJson(Map<String, dynamic> json) {
    final config = json['config'];

    return MetricsPayload(
      ear: (json['ear'] as num?)?.toDouble(),
      mar: (json['mar'] as num?)?.toDouble(),
      yaw: (json['yaw'] as num?)?.toDouble(),
      pitch: (json['pitch'] as num?)?.toDouble(),
      roll: (json['roll'] as num?)?.toDouble(),
      fusedScore: (json['fusedScore'] as num?)?.toDouble(),
      closedFrames: (json['closedFrames'] ?? 0) as int,
      consecFrames: (json['consecFrames'] ?? 0) as int,
      isDrowsy: (json['isDrowsy'] ?? false) as bool,
      thresholds: (json['thresholds'] ?? {}) as Map<String, dynamic>,
      weights: (json['weights'] ?? {}) as Map<String, dynamic>,
      rawFrameB64: json['rawFrame'] as String?,
      processedFrameB64: json['processedFrame'] as String?,
      reason: (json['reason'] as List?)?.cast<String>() ?? const [],
      configSnapshot: config is Map<String, dynamic> ? MetricsConfigSnapshot.fromJson(config) : null,
    );
  }

  bool get isStale => DateTime.now().difference(receivedAt) > const Duration(seconds: 5);
}
