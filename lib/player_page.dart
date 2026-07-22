import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'cover_scrubber.dart';
import 'player.dart';
import 'services/media_cache.dart';
import 'services/cover_feedback.dart';
import 'widgets/glass_player.dart';

const _coverViewportFraction = .16;
const _coverWidthFraction = .88;
const _firstSideCoverOffset = .423;
const _sideCoverStep = .068;
const _sideCoverScale = .62;
const _sideCoverAngle = 1.45;

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.repository,
    required this.openSettings,
  });

  final PlayerRepository repository;
  final Future<void> Function() openSettings;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin {
  static const maxRetainedCovers = 7;

  late final PlayerController controller;
  late PageController pages;
  late final AnimationController modeTransition;
  late final CoverScrubSpeedController scrubSpeed;
  final contentKey = GlobalKey();
  final coverKeys = <String, GlobalKey>{};
  final retainedCoverIds = <String>{};
  Rect? coverStartRect;
  MusicCollection? transitionCollection;
  LibraryKind? listOriginKind;
  String? listOriginId;
  int? listOriginIndex;
  bool listMode = false;
  bool scrubberActive = false;
  bool albumListOpen = false;

  GlobalKey _coverKey(MusicCollection collection) =>
      coverKeys.putIfAbsent(_coverId(collection), GlobalKey.new);

  String _coverId(MusicCollection collection) =>
      '${collection.kind.name}:${collection.id}';

  void _retainCover(MusicCollection collection) {
    final id = _coverId(collection);
    retainedCoverIds
      ..remove(id)
      ..add(id);
    if (retainedCoverIds.length > maxRetainedCovers) {
      retainedCoverIds.remove(retainedCoverIds.first);
    }
  }

  bool _keepCoverAlive(MusicCollection collection) =>
      retainedCoverIds.contains(_coverId(collection));

  @override
  void initState() {
    super.initState();
    controller = PlayerController(widget.repository)..addListener(_refresh);
    modeTransition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    scrubSpeed = CoverScrubSpeedController();
    pages = PageController(viewportFraction: _coverViewportFraction);
    final repository = widget.repository;
    if (repository is PlaybackRepository &&
        repository.restoredCollection != null) {
      final restored = repository.restoredCollection!;
      controller.selectKind(restored.kind);
      final index = controller.visible.indexWhere(
        (item) => item.id == restored.id && item.kind == restored.kind,
      );
      if (index >= 0) {
        pages.dispose();
        pages = PageController(
          viewportFraction: _coverViewportFraction,
          initialPage: index,
        );
        controller.browseTo(index);
      }
    }
    _retainCover(controller.visible[controller.browsedIndex]);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    modeTransition.dispose();
    pages.dispose();
    controller.removeListener(_refresh);
    controller.dispose();
    super.dispose();
  }

  void _selectKind(LibraryKind kind) {
    controller.selectKind(kind);
    _retainCover(controller.visible[controller.browsedIndex]);
    pages.dispose();
    pages = PageController(
      viewportFraction: _coverViewportFraction,
      initialPage: controller.browsedIndex,
    );
  }

  Future<void> _openList() async {
    if (listMode || !controller.hasCollections) return;
    final contentBox =
        contentKey.currentContext?.findRenderObject() as RenderBox?;
    final collection = controller.visible[controller.browsedIndex];
    final coverBox =
        _coverKey(collection).currentContext?.findRenderObject() as RenderBox?;
    if (contentBox != null && coverBox != null) {
      coverStartRect = MatrixUtils.transformRect(
        coverBox.getTransformTo(contentBox),
        Offset.zero & coverBox.size,
      );
    }
    transitionCollection = collection;
    listOriginKind = controller.kind;
    listOriginId = transitionCollection!.id;
    listOriginIndex = controller.browsedIndex;
    setState(() => listMode = true);
    controller.ensureBrowsedTracks();
    await modeTransition.forward(from: 0);
  }

  Future<void> _closeList() async {
    if (!listMode || modeTransition.status == AnimationStatus.reverse) return;
    _restoreListOriginPage();
    await modeTransition.reverse();
    if (mounted) {
      setState(() {
        listMode = false;
        coverStartRect = null;
        transitionCollection = null;
        listOriginKind = null;
        listOriginId = null;
        listOriginIndex = null;
      });
    }
  }

  void _restoreListOriginPage() {
    final originKind = listOriginKind;
    if (originKind == null) return;
    if (controller.kind != originKind) controller.selectKind(originKind);
    final byId = controller.visible.indexWhere(
      (collection) => collection.id == listOriginId,
    );
    final target = (byId >= 0 ? byId : listOriginIndex ?? 0).clamp(
      0,
      controller.visible.length - 1,
    );
    final oldPages = pages;
    pages = PageController(
      viewportFraction: _coverViewportFraction,
      initialPage: target,
    );
    controller.browseTo(target);
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => oldPages.dispose());
  }

  void _scrubCovers(double delta, Duration timestamp) {
    final count = controller.visible.length;
    final step = scrubSpeed.update(delta: delta, timestamp: timestamp);
    if (step == null) return;
    final target = (controller.browsedIndex + step).clamp(0, count - 1);
    if (target == controller.browsedIndex) return;
    _browseTo(target, feedbackCount: (target - controller.browsedIndex).abs());
    pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _browseTo(int index, {int feedbackCount = 1}) {
    final changed = controller.browsedIndex != index;
    controller.browseTo(index);
    _retainCover(controller.visible[controller.browsedIndex]);
    for (var count = 0; changed && count < feedbackCount; count++) {
      CoverFeedback.playCoverChanged();
    }
  }

  void _setScrubberActive(bool active) {
    scrubSpeed.reset();
    if (scrubberActive == active) return;
    setState(() {
      scrubberActive = active;
      if (active) albumListOpen = true;
    });
  }

  void _activateBrowsedAlbum() {
    if (!controller.activateCentered(controller.browsedIndex)) return;
    _dismissAlbumList();
  }

  void _dismissAlbumList() {
    scrubSpeed.reset();
    setState(() {
      scrubberActive = false;
      albumListOpen = false;
    });
  }

  Future<void> _returnToPlaying() async {
    if (albumListOpen) _dismissAlbumList();
    final targetKind = controller.activeKind;
    if (controller.kind != targetKind) {
      controller.selectKind(targetKind);
      final target = controller.activeIndexInVisible();
      final start = target > 3 ? target - 3 : 0;
      pages.dispose();
      pages = PageController(
        viewportFraction: _coverViewportFraction,
        initialPage: start,
      );
      controller.browseTo(start);
      modeTransition.value = 0;
      setState(() {
        listMode = false;
        coverStartRect = null;
        transitionCollection = null;
        listOriginKind = null;
        listOriginId = null;
        listOriginIndex = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !pages.hasClients) return;
      await pages.animateToPage(
        target,
        duration: const Duration(milliseconds: 329),
        curve: Curves.easeOutExpo,
      );
      return;
    }
    if (listMode) {
      await _closeList();
      await WidgetsBinding.instance.endOfFrame;
    }
    final path = PlayerController.returnPath(
      from: controller.browsedIndex,
      to: controller.activeIndexInVisible(),
    );
    if (path.length == 2) {
      pages.jumpToPage(path.first);
      controller.browseTo(path.first);
    }
    await pages.animateToPage(
      path.last,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutExpo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (listMode) {
          _closeList();
        } else if (albumListOpen) {
          _dismissAlbumList();
        } else {
          _setScrubberActive(true);
        }
      },
      child: Scaffold(
        body: SafeArea(
          key: const Key('player-content'),
          child: Stack(
            key: contentKey,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => AnimatedBuilder(
                  animation: modeTransition,
                  builder: (context, _) {
                    final progress = Curves.easeOutCubic.transform(
                      modeTransition.value,
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (modeTransition.value < 1)
                          _CoverMode(
                            controller: controller,
                            pages: pages,
                            coverKeyFor: _coverKey,
                            keepCoverAlive: _keepCoverAlive,
                            onPageChanged: _browseTo,
                            coverPressed: scrubberActive,
                            showingSwitchList: albumListOpen,
                            onScrubStart: () => _setScrubberActive(true),
                            onScrubUpdate: _scrubCovers,
                            onScrubEnd: () => _setScrubberActive(false),
                            onScrubCancel: _dismissAlbumList,
                            activateBrowsedAlbum: _activateBrowsedAlbum,
                            progress: progress,
                            onSelected: _selectKind,
                            openSettings: () async {
                              await widget.openSettings();
                              controller.reloadVisible();
                            },
                            openList: _openList,
                          ),
                        if (listMode)
                          IgnorePointer(
                            key: const Key('transition-list-guard'),
                            ignoring: modeTransition.value < 1,
                            child: Opacity(
                              opacity: Curves.easeIn.transform(
                                ((modeTransition.value - .35) / .65).clamp(
                                  0,
                                  1,
                                ),
                              ),
                              child: _HorizontalSwipeRegion(
                                onSwipe: _closeList,
                                child: _FullscreenTrackList(
                                  controller: controller,
                                ),
                              ),
                            ),
                          ),
                        if (listMode &&
                            coverStartRect != null &&
                            transitionCollection != null &&
                            modeTransition.value < 1)
                          _ExpandingCover(
                            start: coverStartRect!,
                            end: Offset.zero & constraints.biggest,
                            progress: progress,
                            collection: transitionCollection!,
                            fallbackColor: _fallbackCoverColor(
                              controller.browsedIndex,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: GlassPlayer(
                  controller: controller,
                  onMetadataDoubleTap: _returnToPlaying,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverMode extends StatelessWidget {
  const _CoverMode({
    required this.controller,
    required this.pages,
    required this.coverKeyFor,
    required this.keepCoverAlive,
    required this.onPageChanged,
    required this.coverPressed,
    required this.showingSwitchList,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    required this.onScrubCancel,
    required this.activateBrowsedAlbum,
    required this.progress,
    required this.onSelected,
    required this.openSettings,
    required this.openList,
  });

  final PlayerController controller;
  final PageController pages;
  final GlobalKey Function(MusicCollection collection) coverKeyFor;
  final bool Function(MusicCollection collection) keepCoverAlive;
  final ValueChanged<int> onPageChanged;
  final bool coverPressed;
  final bool showingSwitchList;
  final VoidCallback onScrubStart;
  final void Function(double delta, Duration timestamp) onScrubUpdate;
  final VoidCallback onScrubEnd;
  final VoidCallback onScrubCancel;
  final VoidCallback activateBrowsedAlbum;
  final double progress;
  final ValueChanged<LibraryKind> onSelected;
  final Future<void> Function() openSettings;
  final Future<void> Function() openList;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final wheelExpanded = screenSize.height >= 700;
    final wheelSide = math.max(24.0, (screenSize.width - 220) / 2);
    return IgnorePointer(
      ignoring: progress > 0,
      child: Column(
        children: [
          Opacity(
            opacity: 1 - progress,
            child: _Header(
              selected: controller.kind,
              onSelected: onSelected,
              openSettings: openSettings,
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _HorizontalSwipeRegion(
                  onSwipe: openList,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) => onScrubStart(),
                    onVerticalDragUpdate: (details) => onScrubUpdate(
                      -details.delta.dy,
                      WidgetsBinding.instance.currentSystemFrameTimeStamp,
                    ),
                    onVerticalDragEnd: (_) => onScrubEnd(),
                    onVerticalDragCancel: onScrubCancel,
                    child: Opacity(
                      opacity: 1 - progress,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          IgnorePointer(
                            ignoring: showingSwitchList,
                            child: Opacity(
                              opacity: showingSwitchList ? 0 : 1,
                              child: _CoverFlow(
                                controller: controller,
                                pages: pages,
                                coverKeyFor: coverKeyFor,
                                keepCoverAlive: keepCoverAlive,
                                onPageChanged: onPageChanged,
                              ),
                            ),
                          ),
                          if (showingSwitchList)
                            _AlbumSwitchList(
                              controller: controller,
                              onActivate: activateBrowsedAlbum,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: wheelSide,
                  right: wheelSide,
                  bottom: wheelExpanded ? 156 : 180,
                  height: wheelExpanded ? 176 : 56,
                  child: _CoverWheelRegion(
                    key: const Key('cover-wheel'),
                    onStart: onScrubStart,
                    onUpdate: onScrubUpdate,
                    onEnd: onScrubEnd,
                    onCancel: onScrubCancel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverWheelRegion extends StatefulWidget {
  const _CoverWheelRegion({
    super.key,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final VoidCallback onStart;
  final void Function(double delta, Duration timestamp) onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  State<_CoverWheelRegion> createState() => _CoverWheelRegionState();
}

class _CoverWheelRegionState extends State<_CoverWheelRegion> {
  Offset? _startPosition;
  Axis? _axis;
  bool _scrubbing = false;

  void _start(PointerDownEvent event) {
    _startPosition = event.localPosition;
    _axis = null;
    _scrubbing = false;
  }

  void _move(PointerMoveEvent event) {
    final start = _startPosition;
    if (start == null) return;
    final delta = event.localPosition - start;
    _axis ??= delta.distance <= kTouchSlop
        ? null
        : (delta.dx.abs() >= delta.dy.abs() ? Axis.horizontal : Axis.vertical);
    if (_axis != Axis.vertical) return;
    if (!_scrubbing) {
      _scrubbing = true;
      widget.onStart();
      return;
    }
    widget.onUpdate(
      -event.delta.dy,
      WidgetsBinding.instance.currentSystemFrameTimeStamp,
    );
  }

  void _finish({required bool cancelled}) {
    _startPosition = null;
    _axis = null;
    if (_scrubbing) (cancelled ? widget.onCancel : widget.onEnd)();
    _scrubbing = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: const Key('cover-scrubber'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _start,
      onPointerMove: _move,
      onPointerUp: (_) => _finish(cancelled: false),
      onPointerCancel: (_) => _finish(cancelled: true),
    );
  }
}

class _ExpandingCover extends StatelessWidget {
  const _ExpandingCover({
    required this.start,
    required this.end,
    required this.progress,
    required this.collection,
    required this.fallbackColor,
  });

  final Rect start;
  final Rect end;
  final double progress;
  final MusicCollection collection;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    final rect = Rect.lerp(start, end, progress)!;
    final fade = ((progress - .72) / .28).clamp(0.0, 1.0);
    return Positioned.fromRect(
      key: const Key('cover-expansion'),
      rect: rect,
      child: IgnorePointer(
        child: Opacity(
          opacity: 1 - fade,
          child: DecoratedBox(
            decoration: BoxDecoration(color: fallbackColor),
            child: collection.coverUrl.isEmpty
                ? Center(
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      size: 72,
                      color: Colors.white.withValues(alpha: .82),
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: collection.coverUrl,
                    httpHeaders: neteaseImageHeaders,
                    cacheManager: PersistentCoverCache.instance,
                    fit: BoxFit.cover,
                  ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.selected,
    required this.onSelected,
    required this.openSettings,
  });

  final LibraryKind selected;
  final ValueChanged<LibraryKind> onSelected;
  final Future<void> Function() openSettings;

  @override
  Widget build(BuildContext context) {
    const labels = {
      LibraryKind.album: '专辑',
      LibraryKind.playlist: '歌单',
      LibraryKind.podcast: '播客',
    };
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: const Key('library-header'),
      height: 68,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 56,
            right: 56,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                key: const Key('category-tabs'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in LibraryKind.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: InkWell(
                        onTap: () => onSelected(item),
                        borderRadius: BorderRadius.circular(18),
                        child: AnimatedContainer(
                          key: Key('category-${item.name}'),
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected == item ? scheme.primary : null,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            labels[item]!,
                            style: TextStyle(
                              color: selected == item
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              shadows: selected == item
                                  ? _categoryOutlineShadows
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                key: const Key('settings-menu'),
                onPressed: () => openSettings(),
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: '设置',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullscreenTrackList extends StatelessWidget {
  const _FullscreenTrackList({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final collection = controller.visible[controller.browsedIndex];
    return Material(
      key: const Key('fullscreen-track-list'),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Container(
            key: const Key('collection-title'),
            constraints: BoxConstraints(
              minHeight: 100,
              maxHeight: math.max(
                100,
                math.min(220, MediaQuery.sizeOf(context).height * .35),
              ),
            ),
            child: SingleChildScrollView(
              child: Padding(
                key: const Key('collection-title-padding'),
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 5),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        collection.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (collection.subtitle.isNotEmpty) ...[
                        const SizedBox(
                          key: Key('collection-subtitle-gap'),
                          height: 10,
                        ),
                        Text(
                          collection.subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: _TrackList(controller: controller)),
        ],
      ),
    );
  }
}

class _RetainedCoverPage extends StatefulWidget {
  const _RetainedCoverPage({required this.keepAlive, required this.child});

  final bool keepAlive;
  final Widget child;

  @override
  State<_RetainedCoverPage> createState() => _RetainedCoverPageState();
}

class _RetainedCoverPageState extends State<_RetainedCoverPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void didUpdateWidget(_RetainedCoverPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _HorizontalSwipeRegion extends StatefulWidget {
  const _HorizontalSwipeRegion({required this.onSwipe, required this.child});

  final Future<void> Function() onSwipe;
  final Widget child;

  @override
  State<_HorizontalSwipeRegion> createState() => _HorizontalSwipeRegionState();
}

class _HorizontalSwipeRegionState extends State<_HorizontalSwipeRegion> {
  Offset? _start;
  Axis? _axis;

  void _move(PointerMoveEvent event) {
    final start = _start;
    if (start == null || _axis != null) return;
    final delta = event.position - start;
    if (delta.distance <= kTouchSlop) return;
    _axis = delta.dx.abs() >= delta.dy.abs() ? Axis.horizontal : Axis.vertical;
  }

  void _finish(PointerUpEvent event) {
    final start = _start;
    _start = null;
    final axis = _axis;
    _axis = null;
    if (start == null) return;
    final delta = event.position - start;
    if (axis == Axis.horizontal && delta.dx.abs() > 32) {
      widget.onSwipe();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _start = event.position;
        _axis = null;
      },
      onPointerMove: _move,
      onPointerUp: _finish,
      onPointerCancel: (_) {
        _start = null;
        _axis = null;
      },
      child: widget.child,
    );
  }
}

class _CoverTapRegion extends StatefulWidget {
  const _CoverTapRegion({required this.onTap, required this.child});

  final void Function(Offset position, bool activate) onTap;
  final Widget child;

  @override
  State<_CoverTapRegion> createState() => _CoverTapRegionState();
}

class _CoverTapRegionState extends State<_CoverTapRegion> {
  Offset? pointerDownPosition;
  Offset? lastTapPosition;
  Duration? lastTapTime;
  bool pointerMoved = false;

  void _pointerDown(PointerDownEvent event) {
    pointerDownPosition = event.position;
    pointerMoved = false;
  }

  void _pointerMove(PointerMoveEvent event) {
    final start = pointerDownPosition;
    if (start != null && (event.position - start).distance > kTouchSlop) {
      pointerMoved = true;
      lastTapPosition = null;
      lastTapTime = null;
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (pointerMoved || pointerDownPosition == null) return;
    final doubleTap =
        lastTapTime != null &&
        event.timeStamp - lastTapTime! <= kDoubleTapTimeout &&
        lastTapPosition != null &&
        (event.position - lastTapPosition!).distance <= kDoubleTapSlop;
    widget.onTap(event.position, doubleTap);
    lastTapPosition = doubleTap ? null : event.position;
    lastTapTime = doubleTap ? null : event.timeStamp;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: (_) {
        pointerDownPosition = null;
        pointerMoved = true;
        lastTapPosition = null;
        lastTapTime = null;
      },
      child: widget.child,
    );
  }
}

class _AlbumSwitchList extends StatelessWidget {
  const _AlbumSwitchList({required this.controller, required this.onActivate});

  static const rowExtent = 76.0;

  final PlayerController controller;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = controller.browsedIndex;
    final first = math.max(0, selectedIndex - 4);
    final last = math.min(controller.visible.length - 1, selectedIndex + 4);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final center = constraints.maxHeight / 2;
            return _CoverTapRegion(
              onTap: (_, activate) {
                if (activate) onActivate();
              },
              child: Stack(
                key: const Key('album-switch-list'),
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: center - rowExtent / 2 + 4,
                    height: rowExtent - 8,
                    child: DecoratedBox(
                      key: const Key('album-switch-selection-band'),
                      decoration: BoxDecoration(
                        color: scheme.inverseSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  for (var index = first; index <= last; index++)
                    TweenAnimationBuilder<double>(
                      key: ValueKey('album-switch-entry-$index'),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      builder: (context, entry, child) {
                        final entryDistance =
                            constraints.maxHeight / 2 + rowExtent;
                        final entryOffset = index < selectedIndex
                            ? -entryDistance * (1 - entry)
                            : index > selectedIndex
                            ? entryDistance * (1 - entry)
                            : 0.0;
                        return AnimatedPositioned(
                          key: Key('album-switch-position-$index'),
                          left: 0,
                          right: 0,
                          top:
                              center -
                              rowExtent / 2 +
                              (index - selectedIndex) * rowExtent +
                              entryOffset,
                          height: rowExtent,
                          duration: const Duration(milliseconds: 90),
                          curve: Curves.easeOut,
                          child: child!,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: DecoratedBox(
                          key: index == selectedIndex
                              ? Key('album-switch-selected-$index')
                              : null,
                          decoration: const BoxDecoration(
                            color: Colors.transparent,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              key: Key('album-switch-row-$index'),
                              children: [
                                SizedBox.square(
                                  key: Key('album-switch-cover-$index'),
                                  dimension: 52,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: _AlbumSwitchCover(
                                      collection: controller.visible[index],
                                      fallbackColor: _fallbackCoverColor(index),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: MediaQuery.withClampedTextScaling(
                                    maxScaleFactor: 1.5,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          controller.visible[index].title,
                                          key: Key('album-switch-title-$index'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: index == selectedIndex
                                                    ? scheme.onInverseSurface
                                                    : scheme.onSurface,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          controller.visible[index].subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: index == selectedIndex
                                                    ? scheme.onInverseSurface
                                                          .withValues(
                                                            alpha: .72,
                                                          )
                                                    : scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AlbumSwitchCover extends StatelessWidget {
  const _AlbumSwitchCover({
    required this.collection,
    required this.fallbackColor,
  });

  final MusicCollection collection;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    if (collection.coverUrl.isEmpty) {
      return ColoredBox(
        color: fallbackColor,
        child: const Icon(
          Icons.graphic_eq_rounded,
          color: Colors.white,
          size: 28,
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: collection.coverUrl,
      httpHeaders: neteaseImageHeaders,
      cacheManager: PersistentCoverCache.instance,
      memCacheWidth: math.min(
        256,
        (52 * MediaQuery.devicePixelRatioOf(context)).ceil(),
      ),
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      fit: BoxFit.cover,
    );
  }
}

class _CoverFlow extends StatelessWidget {
  const _CoverFlow({
    required this.controller,
    required this.pages,
    required this.coverKeyFor,
    required this.keepCoverAlive,
    required this.onPageChanged,
  });

  final PlayerController controller;
  final PageController pages;
  final GlobalKey Function(MusicCollection collection) coverKeyFor;
  final bool Function(MusicCollection collection) keepCoverAlive;
  final ValueChanged<int> onPageChanged;

  int? _coverAt(Offset globalPosition) {
    final firstIndex = controller.browsedIndex;
    final lastIndex = controller.browsedIndex;
    for (var index = firstIndex; index >= lastIndex; index--) {
      final box =
          coverKeyFor(
                controller.visible[index],
              ).currentContext?.findRenderObject()
              as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.getTransformTo(null).determinant() == 0) continue;
      if ((Offset.zero & box.size).contains(
        box.globalToLocal(globalPosition),
      )) {
        return index;
      }
    }
    return null;
  }

  void _handleCoverTap(Offset globalPosition, {required bool activate}) {
    final index = _coverAt(globalPosition);
    if (index == null) return;
    if (index == controller.browsedIndex) {
      if (activate) controller.activateCentered(index);
      return;
    }
    pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.hasCollections) {
      return Center(
        child: Text(
          '尚未登录或暂无收藏',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }
    return _CoverTapRegion(
      onTap: (position, activate) =>
          _handleCoverTap(position, activate: activate),
      child: PageView.builder(
        key: const ValueKey('covers'),
        clipBehavior: Clip.none,
        reverse: true,
        physics: const NeverScrollableScrollPhysics(),
        controller: pages,
        itemCount: controller.visible.length,
        onPageChanged: onPageChanged,
        itemBuilder: (context, index) => _RetainedCoverPage(
          keepAlive: keepCoverAlive(controller.visible[index]),
          child: AnimatedBuilder(
            animation: pages,
            builder: (context, child) {
              final page = pages.hasClients && pages.position.haveDimensions
                  ? pages.page ?? controller.browsedIndex.toDouble()
                  : controller.browsedIndex.toDouble();
              final distance = index - page;
              final normalizedDistance = math.min(distance.abs(), 1.0);
              final positionProgress = math.sin(
                normalizedDistance * math.pi / 2,
              );
              final transformProgress = Curves.easeOutCubic.transform(
                normalizedDistance,
              );
              final sideAngle = _sideCoverAngle;
              final scale = 1 - (1 - _sideCoverScale) * transformProgress;
              final viewportWidth =
                  pages.hasClients && pages.position.haveDimensions
                  ? pages.position.viewportDimension
                  : MediaQuery.sizeOf(context).width;
              const firstSideOffset = _firstSideCoverOffset;
              const sideStep = _sideCoverStep;
              final showCover = index == page.round();
              final offsetFraction = distance.abs() <= 1
                  ? firstSideOffset * positionProgress
                  : firstSideOffset + (distance.abs() - 1) * sideStep;
              final visualOffset =
                  offsetFraction * viewportWidth * -distance.sign;
              final layoutOffset =
                  -distance * viewportWidth * _coverViewportFraction;
              return Transform.translate(
                offset: Offset(visualOffset - layoutOffset, 0),
                child: Opacity(
                  key: Key('cover-visibility-$index'),
                  opacity: showCover ? 1 : 0,
                  child: Transform(
                    key: Key('cover-transform-$index'),
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, .0012)
                      ..rotateY(-distance.sign * sideAngle * transformProgress)
                      ..scaleByDouble(scale, scale, 1, 1),
                    child: child,
                  ),
                ),
              );
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scaler = MediaQuery.textScalerOf(context);
                final captionHeight = 86 + scaler.scale(30) + scaler.scale(18);
                final coverSize = math.max(
                  0.0,
                  math.min(
                    MediaQuery.sizeOf(context).width * _coverWidthFraction - 16,
                    constraints.maxHeight - 180 - captionHeight,
                  ),
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 180),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: coverSize,
                          child: OverflowBox(
                            minWidth: coverSize,
                            maxWidth: coverSize,
                            child: SizedBox.square(
                              key: Key('cover-art-$index'),
                              dimension: coverSize,
                              child: KeyedSubtree(
                                key: coverKeyFor(controller.visible[index]),
                                child: DecoratedBox(
                                  key: Key('cover-surface-$index'),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        _fallbackCoverColor(index),
                                        _fallbackCoverColor(
                                          index,
                                        ).withValues(alpha: .55),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: .22,
                                        ),
                                        blurRadius: 28,
                                        offset: const Offset(0, 16),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child:
                                        controller
                                            .visible[index]
                                            .coverUrl
                                            .isEmpty
                                        ? Center(
                                            child: Icon(
                                              Icons.graphic_eq_rounded,
                                              size: 72,
                                              color: Colors.white.withValues(
                                                alpha: .82,
                                              ),
                                            ),
                                          )
                                        : CachedNetworkImage(
                                            imageUrl: controller
                                                .visible[index]
                                                .coverUrl,
                                            httpHeaders: neteaseImageHeaders,
                                            cacheManager:
                                                PersistentCoverCache.instance,
                                            memCacheWidth: math.max(
                                              1,
                                              math.min(
                                                1024,
                                                (coverSize *
                                                        MediaQuery.devicePixelRatioOf(
                                                          context,
                                                        ))
                                                    .ceil(),
                                              ),
                                            ),
                                            fadeInDuration: Duration.zero,
                                            fadeOutDuration: Duration.zero,
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                            height: double.infinity,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: scaler.scale(30) + scaler.scale(18),
                          child: OverflowBox(
                            minWidth: coverSize,
                            maxWidth: coverSize,
                            child: SizedBox(
                              key: Key('cover-caption-$index'),
                              width: coverSize,
                              child: Column(
                                children: [
                                  Text(
                                    controller.visible[index].title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    controller.visible[index].subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        const SizedBox(height: 36),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

const _categoryOutlineShadows = [
  Shadow(color: Color(0x99000000), offset: Offset(-.5, -.5)),
  Shadow(color: Color(0x99000000), offset: Offset(0, -.5)),
  Shadow(color: Color(0x99000000), offset: Offset(.5, -.5)),
  Shadow(color: Color(0x99000000), offset: Offset(-.5, 0)),
  Shadow(color: Color(0x99000000), offset: Offset(.5, 0)),
  Shadow(color: Color(0x99000000), offset: Offset(-.5, .5)),
  Shadow(color: Color(0x99000000), offset: Offset(0, .5)),
  Shadow(color: Color(0x99000000), offset: Offset(.5, .5)),
];

Color _fallbackCoverColor(int index) => Color.lerp(
  const Color(0xffe5473e),
  const Color(0xff377f78),
  math.min(index / 4, 1),
)!;

class _TrackList extends StatelessWidget {
  const _TrackList({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loadingTracks) {
      return const Center(child: CircularProgressIndicator());
    }
    final collection = controller.visible[controller.browsedIndex];
    if (collection.tracks.isEmpty) {
      return const Center(child: Text('暂无可播放曲目'));
    }
    return ListView.separated(
      key: const ValueKey('tracks'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 210),
      itemCount: collection.tracks.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .1),
      ),
      itemBuilder: (context, index) {
        final track = collection.tracks[index];
        final active =
            controller.playingCollection.id == collection.id &&
            controller.playingCollection.kind == collection.kind &&
            controller.trackIndex == index;
        final progress = active ? controller.progress.clamp(0.0, 1.0) : 0.0;
        return DecoratedBox(
          key: Key('track-row-$index'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary.withValues(alpha: .2),
                Theme.of(context).colorScheme.primary.withValues(alpha: .2),
                Colors.transparent,
                Colors.transparent,
              ],
              stops: [0, progress, progress, 1],
            ),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(
              width: 34,
              child: Text(
                '${index + 1} ',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            title: Text(track.title),
            subtitle: Text(track.artist),
            trailing: const Icon(Icons.more_horiz),
            onTap: () => controller.activateTrack(collection, index),
          ),
        );
      },
    );
  }
}
