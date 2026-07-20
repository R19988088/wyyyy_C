import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyyyy/services/cover_feedback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.r19988088.wyyyy/cover_feedback');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'cover changes dispatch independent haptic and sound strengths',
    () async {
      CoverFeedback.configure(
        const CoverFeedbackSettings(hapticStrength: .4, soundStrength: .8),
      );

      CoverFeedback.playCoverChanged();
      await Future<void>.delayed(Duration.zero);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'coverChanged');
      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['hapticStrength'], .4);
      expect(arguments['soundStrength'], closeTo(.16, .0001));
    },
  );

  test(
    'disabled cover feedback does not invoke the platform channel',
    () async {
      CoverFeedback.configure(
        const CoverFeedbackSettings(hapticStrength: 0, soundStrength: 0),
      );

      CoverFeedback.playCoverChanged();
      await Future<void>.delayed(Duration.zero);

      expect(calls, isEmpty);
    },
  );
}
