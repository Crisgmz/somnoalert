class ThresholdTierConfig {
  const ThresholdTierConfig({
    required this.ear,
    required this.mar,
    required this.pitch,
    required this.fusion,
    required this.consecFrames,
  });

  final double ear;
  final double mar;
  final double pitch;
  final double fusion;
  final int consecFrames;

  ThresholdTierConfig copyWith({
    double? ear,
    double? mar,
    double? pitch,
    double? fusion,
    int? consecFrames,
  }) {
    return ThresholdTierConfig(
      ear: ear ?? this.ear,
      mar: mar ?? this.mar,
      pitch: pitch ?? this.pitch,
      fusion: fusion ?? this.fusion,
      consecFrames: consecFrames ?? this.consecFrames,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ear': ear,
      'mar': mar,
      'pitch': pitch,
      'fusion': fusion,
      'consecFrames': consecFrames,
    };
  }

  factory ThresholdTierConfig.fromJson(Map<String, dynamic> json, {ThresholdTierConfig? fallback}) {
    double _double(dynamic value, double orElse) => (value as num?)?.toDouble() ?? orElse;
    int _int(dynamic value, int orElse) => (value as num?)?.toInt() ?? orElse;

    return ThresholdTierConfig(
      ear: _double(json['ear'], fallback?.ear ?? 0.18),
      mar: _double(json['mar'], fallback?.mar ?? 0.6),
      pitch: _double(json['pitch'], fallback?.pitch ?? 20),
      fusion: _double(json['fusion'], fallback?.fusion ?? 0.7),
      consecFrames: _int(json['consecFrames'], fallback?.consecFrames ?? 50),
    );
  }
}

class ThresholdsConfig {
  ThresholdsConfig({
    Map<String, ThresholdTierConfig>? tiers,
    List<String>? order,
  })  : tiers = Map.unmodifiable(tiers ?? const {}),
        order = List.unmodifiable(order ?? const ['normal', 'signs', 'drowsy']);

  final Map<String, ThresholdTierConfig> tiers;
  final List<String> order;

  static const defaultOrder = ['normal', 'signs', 'drowsy'];

  ThresholdTierConfig tier(String key) {
    return tiers[key] ?? const ThresholdTierConfig(ear: 0.18, mar: 0.6, pitch: 20, fusion: 0.7, consecFrames: 50);
  }

  ThresholdsConfig copyWithTier(String key, ThresholdTierConfig config) {
    final next = Map<String, ThresholdTierConfig>.from(tiers);
    next[key] = config;
    return ThresholdsConfig(tiers: next, order: order);
  }

  ThresholdsConfig clone() {
    return ThresholdsConfig(
      tiers: {for (final entry in tiers.entries) entry.key: entry.value.copyWith()},
      order: order,
    );
  }

  Map<String, dynamic> toJson() {
    return {for (final entry in tiers.entries) entry.key: entry.value.toJson()};
  }

  factory ThresholdsConfig.fromJson(dynamic json, {ThresholdsConfig? fallback}) {
    if (json is ThresholdsConfig) {
      return json;
    }

    Map<String, dynamic>? map;
    List<String> order = defaultOrder;

    if (json is Map<String, dynamic>) {
      if (json['tiers'] is Map<String, dynamic>) {
        map = (json['tiers'] as Map<String, dynamic>);
      } else {
        map = json;
      }

      if (json['order'] is List) {
        order = (json['order'] as List).map((e) => '$e').toList();
      } else if (json['thresholdOrder'] is List) {
        order = (json['thresholdOrder'] as List).map((e) => '$e').toList();
      }
    }

    map ??= fallback?.toJson();

    final tiers = <String, ThresholdTierConfig>{};
    if (map != null) {
      for (final entry in map.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          tiers[entry.key] = ThresholdTierConfig.fromJson(value, fallback: fallback?.tiers[entry.key]);
        }
      }
    }

    if (tiers.isEmpty && fallback != null) {
      return fallback;
    }

    return ThresholdsConfig(tiers: tiers, order: order);
  }

  static ThresholdsConfig defaults({
    double baseEar = 0.18,
    double baseMar = 0.6,
    double basePitch = 20,
    int baseConsec = 50,
    double baseFusion = 0.7,
  }) {
    final signs = ThresholdTierConfig(
      ear: baseEar + 0.03,
      mar: (baseMar - 0.05).clamp(0.2, 2.0).toDouble(),
      pitch: (basePitch - 5).clamp(1, 90).toDouble(),
      fusion: (baseFusion - 0.1).clamp(0.05, 1.0).toDouble(),
      consecFrames: (baseConsec - 10).clamp(1, 999).toInt(),
    );
    final normal = ThresholdTierConfig(
      ear: signs.ear + 0.03,
      mar: (signs.mar - 0.05).clamp(0.2, 2.0).toDouble(),
      pitch: (signs.pitch - 5).clamp(1, 90).toDouble(),
      fusion: (signs.fusion - 0.1).clamp(0.05, 1.0).toDouble(),
      consecFrames: (signs.consecFrames - 10).clamp(1, 999).toInt(),
    );
    final drowsy = ThresholdTierConfig(
      ear: baseEar,
      mar: baseMar,
      pitch: basePitch,
      fusion: baseFusion,
      consecFrames: baseConsec,
    );

    return ThresholdsConfig(
      tiers: {
        'normal': normal,
        'signs': signs,
        'drowsy': drowsy,
      },
      order: defaultOrder,
    );
  }
}
