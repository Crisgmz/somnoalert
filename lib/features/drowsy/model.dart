// lib/features/drowsy/view/model.dart
import 'dart:convert';
import 'dart:typed_data';

class VideoConfigSnapshot {
  final int? activeIndex;
  final int? activeWidth;
  final int? activeHeight;
  final int? activeFps;
  final String? activeCodec;
  final String? activeOrientation;
  final int? requestedIndex;
  final int? requestedWidth;
  final int? requestedHeight;
  final int? requestedFps;
  final String? requestedCodec;
  final String? requestedOrientation;
  final List<String> codecOptions;
  final List<List<int>> resolutionOptions;
  final List<int> fpsOptions;

  const VideoConfigSnapshot({
    this.activeIndex,
    this.activeWidth,
    this.activeHeight,
    this.activeFps,
    this.activeCodec,
    this.activeOrientation,
    this.requestedIndex,
    this.requestedWidth,
    this.requestedHeight,
    this.requestedFps,
    this.requestedCodec,
    this.requestedOrientation,
    this.codecOptions = const [],
    this.resolutionOptions = const [],
    this.fpsOptions = const [],
  });

  factory VideoConfigSnapshot.fromJson(Map<String, dynamic> json) {
    final active = (json['active'] as Map<String, dynamic>?) ?? const {};
    final requested = (json['requested'] as Map<String, dynamic>?) ?? const {};
    final options = (json['options'] as Map<String, dynamic>?) ?? const {};

    List<List<int>> parseResolutions(dynamic value) {
      final list = <List<int>>[];
      if (value is List) {
        for (final item in value) {
          if (item is List && item.length >= 2) {
            final width = (item[0] as num?)?.toInt();
            final height = (item[1] as num?)?.toInt();
            if (width != null && height != null) {
              list.add([width, height]);
            }
          } else if (item is Map<String, dynamic>) {
            final width = (item['width'] as num?)?.toInt();
            final height = (item['height'] as num?)?.toInt();
            if (width != null && height != null) {
              list.add([width, height]);
            }
          }
        }
      }
      return list;
    }

    List<int> parseFps(dynamic value) {
      final list = <int>[];
      if (value is List) {
        for (final item in value) {
          final fps = (item as num?)?.toInt();
          if (fps != null) list.add(fps);
        }
      }
      return list;
    }

    return VideoConfigSnapshot(
      activeIndex: (active['index'] as num?)?.toInt(),
      activeWidth: (active['width'] as num?)?.toInt(),
      activeHeight: (active['height'] as num?)?.toInt(),
      activeFps: (active['fps'] as num?)?.toInt(),
      activeCodec: active['codec'] as String?,
      activeOrientation: active['orientation'] as String?,
      requestedIndex: (requested['index'] as num?)?.toInt(),
      requestedWidth: (requested['width'] as num?)?.toInt(),
      requestedHeight: (requested['height'] as num?)?.toInt(),
      requestedFps: (requested['fps'] as num?)?.toInt(),
      requestedCodec: requested['codec'] as String?,
      requestedOrientation: requested['orientation'] as String?,
      codecOptions: (options['codecs'] as List?)?.map((e) => '$e').toList() ?? const [],
      resolutionOptions: parseResolutions(options['resolutions']),
      fpsOptions: parseFps(options['fps']),
    );
  }
}

class DrowsyMetrics {
  final double? ear;
  final double? mar; // NEW
  final double? yaw; // NEW
  final double? pitch; // NEW
  final double? roll; // NEW
  final double? fusedScore; // NEW
  final List<String> reason; // NEW

  final int closedFrames;
  final double threshold; // EAR threshold (compat)
  final int consecFrames;
  final bool isDrowsy;
  final Uint8List? rawFrame;
  final Uint8List? processedFrame;
  final bool? backendAlarmEnabled;
  final VideoConfigSnapshot? videoConfig;

  // Umbrales/Pesos desde backend (opcionales)
  final double? marThreshold; // NEW
  final double? pitchDegThreshold; // NEW
  final double? fusionThreshold; // NEW
  final double? wEar; // NEW
  final double? wMar; // NEW
  final double? wPose; // NEW

  DrowsyMetrics({
    required this.ear,
    required this.mar,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.fusedScore,
    required this.reason,
    required this.closedFrames,
    required this.threshold,
    required this.consecFrames,
    required this.isDrowsy,
    required this.rawFrame,
    required this.processedFrame,
    required this.backendAlarmEnabled,
    required this.videoConfig,
    required this.marThreshold,
    required this.pitchDegThreshold,
    required this.fusionThreshold,
    required this.wEar,
    required this.wMar,
    required this.wPose,
  });

  factory DrowsyMetrics.fromMap(Map<String, dynamic> m) {
    Uint8List? decode(dynamic v) {
      if (v == null) return null;
      if (v is Uint8List) return v;
      if (v is String && v.isNotEmpty) {
        try {
          return base64Decode(v);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    final thr = (m['thresholds'] is Map) ? (m['thresholds'] as Map) : const {};
    final wts = (m['weights'] is Map) ? (m['weights'] as Map) : const {};
    final cfg = (m['config'] is Map<String, dynamic>)
        ? m['config'] as Map<String, dynamic>
        : <String, dynamic>{};
    final cameraCfg = (cfg['camera'] is Map<String, dynamic>)
        ? VideoConfigSnapshot.fromJson(cfg['camera'] as Map<String, dynamic>)
        : null;

    return DrowsyMetrics(
      ear: (m['ear'] as num?)?.toDouble(),
      mar: (m['mar'] as num?)?.toDouble(),
      yaw: (m['yaw'] as num?)?.toDouble(),
      pitch: (m['pitch'] as num?)?.toDouble(),
      roll: (m['roll'] as num?)?.toDouble(),
      fusedScore: (m['fusedScore'] as num?)?.toDouble(),
      reason: (m['reason'] as List?)?.map((e) => '$e').toList() ?? const [],

      closedFrames: (m['closedFrames'] as num?)?.toInt() ?? 0,
      threshold: (m['threshold'] as num?)?.toDouble() ?? 0.20, // compat
      consecFrames: (m['consecFrames'] as num?)?.toInt() ?? 50,
      isDrowsy: m['isDrowsy'] == true,
      rawFrame: decode(m['rawFrame']),
      processedFrame: decode(m['processedFrame']),
      backendAlarmEnabled: cfg['usePythonAlarm'] as bool?,
      videoConfig: cameraCfg,

      marThreshold: (thr['mar'] as num?)?.toDouble(),
      pitchDegThreshold: (thr['pitch'] as num?)?.toDouble(),
      fusionThreshold: (thr['fusion'] as num?)?.toDouble(),
      wEar: (wts['ear'] as num?)?.toDouble(),
      wMar: (wts['mar'] as num?)?.toDouble(),
      wPose: (wts['pose'] as num?)?.toDouble(),
    );
  }
}
