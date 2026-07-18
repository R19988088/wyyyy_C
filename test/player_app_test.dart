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
    final coverSize = tester.getSize(find.byKey(const Key('cover-art-0')));
    expect(coverSize.width, closeTo(coverSize.height, .01));

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

  testWidgets('square cover fits a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );
    await tester.pump();

    final coverSize = tester.getSize(find.byKey(const Key('cover-art-0')));
    expect(coverSize.width, closeTo(coverSize.height, .01));
    expect(tester.takeException(), isNull);

    await tester.fling(
      find.byKey(const ValueKey('covers')),
      const Offset(0, -400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collection-title')), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    final originalCoverRect = tester.getRect(
      find.byKey(const Key('cover-art-1')),
    );
    await tester.fling(
      find.byKey(const ValueKey('covers')),
      const Offset(0, -400),
      1000,
    );
    await tester.pump();
    expect(
      tester.getRect(find.byKey(const Key('cover-expansion'))),
      originalCoverRect,
    );
    expect(
      tester
          .widget<IgnorePointer>(find.byKey(const Key('transition-list-guard')))
          .ignoring,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byKey(const Key('cover-expansion')), findsOneWidget);
    expect(find.byKey(const Key('fullscreen-track-list')), findsOneWidget);
    final expansionRect = tester.getRect(
      find.byKey(const Key('cover-expansion')),
    );
    expect(expansionRect.width, greaterThan(originalCoverRect.width));
    expect(expansionRect.height, greaterThan(originalCoverRect.height));
    await tester.pump(const Duration(milliseconds: 200));
    final nearFullRect = tester.getRect(
      find.byKey(const Key('cover-expansion')),
    );
    final contentRect = tester.getRect(find.byKey(const Key('player-content')));
    expect(nearFullRect.left, closeTo(contentRect.left, 1));
    expect(nearFullRect.top, closeTo(contentRect.top, 1));
    expect(nearFullRect.width, closeTo(contentRect.width, 2));
    expect(nearFullRect.height, closeTo(contentRect.height, 2));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tracks')), findsOneWidget);
    expect(find.byKey(const Key('fullscreen-track-list')), findsOneWidget);
    expect(find.byKey(const Key('library-header')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('collection-title')),
        matching: find.text('时间的歌'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('player-controls')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.byKey(const Key('cover-expansion')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('covers')), findsOneWidget);
    expect(find.text('时间的歌'), findsOneWidget);
  });

  testWidgets('back during expansion reverses from the current frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );
    await tester.fling(
      find.byKey(const ValueKey('covers')),
      const Offset(0, -400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final beforeBack = tester.getRect(find.byKey(const Key('cover-expansion')));

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final afterBack = tester.getRect(find.byKey(const Key('cover-expansion')));
    expect(afterBack.width, lessThan(beforeBack.width));
    expect(afterBack.height, lessThan(beforeBack.height));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('covers')), findsOneWidget);
  });
}
