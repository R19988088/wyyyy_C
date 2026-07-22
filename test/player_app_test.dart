import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:wyyyy/main.dart';
import 'package:wyyyy/player.dart';
import 'package:wyyyy/services/cover_feedback.dart';

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
    expect(find.byKey(const Key('cover-haptic-strength')), findsOneWidget);
    expect(find.byKey(const Key('cover-sound-strength')), findsOneWidget);
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

  testWidgets('settings sliders persist independent cover feedback strengths', (
    tester,
  ) async {
    final saved = <CoverFeedbackSettings>[];
    await tester.pumpWidget(
      PlayerApp(
        repository: InMemoryPlayerRepository.demo(),
        saveCoverFeedback: (value) async => saved.add(value),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    tester
        .widget<Slider>(find.byKey(const Key('cover-haptic-strength')))
        .onChanged!(.25);
    await tester.pump();
    tester
        .widget<Slider>(find.byKey(const Key('cover-sound-strength')))
        .onChanged!(.85);
    await tester.pump();

    expect(saved, hasLength(2));
    expect(saved.first.hapticStrength, .25);
    expect(saved.first.soundStrength, .7);
    expect(saved.last.hapticStrength, .25);
    expect(saved.last.soundStrength, .85);
  });

  testWidgets('settings omits the obsolete album switching view', (
    tester,
  ) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('album-switch-view')), findsNothing);
    expect(find.text('切换专辑时'), findsNothing);
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
    tester
        .widget<PageView>(find.byKey(const ValueKey('covers')))
        .controller!
        .jumpToPage(1);
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
    expect(find.byKey(const Key('album-switch-list')), findsNothing);
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

  testWidgets(
    'wheel waits for a clear vertical angle before opening the list',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        PlayerApp(repository: InMemoryPlayerRepository.demo()),
      );

      final wheel = find.byKey(const Key('cover-wheel'));
      final ambiguous = await tester.startGesture(tester.getCenter(wheel));
      await ambiguous.moveBy(const Offset(30, -25));
      await ambiguous.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('album-switch-list')), findsNothing);

      final vertical = await tester.startGesture(tester.getCenter(wheel));
      await vertical.moveBy(const Offset(10, -30));
      await vertical.up();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('album-switch-list')), findsOneWidget);
      expect(find.byKey(const Key('fullscreen-track-list')), findsNothing);
    },
  );

  testWidgets('cover caption uses the cover width', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );

    expect(
      tester.getSize(find.byKey(const Key('cover-caption-0'))).width,
      closeTo(tester.getSize(find.byKey(const Key('cover-art-0'))).width, 1),
    );
  });

  testWidgets(
    'album switch list scrolls freely without a fixed center selection',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      const tracks = [Track('track', 'Track', 'Artist')];
      final collections = List.generate(
        7,
        (index) => MusicCollection(
          '$index',
          'Collection $index',
          'Owner $index',
          LibraryKind.album,
          tracks,
        ),
      );
      await tester.pumpWidget(
        PlayerApp(repository: InMemoryPlayerRepository(collections)),
      );
      expect(find.byKey(const Key('album-switch-list')), findsNothing);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('cover-scrubber'))),
      );
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump();

      final list = find.byKey(const Key('album-switch-list'));
      expect(list, findsOneWidget);
      expect(
        find.byKey(const Key('cover-flow-fold-transition')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('album-switch-list-transition')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('album-switch-selection-band')),
        findsNothing,
      );
      expect(find.byKey(const Key('album-switch-scroll')), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const Key('album-switch-cover-0'))).dx,
        lessThan(
          tester.getCenter(find.byKey(const Key('album-switch-title-0'))).dx,
        ),
      );

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('free album list scroll keeps per-row cover feedback', (
    tester,
  ) async {
    const channel = MethodChannel('com.r19988088.wyyyy/cover_feedback');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => calls.add(call),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    const tracks = [Track('track', 'Track', 'Artist')];
    final collections = List.generate(
      12,
      (index) => MusicCollection(
        '$index',
        'Collection $index',
        'Owner $index',
        LibraryKind.album,
        tracks,
      ),
    );
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository(collections)),
    );
    final open = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cover-art-0'))),
    );
    await open.moveBy(const Offset(0, -24));
    await open.up();
    await tester.pumpAndSettle();
    calls.clear();

    await tester.drag(
      find.byKey(const Key('album-switch-scroll')),
      const Offset(0, -170),
    );
    await tester.pumpAndSettle();

    expect(calls.where((call) => call.method == 'coverChanged').length, 2);
  });

  testWidgets('album switch list extends beneath the glass player', (
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
      5,
      (index) => MusicCollection(
        '$index',
        'Collection $index',
        'Owner $index',
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
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();

    final listRect = tester.getRect(find.byKey(const Key('album-switch-list')));
    final playerRect = tester.getRect(
      find.byKey(const Key('player-glass-frame')),
    );
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pumpAndSettle();

    expect(listRect.bottom, greaterThan(playerRect.bottom));
    expect(listRect.overlaps(playerRect), isTrue);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'opening the free album list does not change the browsed cover or playback',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repository = InMemoryPlayerRepository(const [
        MusicCollection('0', 'Collection 0', 'Owner 0', LibraryKind.album, [
          Track('track-0', 'Track 0', 'Artist 0'),
        ]),
        MusicCollection('1', 'Collection 1', 'Owner 1', LibraryKind.album, [
          Track('track-1', 'Track 1', 'Artist 1'),
        ]),
        MusicCollection('2', 'Collection 2', 'Owner 2', LibraryKind.album, [
          Track('track-2', 'Track 2', 'Artist 2'),
        ]),
      ]);
      await tester.pumpWidget(PlayerApp(repository: repository));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('cover-scrubber'))),
      );
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      final list = find.byKey(const Key('album-switch-list'));
      expect(find.byKey(const Key('album-switch-selected-0')), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(list, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('player-metadata')),
          matching: find.text('Track 0'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('vertical cover drag opens the free list without browsing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = InMemoryPlayerRepository(const [
      MusicCollection('0', 'Collection 0', 'Owner 0', LibraryKind.album, [
        Track('track-0', 'Track 0', 'Artist 0'),
      ]),
      MusicCollection('1', 'Collection 1', 'Owner 1', LibraryKind.album, [
        Track('track-1', 'Track 1', 'Artist 1'),
      ]),
      MusicCollection('2', 'Collection 2', 'Owner 2', LibraryKind.album, [
        Track('track-2', 'Track 2', 'Artist 2'),
      ]),
    ]);
    await tester.pumpWidget(PlayerApp(repository: repository));

    final upward = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cover-art-0'))),
    );
    await upward.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('album-switch-list')), findsOneWidget);
    await upward.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('album-switch-list')), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const Key('cover-art-0'))).dx,
      closeTo(tester.getCenter(find.byKey(const Key('player-content'))).dx, 1),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('player-metadata')),
        matching: find.text('Track 0'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cancelled list tap cannot complete a double-tap activation', (
    tester,
  ) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );
    final wheel = find.byKey(const Key('cover-scrubber'));
    final browse = await tester.startGesture(tester.getCenter(wheel));
    await browse.moveBy(const Offset(0, -24));
    await browse.up();
    await tester.pumpAndSettle();

    final selected = find.byKey(const Key('album-switch-selected-0'));
    await tester.tap(selected);
    final cancelled = await tester.startGesture(tester.getCenter(selected));
    await cancelled.cancel();
    await tester.tap(selected);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('album-switch-list')), findsOneWidget);
  });

  testWidgets('horizontal swipe toggles the cover and track list', (
    tester,
  ) async {
    for (final delta in const [-240.0, 240.0]) {
      await tester.pumpWidget(
        PlayerApp(repository: InMemoryPlayerRepository.demo()),
      );

      await tester.drag(find.byKey(const Key('cover-art-0')), Offset(delta, 0));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fullscreen-track-list')), findsOneWidget);

      await tester.drag(
        find.byKey(const Key('fullscreen-track-list')),
        Offset(delta, 0),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fullscreen-track-list')), findsNothing);
      expect(
        tester.getCenter(find.byKey(const Key('cover-art-0'))).dx,
        closeTo(
          tester.getCenter(find.byKey(const Key('player-content'))).dx,
          1,
        ),
      );
    }
  });

  testWidgets('horizontal swipe stays inert without collections', (
    tester,
  ) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository(const [])),
    );

    await tester.drag(find.text('尚未登录或暂无收藏'), const Offset(240, 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fullscreen-track-list')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagonal gesture waits for a clear direction', (tester) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cover-art-0'))),
    );
    await gesture.moveBy(const Offset(60, 50));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('album-switch-list')), findsNothing);
    expect(find.byKey(const Key('fullscreen-track-list')), findsNothing);
  });

  testWidgets('back from the active cover opens the album list', (
    tester,
  ) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('album-switch-list')), findsOneWidget);
    expect(find.byKey(const Key('fullscreen-track-list')), findsNothing);
  });

  testWidgets('double tapping player cover returns to the active cover', (
    tester,
  ) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('album-switch-list')), findsOneWidget);

    await tester.tap(find.byKey(const Key('player-mini-cover')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('player-mini-cover')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('album-switch-list')), findsNothing);
    expect(
      tester.getCenter(find.byKey(const Key('cover-art-0'))).dx,
      closeTo(tester.getCenter(find.byKey(const Key('player-content'))).dx, 1),
    );
  });

  testWidgets('vertical-first gestures do not toggle cover and track list', (
    tester,
  ) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );

    final coverGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cover-art-0'))),
    );
    await coverGesture.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 100));
    await coverGesture.moveBy(const Offset(80, 0));
    await coverGesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fullscreen-track-list')), findsNothing);
    expect(
      tester.getCenter(find.byKey(const Key('cover-art-1'))).dx,
      isNot(
        closeTo(
          tester.getCenter(find.byKey(const Key('player-content'))).dx,
          1,
        ),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('cover-art-0')),
      const Offset(240, 0),
    );
    await tester.pumpAndSettle();
    final listGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('fullscreen-track-list'))),
    );
    await listGesture.moveBy(const Offset(0, -60));
    await listGesture.moveBy(const Offset(120, 40));
    await listGesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fullscreen-track-list')), findsOneWidget);
  });

  testWidgets('double tapping any album row activates that collection', (
    tester,
  ) async {
    final repository = InMemoryPlayerRepository(const [
      MusicCollection('0', 'Collection 0', 'Owner 0', LibraryKind.album, [
        Track('track-0', 'Track 0', 'Artist 0'),
      ]),
      MusicCollection('1', 'Collection 1', 'Owner 1', LibraryKind.album, [
        Track('track-1', 'Track 1', 'Artist 1'),
      ]),
      MusicCollection('2', 'Collection 2', 'Owner 2', LibraryKind.album, [
        Track('track-2', 'Track 2', 'Artist 2'),
      ]),
    ]);
    await tester.pumpWidget(PlayerApp(repository: repository));

    final open = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cover-art-0'))),
    );
    await open.moveBy(const Offset(0, -40));
    await open.up();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('album-switch-selected-2')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('album-switch-selected-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('album-switch-list')), findsNothing);
    expect(
      tester.getCenter(find.byKey(const Key('cover-art-2'))).dx,
      closeTo(tester.getCenter(find.byKey(const Key('player-content'))).dx, 1),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('player-metadata')),
        matching: find.text('Track 2'),
      ),
      findsOneWidget,
    );
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
    final pages = tester
        .widget<PageView>(find.byKey(const ValueKey('covers')))
        .controller!;

    pages.jumpToPage(3);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('cover-surface-0'), skipOffstage: false),
      findsOneWidget,
    );

    pages.jumpToPage(0);
    await tester.pumpAndSettle();

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
    final pages = tester
        .widget<PageView>(find.byKey(const ValueKey('covers')))
        .controller!;

    for (var index = 1; index < 9; index++) {
      pages.jumpToPage(index);
      await tester.pump();
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

  testWidgets('list switching stays open after a vertical wheel swipe', (
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

    expect(find.byKey(const Key('album-switch-list')), findsOneWidget);
    expect(find.byKey(const Key('fullscreen-track-list')), findsNothing);
    expect(find.byKey(const ValueKey('covers')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('player-metadata')),
        matching: find.text('晴天'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cancelling list switching returns to the cover', (tester) async {
    await tester.pumpWidget(
      PlayerApp(repository: InMemoryPlayerRepository.demo()),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cover-scrubber'))),
    );
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();
    expect(find.byKey(const Key('album-switch-list')), findsOneWidget);

    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('album-switch-list')), findsNothing);
    expect(find.byKey(const Key('fullscreen-track-list')), findsNothing);
    expect(find.byKey(const ValueKey('covers')), findsOneWidget);
  });

  testWidgets('vertical swipes outside the cover keep the track list closed', (
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

    await tester.flingFrom(const Offset(8, 360), const Offset(0, -240), 1000);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fullscreen-track-list')), findsNothing);
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
    await tester.drag(
      find.byKey(const Key('cover-art-0')),
      const Offset(240, 0),
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

    final albumGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cover-art-0'))),
    );
    await albumGesture.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('album-switch-list')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await albumGesture.up();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('cover-art-0')),
      const Offset(240, 0),
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
    tester
        .widget<PageView>(find.byKey(const ValueKey('covers')))
        .controller!
        .jumpToPage(1);
    await tester.pumpAndSettle();
    final originalCoverRect = tester.getRect(
      find.byKey(const Key('cover-art-1')),
    );
    await tester.drag(
      find.byKey(const Key('cover-art-1')),
      const Offset(240, 0),
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
    expect(find.text('时间的歌'), findsWidgets);
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

    await tester.drag(
      find.byKey(const Key('cover-art-0')),
      const Offset(240, 0),
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
    await tester.drag(
      find.byKey(const Key('cover-art-0')),
      const Offset(240, 0),
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
    int? trackIndex,
    bool autoplay = true,
  }) async => trackIndex ?? 0;

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
