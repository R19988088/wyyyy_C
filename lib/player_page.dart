import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'cover_scrubber.dart';
import 'player.dart';
import 'services/media_cache.dart';
import 'widgets/glass_player.dart';

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
  bool pageDragActive = false;

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
    pages = PageController(viewportFraction: .7935);
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
        pages = PageController(viewportFraction: .7935, initialPage: index);
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
      viewportFraction: .7935,
      initialPage: controller.browsedIndex,
    );
  }

  Future<void> _openList() async {
    if (listMode) return;
    final contentBox =
        contentKey.currentContext?.findRenderObject() as RenderBox?;
    final collection = controller.visible[controller.browsedIndex];
    final coverBox =
        _coverKey(collection).currentContext?.findRenderObject() as RenderBox?;
    if (contentBox != null && coverBox != null) {
      coverStartRect =
          coverBox.localToGlobal(Offset.zero, ancestor: contentBox) &
          coverBox.size;
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
    pages = PageController(viewportFraction: .7935, initialPage: target);
    controller.browseTo(target);
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => oldPages.dispose());
  }

  void _scrubCovers(DragUpdateDetails details) {
    final step = scrubSpeed.update(
      delta: details.primaryDelta ?? 0,
      timestamp: WidgetsBinding.instance.currentSystemFrameTimeStamp,
    );
    if (step == null) return;
    final target = (controller.browsedIndex + step).clamp(
      0,
      controller.visible.length - 1,
    );
    if (target == controller.browsedIndex) return;
    controller.browseTo(target);
    pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _browseTo(int index) {
    controller.browseTo(index);
    _retainCover(controller.visible[controller.browsedIndex]);
  }

  void _setScrubberActive(bool active) {
    scrubSpeed.reset();
    if (scrubberActive == active) return;
    setState(() => scrubberActive = active);
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
      pages = PageController(viewportFraction: .7935, initialPage: start);
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
                            coverSwitching: scrubberActive || pageDragActive,
                            onPageDragStart: () => _setPageDragActive(true),
                            onPageDragEnd: () => _setPageDragActive(false),
                            onScrubStart: () => _setScrubberActive(true),
                            onScrubUpdate: _scrubCovers,
                            onScrubEnd: () => _setScrubberActive(false),
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
    required this.onPageDragStart,
    required this.onPageDragEnd,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
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
  final VoidCallback onPageDragStart;
  final VoidCallback onPageDragEnd;
  final VoidCallback onScrubStart;
  final ValueChanged<DragUpdateDetails> onScrubUpdate;
  final VoidCallback onScrubEnd;
  final double progress;
  final ValueChanged<LibraryKind> onSelected;
  final Future<void> Function() openSettings;
  final Future<void> Function() openList;

  @override
  Widget build(BuildContext context) {
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
                        details.primaryVelocity != 0) {
                      openList();
                    }
                  },
                  child: Opacity(
                    opacity: 1 - progress,
                    child: AnimatedScale(
                      key: const Key('cover-switch-scale'),
                      scale: coverSwitching ? .5 : 1,
                      duration: Duration(
                        milliseconds: coverSwitching ? 110 : 260,
                      ),
                      curve: Curves.easeOutCubic,
                      child: _CoverFlow(
                        controller: controller,
                        pages: pages,
                        coverKeyFor: coverKeyFor,
                        keepCoverAlive: keepCoverAlive,
                        onPageChanged: onPageChanged,
                        onDragStart: onPageDragStart,
                        onDragEnd: onPageDragEnd,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 180,
                  height: 56,
                  child: GestureDetector(
                    key: const Key('cover-scrubber'),
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: (_) => onScrubStart(),
                    onHorizontalDragUpdate: onScrubUpdate,
                    onHorizontalDragEnd: (_) => onScrubEnd(),
                    onHorizontalDragCancel: onScrubEnd,
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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

class _CoverFlow extends StatelessWidget {
  const _CoverFlow({
    required this.controller,
    required this.pages,
    required this.coverKeyFor,
    required this.keepCoverAlive,
    required this.onPageChanged,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final PlayerController controller;
  final PageController pages;
  final GlobalKey Function(MusicCollection collection) coverKeyFor;
  final bool Function(MusicCollection collection) keepCoverAlive;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

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
                final distance = (index - page).clamp(-1.0, 1.0);
                final scale = 1 - distance.abs() * .28;
                return Opacity(
                  opacity: 1 - distance.abs() * .28,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, .0012)
                      ..rotateY(-distance * .18)
                      ..scaleByDouble(scale, scale, 1, 1),
                    child: child,
                  ),
                );
              },
              child: GestureDetector(
                onTap: index == controller.browsedIndex
                    ? null
                    : () => pages.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      ),
                onDoubleTap: index == controller.browsedIndex
                    ? () => controller.activateCentered(index)
                    : null,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scaler = MediaQuery.textScalerOf(context);
                    final captionHeight =
                        78 + scaler.scale(28) + scaler.scale(18);
                    final coverSize = math.max(
                      0.0,
                      math.min(
                        constraints.maxWidth - 16,
                        constraints.maxHeight - 180 - captionHeight,
                      ),
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 180),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
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
                            const SizedBox(height: 18),
                            Text(
                              controller.visible[index].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              controller.visible[index].subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 56),
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
