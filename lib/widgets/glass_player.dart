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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: GlassContainer(
        shape: LiquidRoundedSuperellipse(
          borderRadius: 30,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .24)),
        ),
        settings: LiquidGlassSettings(
          glassColor: scheme.surfaceContainer.withValues(alpha: .2),
          blur: 18,
          thickness: 26,
          chromaticAberration: .14,
          refractiveIndex: 1.14,
          saturation: 1.2,
        ),
        quality: GlassQuality.premium,
        useOwnLayer: true,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
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
                              cacheManager: PersistentCoverCache.instance,
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
                            style: const TextStyle(fontWeight: FontWeight.w700),
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
    );
  }

  String _formatTime(double seconds) {
    final value = seconds.isFinite ? seconds.round().clamp(0, 359999) : 0;
    return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
  }
}
