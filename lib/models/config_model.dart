import 'thresholds.dart';

class ConfigModel {
  static const double defaultEarThreshold = 0.18;
  static const double defaultMarThreshold = 0.6;
  static const double defaultPitchThreshold = 20;
  static const double defaultFusionThreshold = 0.7;
  static const int defaultConsecFrames = 50;
  static const double defaultWeightEar = 0.5;
  static const double defaultWeightMar = 0.3;
  static const double defaultWeightPose = 0.2;
  static const bool defaultUsePythonAlarm = false;

  double earThr;
  double marThr;
  double pitchThr;
  double fusionThr;
  int consecFrames;
  double wEar;
  double wMar;
  double wPose;
  bool usePythonAlarm;

  ConfigModel({
    ThresholdsConfig? thresholds,
    required this.wEar,
    required this.wMar,
    required this.wPose,
    required this.usePythonAlarm,
  }) : thresholds = thresholds ?? ThresholdsConfig.defaults(
          baseEar: defaultEarThreshold,
          baseMar: defaultMarThreshold,
          basePitch: defaultPitchThreshold,
          baseConsec: defaultConsecFrames,
          baseFusion: defaultFusionThreshold,
        );

  ThresholdsConfig thresholds;
  double wEar;
  double wMar;
  double wPose;
  bool usePythonAlarm;

  double get earThr => thresholds.tier('drowsy').ear;
  set earThr(double value) {
    final tier = thresholds.tier('drowsy').copyWith(ear: value);
    thresholds = thresholds.copyWithTier('drowsy', tier);
  }

  double get marThr => thresholds.tier('drowsy').mar;
  set marThr(double value) {
    final tier = thresholds.tier('drowsy').copyWith(mar: value);
    thresholds = thresholds.copyWithTier('drowsy', tier);
  }

  double get pitchThr => thresholds.tier('drowsy').pitch;
  set pitchThr(double value) {
    final tier = thresholds.tier('drowsy').copyWith(pitch: value);
    thresholds = thresholds.copyWithTier('drowsy', tier);
  }

  double get fusionThr => thresholds.tier('drowsy').fusion;
  set fusionThr(double value) {
    final tier = thresholds.tier('drowsy').copyWith(fusion: value);
    thresholds = thresholds.copyWithTier('drowsy', tier);
  }

  int get consecFrames => thresholds.tier('drowsy').consecFrames;
  set consecFrames(int value) {
    final tier = thresholds.tier('drowsy').copyWith(consecFrames: value);
    thresholds = thresholds.copyWithTier('drowsy', tier);
  }

  ThresholdTierConfig tier(String key) => thresholds.tier(key);

  void updateTier(String key, ThresholdTierConfig config) {
    thresholds = thresholds.copyWithTier(key, config);
  }

  factory ConfigModel.defaults() => ConfigModel(
        wEar: defaultWeightEar,
        wMar: defaultWeightMar,
        wPose: defaultWeightPose,
        usePythonAlarm: defaultUsePythonAlarm,
      );

  factory ConfigModel.defaults() => ConfigModel(
        earThr: defaultEarThreshold,
        marThr: defaultMarThreshold,
        pitchThr: defaultPitchThreshold,
        fusionThr: defaultFusionThreshold,
        consecFrames: defaultConsecFrames,
        wEar: defaultWeightEar,
        wMar: defaultWeightMar,
        wPose: defaultWeightPose,
        usePythonAlarm: defaultUsePythonAlarm,
      );

  factory ConfigModel.fromJson(Map<String, dynamic> json) {
    final baseEar = (json['EAR_THRESHOLD'] as num?)?.toDouble() ?? defaultEarThreshold;
    final baseMar = (json['MAR_THRESHOLD'] as num?)?.toDouble() ?? defaultMarThreshold;
    final basePitch = (json['PITCH_DEG_THRESHOLD'] as num?)?.toDouble() ?? defaultPitchThreshold;
    final baseFusion = (json['FUSION_THRESHOLD'] as num?)?.toDouble() ?? defaultFusionThreshold;
    final baseConsec = (json['CONSEC_FRAMES'] as num?)?.toInt() ?? defaultConsecFrames;

    final fallback = ThresholdsConfig.defaults(
      baseEar: baseEar,
      baseMar: baseMar,
      basePitch: basePitch,
      baseConsec: baseConsec,
      baseFusion: baseFusion,
    );

    ThresholdsConfig thresholds;
    final thresholdsPayload = json['thresholds'];
    if (thresholdsPayload is Map<String, dynamic>) {
      final merged = Map<String, dynamic>.from(thresholdsPayload);
      if (json['thresholdOrder'] is List && merged['thresholdOrder'] == null) {
        merged['thresholdOrder'] = json['thresholdOrder'];
      }
      thresholds = ThresholdsConfig.fromJson(merged, fallback: fallback);
    } else {
      thresholds = fallback;
    }

    return ConfigModel(
      thresholds: thresholds,
      wEar: (json['W_EAR'] as num?)?.toDouble() ?? defaultWeightEar,
      wMar: (json['W_MAR'] as num?)?.toDouble() ?? defaultWeightMar,
      wPose: (json['W_POSE'] as num?)?.toDouble() ?? defaultWeightPose,
      usePythonAlarm: (json['USE_PYTHON_ALARM'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    final drowsy = thresholds.tier('drowsy');
    return {
      'EAR_THRESHOLD': drowsy.ear,
      'MAR_THRESHOLD': drowsy.mar,
      'PITCH_DEG_THRESHOLD': drowsy.pitch,
      'CONSEC_FRAMES': drowsy.consecFrames,
      'W_EAR': wEar,
      'W_MAR': wMar,
      'W_POSE': wPose,
      'FUSION_THRESHOLD': drowsy.fusion,
      'USE_PYTHON_ALARM': usePythonAlarm,
      'thresholds': thresholds.toJson(),
      'thresholdOrder': thresholds.order,
    };
  }

  ConfigModel copy() => ConfigModel(
        thresholds: thresholds.clone(),
        wEar: wEar,
        wMar: wMar,
        wPose: wPose,
        usePythonAlarm: usePythonAlarm,
      );
}
