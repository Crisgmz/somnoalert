// lib/features/drowsy/view/model.dart
import 'dart:convert';
import 'dart:typed_data';

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

      marThreshold: (thr['mar'] as num?)?.toDouble(),
      pitchDegThreshold: (thr['pitch'] as num?)?.toDouble(),
      fusionThreshold: (thr['fusion'] as num?)?.toDouble(),
      wEar: (wts['ear'] as num?)?.toDouble(),
      wMar: (wts['mar'] as num?)?.toDouble(),
      wPose: (wts['pose'] as num?)?.toDouble(),
    );
  }
}
