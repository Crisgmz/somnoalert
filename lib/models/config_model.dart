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
    required this.earThr,
    required this.marThr,
    required this.pitchThr,
    required this.fusionThr,
    required this.consecFrames,
    required this.wEar,
    required this.wMar,
    required this.wPose,
    required this.usePythonAlarm,
  });

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
    return ConfigModel(
      earThr: (json['EAR_THRESHOLD'] as num).toDouble(),
      marThr: (json['MAR_THRESHOLD'] as num).toDouble(),
      pitchThr: (json['PITCH_DEG_THRESHOLD'] as num).toDouble(),
      fusionThr: (json['FUSION_THRESHOLD'] as num).toDouble(),
      consecFrames: (json['CONSEC_FRAMES'] as num).toInt(),
      wEar: (json['W_EAR'] as num).toDouble(),
      wMar: (json['W_MAR'] as num).toDouble(),
      wPose: (json['W_POSE'] as num).toDouble(),
      usePythonAlarm: (json['USE_PYTHON_ALARM'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'EAR_THRESHOLD': earThr,
      'MAR_THRESHOLD': marThr,
      'PITCH_DEG_THRESHOLD': pitchThr,
      'CONSEC_FRAMES': consecFrames,
      'W_EAR': wEar,
      'W_MAR': wMar,
      'W_POSE': wPose,
      'FUSION_THRESHOLD': fusionThr,
      'USE_PYTHON_ALARM': usePythonAlarm,
    };
  }

  ConfigModel copy() => ConfigModel(
        earThr: earThr,
        marThr: marThr,
        pitchThr: pitchThr,
        fusionThr: fusionThr,
        consecFrames: consecFrames,
        wEar: wEar,
        wMar: wMar,
        wPose: wPose,
        usePythonAlarm: usePythonAlarm,
      );
}
