import 'dart:async';

import 'package:flutter/services.dart';

class CoverFeedbackSettings {
  const CoverFeedbackSettings({
    required this.hapticStrength,
    required this.soundStrength,
  });

  static const defaults = CoverFeedbackSettings(
    hapticStrength: .7,
    soundStrength: .7,
  );

  final double hapticStrength;
  final double soundStrength;

  CoverFeedbackSettings copyWith({
    double? hapticStrength,
    double? soundStrength,
  }) => CoverFeedbackSettings(
    hapticStrength: hapticStrength ?? this.hapticStrength,
    soundStrength: soundStrength ?? this.soundStrength,
  );
}

class CoverFeedback {
  static const _channel = MethodChannel('com.r19988088.wyyyy/cover_feedback');
  static CoverFeedbackSettings _settings = CoverFeedbackSettings.defaults;

  static void configure(CoverFeedbackSettings settings) {
    _settings = settings;
  }

  static void playCoverChanged() {
    final settings = _settings;
    if (settings.hapticStrength <= 0 && settings.soundStrength <= 0) return;
    unawaited(_send(settings));
  }

  static Future<void> _send(CoverFeedbackSettings settings) async {
    try {
      await _channel.invokeMethod<void>('coverChanged', {
        'hapticStrength': settings.hapticStrength,
        'soundStrength': settings.soundStrength,
      });
    } catch (_) {
      // Desktop and widget tests do not provide the Android feedback channel.
    }
  }
}
