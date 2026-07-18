import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../player.dart';
import '../services/media_cache.dart';

class GlassPlayer extends StatelessWidget {
  const GlassPlayer({
    super.key,
    required this.controller,
    required this.onMetadataDoubleTap,
  });

  final PlayerController controller;
  final VoidCallback onMetadataDoubleTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('player-glass-frame'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(width: 1, color: Colors.black.withValues(alpha: .3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: GlassContainer(
          shape: const LiquidRoundedSuperellipse(borderRadius: 29),
          settings: LiquidGlassSettings(
            glassColor: scheme.surfaceContainer.withValues(alpha: .12),
            blur: 2,
            thickness: 44.2,
            chromaticAberration: .44,
            lightIntensity: .828,
            ambientStrength: .1,
            refractiveIndex: 1.19,
            saturation: 1.35,
            glowIntensity: .9,
            specularSharpness: GlassSpecularSharpness.sharp,
          ),
          quality: GlassQuality.premium,
          useOwnLayer: true,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        key: const Key('player-metadata'),
                        onDoubleTap: onMetadataDoubleTap,
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child:
                                  (controller.track.coverUrl ??
                                          controller.playingCollection.coverUrl)
                                      .isEmpty
                                  ? const Icon(
                                      Icons.music_note_rounded,
                                      color: Colors.white,
                                    )
                                  : CachedNetworkImage(
                                      imageUrl:
                                          controller.track.coverUrl ??
                                          controller.playingCollection.coverUrl,
                                      httpHeaders: neteaseImageHeaders,
                                      cacheManager:
                                          PersistentCoverCache.instance,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    controller.track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    controller.track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: IconButton(
                        key: const Key('sleep-timer'),
                        tooltip: controller.sleepTimerMinutes == 0
                            ? '定时停止播放'
                            : '${controller.sleepTimerMinutes} 分钟后停止播放',
                        onPressed: controller.cycleSleepTimer,
                        icon: controller.sleepTimerMinutes == 0
                            ? const Icon(Icons.hourglass_empty_rounded)
                            : Text(
                                '${controller.sleepTimerMinutes}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  key: const Key('player-controls'),
                  height: 50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: controller.previous,
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      const SizedBox(width: 18),
                      IconButton.filled(
                        onPressed: controller.togglePlaying,
                        icon: Icon(
                          controller.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      const SizedBox(width: 18),
                      IconButton(
                        onPressed: controller.next,
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _formatTime(
                        controller.track.duration * controller.progress,
                      ),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 4,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          key: const Key('player-progress'),
                          value: controller.progress,
                          onChanged: controller.seek,
                        ),
                      ),
                    ),
                    Text(
                      _formatTime(controller.track.duration.toDouble()),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(double seconds) {
    final value = seconds.isFinite ? seconds.round().clamp(0, 359999) : 0;
    return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
  }
}
