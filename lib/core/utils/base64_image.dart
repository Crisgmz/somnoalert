import 'dart:convert';
import 'dart:typed_data';

/// Safely decodes a base64 encoded image into [Uint8List].
///
/// Returns `null` when the input is `null` or decoding fails.
Uint8List? decodeBase64Image(String? base64String) {
  if (base64String == null || base64String.isEmpty) {
    return null;
  }

  try {
    return base64Decode(base64String);
  } catch (_) {
    return null;
  }
}
