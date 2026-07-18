import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
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
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    expect(find.byKey(const Key('cover-scrubber')), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const Key('category-tabs'))).dx,
      closeTo(tester.getCenter(find.byKey(const Key('player-content'))).dx, 1),
    );
    final activeCategory = tester.widget<AnimatedContainer>(
      find.byKey(const Key('category-album')),
    );
    expect((activeCategory.decoration as BoxDecoration).color, isNotNull);
    final activeCategoryText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('category-album')),
        matching: find.text('专辑'),
      ),
    );
    expect(activeCategoryText.style!.shadows, isNotEmpty);
    expect(
      activeCategoryText.style!.shadows!.first.color,
      Colors.black.withValues(alpha: .6),
    );
    expect(find.byKey(const Key('player-metadata')), findsOneWidget);
    expect(find.byKey(const Key('player-controls')), findsOneWidget);
    expect(find.byKey(const Key('player-progress')), findsOneWidget);
    final coverSize = tester.getSize(find.byKey(const Key('cover-art-0')));
    expect(coverSize.width, closeTo(coverSize.height, .01));
    final covers = tester.widget<PageView>(
      find.byKey(const ValueKey('covers')),
    );
    expect(covers.controller!.viewportFraction, .16);
    expect(covers.reverse, isTrue);
    expect(covers.clipBehavior, Clip.none);
    final coverSpacing =
        (tester.getCenter(find.byKey(const Key('cover-art-1'))).dx -
                tester.getCenter(find.byKey(const Key('cover-art-0'))).dx)
            .abs();
    expect(
      coverSpacing,
      closeTo(
        tester.getSize(find.byKey(const ValueKey('covers'))).width * .423,
        1,
      ),
    );

    final glass = tester.widget<GlassContainer>(find.byType(GlassContainer));
    final shape = glass.shape as LiquidRoundedSuperellipse;
    expect(shape.side, BorderSide.none);
    final playerFrame = tester.widget<DecoratedBox>(
      find.byKey(const Key('player-glass-frame')),
    );
    final frameBorder = (playerFrame.decoration as BoxDecoration).border!;
    expect(frameBorder.top.width, 1);
    expect(frameBorder.top.color, Colors.black.withValues(alpha: .3));
    expect(glass.settings!.blur, 2);
    expect(glass.settings!.thickness, closeTo(44.2, .01));
    expect(glass.settings!.lightIntensity, closeTo(.828, .001));
    expect(glass.settings!.chromaticAberration, closeTo(.44, .001));
    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(
      theme.textTheme.bodyMedium!.shadows!.first.color.a,
      closeTo(.6, .001),
    );
    expect(theme.iconTheme.shadows!.first.color.a, closeTo(.6, .001));
    expect(theme.iconTheme.shadows!.first.offset, const Offset(-.5, -.5));

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
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
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

  testWidgets('center cover requires a double tap to start playback', (
    tester,
  ) async {
    final repository = InMemoryPlayerRepository(const [
      MusicCollection(
        'first',
        'First collection',
        'First owner',
        LibraryKind.album,
        [Track('first-track', 'First track', 'First artist')],
      ),
      MusicCollection(
        'second',
        'Second collection',
        'Second owner',
        LibraryKind.album,
        [Track('second-track', 'Second track', 'Second artist')],
      ),
    ]);
    await tester.pumpWidget(PlayerApp(repository: repository));
    await tester.drag(
      find.byKey(const ValueKey('covers')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cover-art-1')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('player-metadata')),
        matching: find.text('First track'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('cover-art-1')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('cover-art-1')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('player-metadata')),
        matching: find.text('Second track'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping the hidden side area does not change the cover', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );

    final sideCover = tester.getRect(find.byKey(const Key('cover-art-1')));
    final tapPosition = sideCover.center;
    final viewport = tester.getRect(find.byKey(const ValueKey('covers')));
    final pageWidth =
        tester.getSize(find.byKey(const ValueKey('covers'))).width * .16;
    expect(tapPosition.dx, lessThan(viewport.center.dx - pageWidth * 1.5));
    await tester.tapAt(tapPosition);
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.byKey(const Key('cover-art-0'))).dx,
      closeTo(tester.getCenter(find.byKey(const Key('player-content'))).dx, 1),
    );
  });

  testWidgets('cover flow hides side covers until drag', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const tracks = [Track('track', 'Track', 'Artist')];
    final collections = List.generate(
      9,
      (index) => MusicCollection(
        '$index',
        'Collection $index',
        'Owner',
        LibraryKind.album,
        tracks,
      ),
    );
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository(collections)),
    );
    final pageView = tester.widget<PageView>(
      find.byKey(const ValueKey('covers')),
    );
    pageView.controller!.jumpToPage(4);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Opacity>(find.byKey(const Key('cover-visibility-4')))
          .opacity,
      1,
    );
    for (final index in [2, 3, 5, 6]) {
      expect(
        tester
            .widget<Opacity>(find.byKey(Key('cover-visibility-$index')))
            .opacity,
        0,
      );
    }
  });

  testWidgets('hidden scrubber uses a fast drag to cross multiple covers', (
    tester,
  ) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );

    await tester.drag(
      find.byKey(const Key('cover-scrubber')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.byKey(const Key('cover-art-2'))).dx,
      closeTo(tester.getCenter(find.byKey(const Key('player-content'))).dx, 1),
    );
  });

  testWidgets('holding the scrubber elastically shrinks and rebounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );
    final normalSpacing =
        (tester.getCenter(find.byKey(const Key('cover-art-1'))).dx -
                tester.getCenter(find.byKey(const Key('cover-art-0'))).dx)
            .abs();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cover-scrubber'))),
    );
    await tester.pump();
    final pressedScale = tester.widget<AnimatedScale>(
      find.byKey(const Key('cover-switch-scale')),
    );
    expect(pressedScale.scale, .72);
    expect(pressedScale.curve, Curves.easeOutBack);
    expect(
      tester
          .widget<Opacity>(find.byKey(const Key('cover-visibility-1')))
          .opacity,
      1,
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(
      tester
          .widget<Opacity>(find.byKey(const Key('cover-visibility-1')))
          .opacity,
      1,
    );
    await tester.pump(const Duration(milliseconds: 180));
    final sideCover = tester.getRect(find.byKey(const Key('cover-art-1')));
    expect(sideCover.width, greaterThan(45));
    expect(sideCover.overlaps(const Rect.fromLTWH(0, 0, 400, 900)), isTrue);
    final compactSpacing =
        (tester.getCenter(find.byKey(const Key('cover-art-1'))).dx -
                tester.getCenter(find.byKey(const Key('cover-art-0'))).dx)
            .abs();
    expect(compactSpacing, closeTo(normalSpacing * .812, 1));
    await gesture.up();
    await tester.pump();

    final restoredScale = tester.widget<AnimatedScale>(
      find.byKey(const Key('cover-switch-scale')),
    );
    expect(restoredScale.scale, 1);
    expect(restoredScale.curve, Curves.elasticOut);
    await tester.pumpAndSettle();
    final restoredSpacing =
        (tester.getCenter(find.byKey(const Key('cover-art-1'))).dx -
                tester.getCenter(find.byKey(const Key('cover-art-0'))).dx)
            .abs();
    expect(restoredSpacing, closeTo(normalSpacing, 1));
  });

  testWidgets('direct cover drag restores scale as soon as the finger lifts', (
    tester,
  ) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cover-art-0'))),
    );
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const Key('cover-switch-scale')))
          .scale,
      .8,
    );
    await gesture.up();
    await tester.pump();

    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const Key('cover-switch-scale')))
          .scale,
      1,
    );
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('cover drag shows five wider layered side covers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const tracks = [Track('track', 'Track', 'Artist')];
    final collections = List.generate(
      9,
      (index) => MusicCollection(
        '$index',
        'Collection $index',
        'Owner',
        LibraryKind.album,
        tracks,
      ),
    );
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository(collections)),
    );
    final pageView = tester.widget<PageView>(
      find.byKey(const ValueKey('covers')),
    );
    pageView.controller!.jumpToPage(4);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cover-art-4'))),
    );
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester
          .widget<AnimatedScale>(find.byKey(const Key('cover-switch-scale')))
          .scale,
      .8,
    );
    await tester.pump(const Duration(milliseconds: 110));
    final viewport =
        Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
    final visibleCovers =
        [
            for (var index = 1; index < 8; index++)
              tester.getRect(find.byKey(Key('cover-art-$index'))),
          ].where((rect) => rect.overlaps(viewport)).toList()
          ..sort((left, right) => left.left.compareTo(right.left));
    expect(visibleCovers, hasLength(5));
    for (var index = 1; index < visibleCovers.length; index++) {
      expect(
        visibleCovers[index].left - visibleCovers[index - 1].right,
        greaterThanOrEqualTo(0),
      );
    }
    final nearWidth = tester
        .getRect(find.byKey(const Key('cover-art-3')))
        .width;
    final farWidth = tester.getRect(find.byKey(const Key('cover-art-2'))).width;
    expect(
      tester
          .widget<Opacity>(find.byKey(const Key('cover-visibility-3')))
          .opacity,
      1,
    );
    expect(nearWidth, greaterThan(50));
    expect(nearWidth, greaterThan(farWidth * 3));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('returning to a cover preserves its image subtree', (
    tester,
  ) async {
    const tracks = [Track('track', 'Track', 'Artist')];
    final collections = List.generate(
      5,
      (index) => MusicCollection(
        '$index',
        'Collection $index',
        'Owner',
        LibraryKind.album,
        tracks,
      ),
    );
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository(collections)),
    );
    final originalSurface = tester.element(
      find.byKey(const Key('cover-surface-0')),
    );

    for (var index = 0; index < 3; index++) {
      await tester.drag(
        find.byKey(const ValueKey('covers')),
        const Offset(90, 0),
      );
      await tester.pumpAndSettle();
    }
    expect(
      find.byKey(const Key('cover-surface-0'), skipOffstage: false),
      findsOneWidget,
    );

    for (var index = 0; index < 3; index++) {
      await tester.drag(
        find.byKey(const ValueKey('covers')),
        const Offset(-90, 0),
      );
      await tester.pumpAndSettle();
    }

    expect(
      tester.element(find.byKey(const Key('cover-surface-0'))),
      same(originalSurface),
    );
  });

  testWidgets('production glass wrapper avoids obsolete backdrop scopes', (
    tester,
  ) async {
    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        child: PlayerApp(repository: InMemoryPlayerRepository.demo()),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'GlassBackdropScope',
      ),
      findsNothing,
    );
  });

  testWidgets('cover subtree retention stays bounded', (tester) async {
    const tracks = [Track('track', 'Track', 'Artist')];
    final collections = List.generate(
      9,
      (index) => MusicCollection(
        '$index',
        'Collection $index',
        'Owner',
        LibraryKind.album,
        tracks,
      ),
    );
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository(collections)),
    );

    for (var index = 0; index < 8; index++) {
      await tester.drag(
        find.byKey(const ValueKey('covers')),
        const Offset(90, 0),
      );
      await tester.pumpAndSettle();
    }

    expect(
      find.byKey(const Key('cover-surface-0'), skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('glass player survives app background and resume', (
    tester,
  ) async {
    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        child: PlayerApp(repository: InMemoryPlayerRepository.demo()),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('player-glass-frame')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one scrub gesture keeps sampling after the focused page changes',
    (tester) async {
      const tracks = [Track('track', 'Track', 'Artist')];
      final collections = List.generate(
        8,
        (index) => MusicCollection(
          '$index',
          'Collection $index',
          'Owner',
          LibraryKind.album,
          tracks,
        ),
      );
      await tester.pumpWidget(
        PlayerApp(repository: InMemoryPlayerRepository(collections)),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('cover-scrubber'))),
      );
      for (var index = 0; index < 4; index++) {
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(find.byKey(const Key('cover-art-3'))).dx,
        closeTo(
          tester.getCenter(find.byKey(const Key('player-content'))).dx,
          1,
        ),
      );

      final returnGesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('cover-scrubber'))),
      );
      for (var index = 0; index < 4; index++) {
        await returnGesture.moveBy(const Offset(-30, 0));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await returnGesture.up();
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(find.byKey(const Key('cover-art-0'))).dx,
        closeTo(
          tester.getCenter(find.byKey(const Key('player-content'))).dx,
          1,
        ),
      );
    },
  );

  testWidgets('vertical swipe from the scrubber still opens the track list', (
    tester,
  ) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );

    await tester.fling(
      find.byKey(const Key('cover-scrubber')),
      const Offset(0, -400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fullscreen-track-list')), findsOneWidget);
  });

  testWidgets('downward swipe also opens the track list', (tester) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );

    await tester.fling(
      find.byKey(const ValueKey('covers')),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fullscreen-track-list')), findsOneWidget);
  });

  testWidgets('track list shows metadata numbers and active progress fill', (
    tester,
  ) async {
    const title =
        'A complete collection title that must wrap without ellipsis '
        'even when the collection name contains several descriptive clauses '
        'and remains fully available in the scrollable metadata header';
    const collection = MusicCollection(
      'album',
      title,
      'Artist · 2024',
      LibraryKind.album,
      [Track('track', 'Track', 'Artist')],
    );
    await tester.pumpWidget(
      PlayerApp(repository: _ProgressRepository(collection)),
    );
    await tester.pump();
    await tester.fling(
      find.byKey(const ValueKey('covers')),
      const Offset(0, -400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text(title), findsOneWidget);
    expect(find.text('Artist · 2024'), findsOneWidget);
    expect(find.text('1 '), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('collection-title'))).height,
      greaterThanOrEqualTo(100),
    );
    expect(
      tester.getSize(find.byKey(const Key('collection-subtitle-gap'))).height,
      10,
    );
    final titlePadding = tester.widget<Padding>(
      find.byKey(const Key('collection-title-padding')),
    );
    expect(titlePadding.padding, const EdgeInsets.fromLTRB(20, 32, 20, 5));
    final row = tester.widget<DecoratedBox>(
      find.byKey(const Key('track-row-0')),
    );
    final gradient = (row.decoration as BoxDecoration).gradient!;
    expect(gradient.colors.first.a, closeTo(.2, .001));
    expect(gradient.stops, [0, .5, .5, 1]);
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
    final tabsRect = tester.getRect(find.byKey(const Key('category-tabs')));
    final menuRect = tester.getRect(find.byKey(const Key('settings-menu')));
    expect(tabsRect.right, lessThanOrEqualTo(menuRect.left));
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
      const Offset(90, 0),
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
    expect(
      tester.getCenter(find.byKey(const Key('cover-art-1'))).dx,
      closeTo(tester.getCenter(find.byKey(const Key('player-content'))).dx, 1),
    );
  });

  testWidgets('rebounded cover expands from its transformed rectangle', (
    tester,
  ) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cover-scrubber'))),
    );
    await tester.pump(const Duration(milliseconds: 180));
    await gesture.up();
    await tester.pumpAndSettle();
    final coverRect = tester.getRect(find.byKey(const Key('cover-art-0')));

    await tester.fling(
      find.byKey(const ValueKey('covers')),
      const Offset(0, -400),
      1000,
    );
    await tester.pump();

    final expansionRect = tester.getRect(
      find.byKey(const Key('cover-expansion')),
    );
    expect(expansionRect.left, closeTo(coverRect.left, 1));
    expect(expansionRect.top, closeTo(coverRect.top, 1));
    expect(expansionRect.width, closeTo(coverRect.width, 1));
    expect(expansionRect.height, closeTo(coverRect.height, 1));
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

class _ProgressRepository implements PlaybackRepository {
  _ProgressRepository(this.collection);

  final MusicCollection collection;

  @override
  Stream<PlaybackSnapshot> get playback => Stream.value(
    const PlaybackSnapshot(playing: true, trackIndex: 0, progress: .5),
  );

  @override
  MusicCollection get restoredCollection => collection;

  @override
  int get restoredTrackIndex => 0;

  @override
  List<MusicCollection> collections(LibraryKind kind) =>
      kind == collection.kind ? [collection] : const [];

  @override
  Future<int> activate(
    MusicCollection collection, {
    int trackIndex = 0,
    bool autoplay = true,
  }) async => trackIndex;

  @override
  Future<void> loadTracks(MusicCollection collection) async {}

  @override
  Future<int> next() async => 0;

  @override
  Future<int> previous() async => 0;

  @override
  Future<void> seek(double progress) async {}

  @override
  Future<bool> togglePlaying() async => true;

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> reload() async {}
}
