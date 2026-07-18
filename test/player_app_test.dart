import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyyyy/main.dart';
import 'package:wyyyy/player.dart';

void main() {
  testWidgets('shows library tabs and the three-row player', (tester) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );

    expect(find.text('专辑'), findsOneWidget);
    expect(find.text('歌单'), findsOneWidget);
    expect(find.text('播客'), findsOneWidget);
    expect(find.byKey(const Key('player-metadata')), findsOneWidget);
    expect(find.byKey(const Key('player-controls')), findsOneWidget);
    expect(find.byKey(const Key('player-progress')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sleep-timer')));
    await tester.pump();
    expect(find.text('60'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sleep-timer')));
    await tester.pump();
    expect(find.text('120'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sleep-timer')));
    await tester.pump();
    expect(find.byIcon(Icons.hourglass_empty_rounded), findsOneWidget);
  });

  testWidgets('settings switches theme and opens QR login', (tester) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('深色模式'), findsOneWidget);
    await tester.tap(find.text('深色模式'));
    await tester.pump();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    await tester.tap(find.text('登录网易云音乐'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('扫码登录'), findsOneWidget);
  });

  testWidgets('back gesture returns from track list to the same cover', (
    tester,
  ) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );
    await tester.drag(
      find.byKey(const ValueKey('covers')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.fling(
      find.byKey(const ValueKey('covers')),
      const Offset(0, -400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tracks')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('covers')), findsOneWidget);
    expect(find.text('时间的歌'), findsOneWidget);
  });
}
