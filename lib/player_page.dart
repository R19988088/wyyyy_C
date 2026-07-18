import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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

class _PlayerPageState extends State<PlayerPage> {
  late final PlayerController controller;
  late PageController pages;
  bool listMode = false;

  @override
  void initState() {
    super.initState();
    controller = PlayerController(widget.repository)..addListener(_refresh);
    pages = PageController(viewportFraction: .69);
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
        pages = PageController(viewportFraction: .69, initialPage: index);
        controller.browseTo(index);
      }
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    pages.dispose();
    controller.removeListener(_refresh);
    controller.dispose();
    super.dispose();
  }

  void _selectKind(LibraryKind kind, {int initialPage = 0}) {
    controller.selectKind(kind);
    pages.dispose();
    pages = PageController(viewportFraction: .69, initialPage: initialPage);
  }

  Future<void> _returnToPlaying() async {
    final targetKind = controller.activeKind;
    if (controller.kind != targetKind) {
      controller.selectKind(targetKind);
      final target = controller.activeIndexInVisible();
      final start = target > 3 ? target - 3 : 0;
      pages.dispose();
      pages = PageController(viewportFraction: .69, initialPage: start);
      controller.browseTo(start);
      setState(() => listMode = false);
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
      setState(() => listMode = false);
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
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _Header(
                  selected: controller.kind,
                  onSelected: _selectKind,
                  openSettings: () async {
                    await widget.openSettings();
                    controller.reloadVisible();
                  },
                ),
                Expanded(
                  child: GestureDetector(
                    onVerticalDragEnd: (details) {
                      if (details.primaryVelocity == null) return;
                      final next = details.primaryVelocity! < 0;
                      setState(() => listMode = next);
                      if (next) controller.ensureBrowsedTracks();
                    },
                    child: NotificationListener<OverscrollNotification>(
                      onNotification: (notification) {
                        if (listMode && notification.overscroll < -8) {
                          setState(() => listMode = false);
                          return true;
                        }
                        return false;
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: listMode
                            ? _TrackList(controller: controller)
                            : _CoverFlow(controller: controller, pages: pages),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 190),
              ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
      child: Row(
        children: [
          for (final item in LibraryKind.values)
            TextButton(
              onPressed: () => onSelected(item),
              child: Text(
                labels[item]!,
                style: TextStyle(
                  fontWeight: selected == item
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            onPressed: () => openSettings(),
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
          ),
        ],
      ),
    );
  }
}

class _CoverFlow extends StatelessWidget {
  const _CoverFlow({required this.controller, required this.pages});

  final PlayerController controller;
  final PageController pages;

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
    return PageView.builder(
      key: const ValueKey('covers'),
      controller: pages,
      itemCount: controller.visible.length,
      onPageChanged: controller.browseTo,
      itemBuilder: (context, index) => AnimatedBuilder(
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
          onTap: () {
            if (index == controller.browsedIndex) {
              controller.activateCentered(index);
            } else {
              pages.animateToPage(
                index,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 34, 8, 70),
            child: Column(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _coverColor(index),
                          _coverColor(index).withValues(alpha: .55),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .22),
                          blurRadius: 28,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: controller.visible[index].coverUrl.isEmpty
                          ? Center(
                              child: Icon(
                                Icons.graphic_eq_rounded,
                                size: 72,
                                color: Colors.white.withValues(alpha: .82),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: controller.visible[index].coverUrl,
                              cacheManager: PersistentCoverCache.instance,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  controller.visible[index].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  controller.visible[index].subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _coverColor(int index) => Color.lerp(
    const Color(0xffe5473e),
    const Color(0xff377f78),
    math.min(index / 4, 1),
  )!;
}

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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      itemCount: collection.tracks.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .1),
      ),
      itemBuilder: (context, index) {
        final track = collection.tracks[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(track.title),
          subtitle: Text(track.artist),
          trailing: const Icon(Icons.more_horiz),
          onTap: () => controller.activateTrack(collection, index),
        );
      },
    );
  }
}
