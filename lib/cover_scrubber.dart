class CoverScrubSpeedController {
  static const _multipliers = [0, 1, 3, 5, 10, 20, 50];
  static const _thresholds = [7.0, 55.0, 90.0, 120.0, 160.0, 200.0];
  static const _stepInterval = Duration(milliseconds: 90);
  static const _distancePerStep = 22.0;
  static const _velocityScale = .06;

  Duration? _lastSampleTime;
  Duration? _lastStepTime;
  double _distance = 0;

  int? update({required double delta, required Duration timestamp}) {
    _distance += delta;
    final previousSample = _lastSampleTime;
    _lastSampleTime = timestamp;

    final elapsedMicros = previousSample == null
        ? 0
        : (timestamp - previousSample).inMicroseconds;
    final pixelsPerSecond = elapsedMicros <= 0
        ? 0.0
        : delta / elapsedMicros * Duration.microsecondsPerSecond;
    final speedSignal = pixelsPerSecond.abs() * _velocityScale;
    final speedSteps = _stepMultiplier(speedSignal);
    final distanceSteps = (_distance.abs() / _distancePerStep).floor();
    final usesSpeed = speedSteps > distanceSteps;
    final steps = usesSpeed ? speedSteps : distanceSteps;
    if (steps == 0) return null;

    final previousStep = _lastStepTime;
    if (previousStep != null && timestamp - previousStep < _stepInterval) {
      return null;
    }

    final directionSignal = usesSpeed ? pixelsPerSecond : _distance;
    if (directionSignal == 0) return null;
    _lastStepTime = timestamp;
    _distance = 0;
    return directionSignal > 0 ? steps : -steps;
  }

  void reset() {
    _lastSampleTime = null;
    _lastStepTime = null;
    _distance = 0;
  }

  static int _stepMultiplier(double signal) {
    for (var index = 0; index < _thresholds.length; index++) {
      if (signal < _thresholds[index]) return _multipliers[index];
    }
    return _multipliers.last;
  }
}
