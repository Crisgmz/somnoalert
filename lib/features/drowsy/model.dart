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
    return DrowsyMetrics(
      ear: (m['ear'] as num?)?.toDouble(),
      closedFrames: (m['closed_frames'] as num?)?.toInt() ?? 0,
      threshold: (m['threshold'] as num?)?.toDouble() ?? 0.2,
      consecFrames: (m['consec_frames'] as num?)?.toInt() ?? 50,
      isDrowsy: (m['is_drowsy'] as bool?) ?? false,
      rawFrame: _decodeFrame(
        m['frame'] ?? m['raw_frame'] ?? m['camera_frame'] ?? m['original_frame'],
      ),
      processedFrame: _decodeFrame(
        m['processed_frame'] ?? m['annotated_frame'] ?? m['debug_frame'],
      ),
    );
  }

  static Uint8List? _decodeFrame(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Uint8List) {
      return value;
    }
    if (value is List<int>) {
      return Uint8List.fromList(value);
    }
    if (value is String && value.isNotEmpty) {
      final sanitized = value.contains(',') ? value.split(',').last : value;
      try {
        return Uint8List.fromList(base64Decode(sanitized));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
