import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'cover_scrubber.dart';
import 'player.dart';
import 'services/media_cache.dart';
import 'widgets/glass_player.dart';

const _coverViewportFraction = .16;
const _coverWidthFraction = .8;
const _firstSideCoverOffset = .423;
const _sideCoverStep = .068;
const _dragFirstSideCoverOffset = .477;
const _dragSideCoverStep = .14;
const _sideCoverScale = .62;
const _sideCoverAngle = 1.45;
const _dragNearSideCoverAngle = 1.16;
const _dragFarSideCoverAngle = 1.46;

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
  bool listSwipeActive = false;
  bool scrubberActive = false;
  bool pageDragActive = false;
  double edgeOverscroll = 0;

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

  void _prepareListTransition() {
    if (listMode) return;
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
  }

  Future<void> _openList() async {
    if (listMode) return;
    _prepareListTransition();
    await modeTransition.animateTo(
      1,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _beginListSwipe() {
    _prepareListTransition();
    if (!listMode) return;
    setState(() => listSwipeActive = true);
  }

  void _updateListSwipe(double distance) {
    if (!listSwipeActive) return;
    final progress = (distance / (MediaQuery.sizeOf(context).height * .72))
        .clamp(0.0, 1.0);
    modeTransition.value = progress;
  }

  Future<void> _endListSwipe() async {
    if (!listSwipeActive) return;
    final complete = modeTransition.value >= .18;
    setState(() => listSwipeActive = false);
    if (complete) {
      await modeTransition.animateTo(1, curve: Curves.easeOutCubic);
      return;
    }
    await modeTransition.animateBack(0, curve: Curves.easeOutCubic);
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

  Future<void> _closeList() async {
    if (!listMode || modeTransition.status == AnimationStatus.reverse) return;
    _restoreListOriginPage();
    await modeTransition.animateBack(0, curve: Curves.easeOutCubic);
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
    final last = count - 1;
    var remaining = delta;
    if (edgeOverscroll != 0) {
      final next = edgeOverscroll + remaining;
      if (edgeOverscroll.sign == next.sign && next != 0) {
        _setEdgeOverscroll(next);
        scrubSpeed.reset();
        return;
      }
      remaining = next;
      _setEdgeOverscroll(0);
      scrubSpeed.reset();
    }
    final atStart = controller.browsedIndex == 0 && remaining < 0;
    final atEnd = controller.browsedIndex == last && remaining > 0;
    if (atStart || atEnd) {
      _setEdgeOverscroll(remaining);
      scrubSpeed.reset();
      return;
    }
    final step = scrubSpeed.update(delta: remaining, timestamp: timestamp);
    if (step == null) return;
    final target = (controller.browsedIndex + step).clamp(0, count - 1);
    if (target == controller.browsedIndex) return;
    controller.browseTo(target);
    pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _setEdgeOverscroll(double value) {
    final coverBox =
        _coverKey(
              controller.visible[controller.browsedIndex],
            ).currentContext?.findRenderObject()
            as RenderBox?;
    final fallbackWidth =
        MediaQuery.sizeOf(context).width * _coverWidthFraction - 16;
    final limit = math.max(0.0, (coverBox?.size.width ?? fallbackWidth) * .15);
    final next = value.clamp(-limit, limit);
    if (next == edgeOverscroll) return;
    setState(() => edgeOverscroll = next);
  }

  void _browseTo(int index) {
    controller.browseTo(index);
    _retainCover(controller.visible[controller.browsedIndex]);
  }

  void _setScrubberActive(bool active) {
    scrubSpeed.reset();
    if (scrubberActive == active && (active || edgeOverscroll == 0)) return;
    setState(() {
      scrubberActive = active;
      if (!active) edgeOverscroll = 0;
    });
  }

  void _setPageDragActive(bool active) {
    if (pageDragActive == active) return;
    setState(() => pageDragActive = active);
  }

  Future<void> _returnToPlaying() async {
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
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
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
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !listMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && listMode) _closeList();
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
                    final progress = modeTransition.value;
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
                            coverSwitching: pageDragActive,
                            coverPressed: scrubberActive,
                            edgeOffsetFraction:
                                edgeOverscroll /
                                MediaQuery.sizeOf(context).width,
                            onPageDragStart: () => _setPageDragActive(true),
                            onPageDragEnd: () => _setPageDragActive(false),
                            onScrubStart: () => _setScrubberActive(true),
                            onScrubUpdate: _scrubCovers,
                            onScrubEnd: () => _setScrubberActive(false),
                            onVerticalStart: _beginListSwipe,
                            onVerticalUpdate: _updateListSwipe,
                            onVerticalEnd: _endListSwipe,
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
                              child: _FullscreenTrackList(
                                controller: controller,
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
    required this.coverSwitching,
    required this.coverPressed,
    required this.edgeOffsetFraction,
    required this.onPageDragStart,
    required this.onPageDragEnd,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
    required this.onVerticalStart,
    required this.onVerticalUpdate,
    required this.onVerticalEnd,
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
  final bool coverSwitching;
  final bool coverPressed;
  final double edgeOffsetFraction;
  final VoidCallback onPageDragStart;
  final VoidCallback onPageDragEnd;
  final VoidCallback onScrubStart;
  final void Function(double delta, Duration timestamp) onScrubUpdate;
  final VoidCallback onScrubEnd;
  final VoidCallback onVerticalStart;
  final ValueChanged<double> onVerticalUpdate;
  final VoidCallback onVerticalEnd;
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
                GestureDetector(
                  onVerticalDragEnd: (details) {
                    if (details.primaryVelocity != null &&
                        details.primaryVelocity! < 0) {
                      openList();
                    }
                  },
                  child: Opacity(
                    opacity: 1 - progress,
                    child: AnimatedSlide(
                      key: const Key('cover-edge-slide'),
                      offset: Offset(edgeOffsetFraction, 0),
                      duration: coverPressed
                          ? Duration.zero
                          : const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      child: AnimatedScale(
                        key: const Key('cover-switch-scale'),
                        scale: coverPressed ? .72 : (coverSwitching ? .8 : 1),
                        duration: Duration(
                          milliseconds: coverPressed
                              ? 180
                              : (coverSwitching ? 110 : 520),
                        ),
                        curve: coverPressed
                            ? Curves.easeOutBack
                            : (coverSwitching
                                  ? Curves.easeOutCubic
                                  : Curves.easeOutBack),
                        child: _CoverFlow(
                          controller: controller,
                          pages: pages,
                          expandedSides: coverPressed || coverSwitching,
                          coverKeyFor: coverKeyFor,
                          keepCoverAlive: keepCoverAlive,
                          onPageChanged: onPageChanged,
                          onDragStart: onPageDragStart,
                          onDragEnd: onPageDragEnd,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final scaler = MediaQuery.textScalerOf(context);
                        final textHeight = scaler.scale(30) + scaler.scale(18);
                        final captionHeight = 86 + textHeight;
                        final coverSize = math.max(
                          0.0,
                          math.min(
                            MediaQuery.sizeOf(context).width *
                                    _coverWidthFraction -
                                16,
                            constraints.maxHeight - 180 - captionHeight,
                          ),
                        );
                        final contentHeight =
                            coverSize + 18 + textHeight + 32 + 36;
                        final indicatorTop =
                            (constraints.maxHeight - 180 - contentHeight) / 2 +
                            coverSize +
                            18 +
                            textHeight;
                        return Stack(
                          children: [
                            Positioned(
                              left: (constraints.maxWidth - coverSize) / 2,
                              top: indicatorTop,
                              width: coverSize,
                              child: _CoverScrollIndicator(
                                key: const Key('cover-scrollbar'),
                                visible: coverPressed || coverSwitching,
                                index: controller.browsedIndex,
                                count: controller.visible.length,
                                width: coverSize,
                              ),
                            ),
                          ],
                        );
                      },
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
                    onVerticalStart: onVerticalStart,
                    onVerticalUpdate: onVerticalUpdate,
                    onVerticalEnd: onVerticalEnd,
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

enum _CoverInputMode { pending, wheel, verticalUp, verticalDown }

class _CoverWheelRegion extends StatefulWidget {
  const _CoverWheelRegion({
    super.key,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onVerticalStart,
    required this.onVerticalUpdate,
    required this.onVerticalEnd,
  });

  final VoidCallback onStart;
  final void Function(double delta, Duration timestamp) onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onVerticalStart;
  final ValueChanged<double> onVerticalUpdate;
  final VoidCallback onVerticalEnd;

  @override
  State<_CoverWheelRegion> createState() => _CoverWheelRegionState();
}

class _CoverWheelRegionState extends State<_CoverWheelRegion> {
  Offset? _previousPosition;
  Offset? _startPosition;
  _CoverInputMode _mode = _CoverInputMode.pending;
  bool _circularMoved = false;
  bool _sampled = false;
  bool _pressed = false;

  void _start(PointerDownEvent event) {
    _startPosition = event.localPosition;
    _previousPosition = event.localPosition;
    _mode = _CoverInputMode.pending;
    _circularMoved = false;
    _sampled = false;
    _pressed = true;
    widget.onStart();
  }

  void _move(PointerMoveEvent event) {
    final previous = _previousPosition;
    final start = _startPosition;
    if (previous == null || start == null) return;
    final center = (context.size ?? Size.zero).center(Offset.zero);
    final startVector = start - center;
    final previousVector = previous - center;
    final currentVector = event.localPosition - center;
    final previousRadius = previousVector.distance;
    final currentRadius = currentVector.distance;
    final radialDelta = currentRadius - previousRadius;
    var angularDelta =
        math.atan2(currentVector.dy, currentVector.dx) -
        math.atan2(previousVector.dy, previousVector.dx);
    if (angularDelta > math.pi) angularDelta -= 2 * math.pi;
    if (angularDelta < -math.pi) angularDelta += 2 * math.pi;
    final tangentialDelta = angularDelta * (previousRadius + currentRadius) / 2;
    final circular =
        previousRadius >= 24 &&
        currentRadius >= 24 &&
        tangentialDelta.abs() > radialDelta.abs();
    if (_mode == _CoverInputMode.pending) {
      final displacement = event.localPosition - start;
      if (displacement.distance < 12) return;
      final vertical = startVector.distance < 24
          ? displacement.dy.abs() > displacement.dx.abs()
          : !circular && displacement.dy.abs() > displacement.dx.abs();
      if (vertical) {
        _mode = displacement.dy < 0
            ? _CoverInputMode.verticalUp
            : _CoverInputMode.verticalDown;
        if (_mode == _CoverInputMode.verticalUp) {
          widget.onEnd();
          _pressed = false;
          widget.onVerticalStart();
        }
      } else {
        _mode = _CoverInputMode.wheel;
      }
    }
    if (_mode == _CoverInputMode.verticalUp) {
      widget.onVerticalUpdate(
        (start.dy - event.localPosition.dy).clamp(0, double.infinity),
      );
      _previousPosition = event.localPosition;
      return;
    }
    if (_mode == _CoverInputMode.verticalDown) {
      _previousPosition = event.localPosition;
      return;
    }
    _circularMoved |= circular;
    final delta = _circularMoved
        ? tangentialDelta
        : (_sampled ? event.delta.dx : 0.0);
    widget.onUpdate(delta, WidgetsBinding.instance.currentSystemFrameTimeStamp);
    _sampled = true;
    _previousPosition = event.localPosition;
  }

  void _finish() {
    final start = _startPosition;
    _startPosition = null;
    _previousPosition = null;
    final mode = _mode;
    _mode = _CoverInputMode.pending;
    _circularMoved = false;
    _sampled = false;
    if (_pressed) widget.onEnd();
    _pressed = false;
    if (mode == _CoverInputMode.verticalUp && start != null) {
      widget.onVerticalEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: const Key('cover-scrubber'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _start,
      onPointerMove: _move,
      onPointerUp: (_) => _finish(),
      onPointerCancel: (_) => _finish(),
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
      onPointerCancel: (_) => pointerMoved = true,
      child: widget.child,
    );
  }
}

class _CoverScrollIndicator extends StatelessWidget {
  const _CoverScrollIndicator({
    super.key,
    required this.visible,
    required this.index,
    required this.count,
    required this.width,
  });

  final bool visible;
  final int index;
  final int count;
  final double width;

  @override
  Widget build(BuildContext context) {
    final trackWidth = width;
    final thumbWidth = math.max(
      24.0,
      trackWidth * math.min(1.0, 3 / math.max(count, 1)),
    );
    final maxOffset = math.max(0.0, trackWidth - thumbWidth);
    final offset = count <= 1 ? 0.0 : maxOffset * index / (count - 1);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: Duration(milliseconds: visible ? 150 : 300),
      curve: Curves.easeOut,
      child: SizedBox(
        height: 32,
        child: OverflowBox(
          minWidth: width,
          maxWidth: width,
          child: SizedBox(
            width: width,
            height: 32,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                key: const Key('cover-scrollbar-track'),
                width: trackWidth,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xffd6d4d2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xffaaa59b)),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: offset,
                      top: 2,
                      bottom: 2,
                      child: Container(
                        key: const Key('cover-scrollbar-thumb'),
                        width: thumbWidth,
                        decoration: BoxDecoration(
                          color: const Color(0xff393b3d),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverFlow extends StatelessWidget {
  const _CoverFlow({
    required this.controller,
    required this.pages,
    required this.expandedSides,
    required this.coverKeyFor,
    required this.keepCoverAlive,
    required this.onPageChanged,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final PlayerController controller;
  final PageController pages;
  final bool expandedSides;
  final GlobalKey Function(MusicCollection collection) coverKeyFor;
  final bool Function(MusicCollection collection) keepCoverAlive;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  int? _coverAt(Offset globalPosition) {
    final firstIndex = expandedSides
        ? controller.visible.length - 1
        : controller.browsedIndex;
    final lastIndex = expandedSides ? 0 : controller.browsedIndex;
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
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          onDragStart();
        } else if (notification is ScrollEndNotification) {
          onDragEnd();
        }
        return false;
      },
      child: Listener(
        onPointerUp: (_) => onDragEnd(),
        onPointerCancel: (_) => onDragEnd(),
        child: _CoverTapRegion(
          onTap: (position, activate) =>
              _handleCoverTap(position, activate: activate),
          child: PageView.builder(
            key: const ValueKey('covers'),
            clipBehavior: Clip.none,
            reverse: true,
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
                  final depthProgress = (distance.abs() - 1).clamp(0.0, 1.0);
                  final sideAngle = expandedSides
                      ? _dragNearSideCoverAngle +
                            (_dragFarSideCoverAngle - _dragNearSideCoverAngle) *
                                depthProgress
                      : _sideCoverAngle;
                  final scale = 1 - (1 - _sideCoverScale) * transformProgress;
                  final viewportWidth =
                      pages.hasClients && pages.position.haveDimensions
                      ? pages.position.viewportDimension
                      : MediaQuery.sizeOf(context).width;
                  final firstSideOffset = expandedSides
                      ? _dragFirstSideCoverOffset
                      : _firstSideCoverOffset;
                  final sideStep = expandedSides
                      ? _dragSideCoverStep
                      : _sideCoverStep;
                  final showCover = expandedSides || index == page.round();
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
                          ..rotateY(
                            -distance.sign * sideAngle * transformProgress,
                          )
                          ..scaleByDouble(scale, scale, 1, 1),
                        child: child,
                      ),
                    ),
                  );
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scaler = MediaQuery.textScalerOf(context);
                    final captionHeight =
                        86 + scaler.scale(30) + scaler.scale(18);
                    final coverSize = math.max(
                      0.0,
                      math.min(
                        MediaQuery.sizeOf(context).width * _coverWidthFraction -
                            16,
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
                                                  color: Colors.white
                                                      .withValues(alpha: .82),
                                                ),
                                              )
                                            : CachedNetworkImage(
                                                imageUrl: controller
                                                    .visible[index]
                                                    .coverUrl,
                                                httpHeaders:
                                                    neteaseImageHeaders,
                                                cacheManager:
                                                    PersistentCoverCache
                                                        .instance,
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
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
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
