import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:media_kit/media_kit.dart';

int adjacentQueueIndex(int current, int length, int delta) {
  if (length <= 0) return -1;
  return (current + delta).clamp(0, length - 1);
}

Future<WyyyyAudioHandler> initializeAudioService() {
  return AudioService.init(
    builder: WyyyyAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.r19988088.wyyyy.playback',
      androidNotificationChannelName: '云音乐播放',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidShowNotificationBadge: false,
    ),
  ).then((handler) async {
    await handler.configurePlatformAudioSession();
    return handler;
  });
}

class WyyyyAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  WyyyyAudioHandler() : _player = Player() {
    _subscriptions = [
      _player.stream.playing.listen(
        (playing) => _publishState(playing: playing),
      ),
      _player.stream.position.listen(
        (position) => _publishState(position: position),
      ),
      _player.stream.duration.listen(
        (duration) => _publishState(duration: duration),
      ),
      _player.stream.buffering.listen(
        (buffering) => _publishState(buffering: buffering),
      ),
      _player.stream.completed.listen((completed) {
        if (completed) unawaited(skipToNext());
      }),
    ];
  }

  final Player _player;
  late final List<StreamSubscription<dynamic>> _subscriptions;
  List<MediaItem> _items = const [];
  int _index = -1;
  Future<String> Function(MediaItem item)? _resolveUri;
  bool _resumeAfterInterruption = false;
  int _queueGeneration = 0;

  Player get player => _player;
  int get currentIndex => _index;

  Future<void> configurePlatformAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _subscriptions.add(
      session.becomingNoisyEventStream.listen((_) => unawaited(pause())),
    );
    _subscriptions.add(
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          _resumeAfterInterruption = _player.state.playing;
          if (_resumeAfterInterruption) unawaited(pause());
        } else if (_resumeAfterInterruption) {
          _resumeAfterInterruption = false;
          unawaited(play());
        }
      }),
    );
  }

  Future<void> setPlayableQueue(
    List<MediaItem> items, {
    required int initialIndex,
    bool autoplay = true,
    Future<String> Function(MediaItem item)? resolveUri,
  }) async {
    final generation = ++_queueGeneration;
    _items = List.unmodifiable(items);
    _resolveUri = resolveUri;
    queue.add(_items);
    if (_items.isEmpty) {
      _index = -1;
      mediaItem.add(null);
      await stop();
      return;
    }
    await _open(
      initialIndex.clamp(0, _items.length - 1),
      autoplay: autoplay,
      generation: generation,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    final target = adjacentQueueIndex(_index, _items.length, 1);
    if (target >= 0 && target != _index) {
      await _open(target, autoplay: true, generation: _queueGeneration);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.state.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    final target = adjacentQueueIndex(_index, _items.length, -1);
    if (target >= 0 && target != _index) {
      await _open(target, autoplay: true, generation: _queueGeneration);
    }
  }

  Future<void> _open(
    int index, {
    required bool autoplay,
    required int generation,
  }) async {
    final item = _items[index];
    var uri = item.extras?['uri'] as String?;
    if ((uri == null || uri.isEmpty) && _resolveUri != null) {
      uri = await _resolveUri!(item);
    }
    if (generation != _queueGeneration) {
      throw StateError('播放队列请求已过期');
    }
    if (uri == null || uri.isEmpty) throw StateError('曲目缺少播放地址');
    _index = index;
    mediaItem.add(item);
    await _player.open(Media(uri), play: autoplay);
    _publishState();
  }

  void _publishState({
    bool? playing,
    bool? buffering,
    Duration? position,
    Duration? duration,
  }) {
    final isPlaying = playing ?? _player.state.playing;
    final isBuffering = buffering ?? _player.state.buffering;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: isBuffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: isPlaying,
        updatePosition: position ?? _player.state.position,
        bufferedPosition: _player.state.buffer,
        speed: _player.state.rate,
        queueIndex: _index < 0 ? null : _index,
      ),
    );
    final current = mediaItem.value;
    final resolvedDuration = duration ?? _player.state.duration;
    if (current != null &&
        resolvedDuration > Duration.zero &&
        current.duration != resolvedDuration) {
      mediaItem.add(current.copyWith(duration: resolvedDuration));
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    return super.stop();
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
  }
}
