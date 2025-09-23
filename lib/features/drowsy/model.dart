// lib/features/drowsy/view/model.dart
import 'dart:convert';
import 'dart:typed_data';

class DrowsyMetrics {
  final double? ear;
  final int closedFrames;
  final double threshold;
  final int consecFrames;
  final bool isDrowsy;
  final Uint8List? rawFrame;
  final Uint8List? processedFrame;

  DrowsyMetrics({
    required this.ear,
    required this.closedFrames,
    required this.threshold,
    required this.consecFrames,
    required this.isDrowsy,
    required this.rawFrame,
    required this.processedFrame,
  });

  factory DrowsyMetrics.fromMap(Map<String, dynamic> m) {
    Uint8List? _decode(dynamic v) {
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

    return DrowsyMetrics(
      ear: (m['ear'] as num?)?.toDouble(),
      closedFrames: (m['closedFrames'] as num?)?.toInt() ?? 0,
      threshold: (m['threshold'] as num?)?.toDouble() ?? 0.20,
      consecFrames: (m['consecFrames'] as num?)?.toInt() ?? 50,
      isDrowsy: m['isDrowsy'] == true,
      rawFrame: _decode(m['rawFrame']),
      processedFrame: _decode(m['processedFrame']),
    );
  }
}
