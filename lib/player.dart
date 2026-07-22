import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum LibraryKind { album, playlist, podcast }

@immutable
class Track {
  const Track(
    this.id,
    this.title,
    this.artist, {
    this.duration = 240,
    this.coverUrl,
  });

  final String id;
  final String title;
  final String artist;
  final int duration;
  final String? coverUrl;
}

@immutable
class MusicCollection {
  const MusicCollection(
    this.id,
    this.title,
    this.subtitle,
    this.kind,
    this.tracks, {
    this.coverUrl = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final LibraryKind kind;
  final List<Track> tracks;
  final String coverUrl;
}

abstract interface class PlayerRepository {
  List<MusicCollection> collections(LibraryKind kind);
  Future<void> reload();
  Future<void> clearCache();
}

abstract interface class PlaybackRepository implements PlayerRepository {
  Stream<PlaybackSnapshot> get playback;
  MusicCollection? get restoredCollection;
  int get restoredTrackIndex;
  Future<void> loadTracks(MusicCollection collection);
  Future<int> activate(
    MusicCollection collection, {
    int? trackIndex,
    bool autoplay = true,
  });
  Future<int> previous();
  Future<int> next();
  Future<bool> togglePlaying();
  Future<void> seek(double progress);
}

@immutable
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.playing,
    required this.trackIndex,
    required this.progress,
  });

  final bool playing;
  final int trackIndex;
  final double progress;
}

class InMemoryPlayerRepository implements PlayerRepository {
  InMemoryPlayerRepository(this._items);

  factory InMemoryPlayerRepository.demo() {
    const tracks = [
      Track('1', '晴天', '周杰伦', duration: 269),
      Track('2', '宇宙的有趣', '许嵩'),
      Track('3', '如愿', '王菲'),
    ];
    return InMemoryPlayerRepository(const [
      MusicCollection('a1', '深夜唱片', '私人收藏', LibraryKind.album, tracks),
      MusicCollection('a2', '时间的歌', '今日推荐', LibraryKind.album, tracks),
      MusicCollection('a3', '夏日入口', '2026 精选', LibraryKind.album, tracks),
      MusicCollection('p1', '我喜欢的音乐', '128 首', LibraryKind.playlist, tracks),
      MusicCollection('p2', '通勤节拍', '最近更新', LibraryKind.playlist, tracks),
      MusicCollection('d1', '无穷小亮', '最新一期', LibraryKind.podcast, tracks),
      MusicCollection('d2', '忽左忽右', '播客', LibraryKind.podcast, tracks),
    ]);
  }

  final List<MusicCollection> _items;

  @override
  List<MusicCollection> collections(LibraryKind kind) =>
      _items.where((item) => item.kind == kind).toList(growable: false);

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> reload() async {}
}

class PlayerController extends ChangeNotifier {
  PlayerController(this.repository)
    : _visible = repository.collections(LibraryKind.album) {
    final playbackRepository = repository;
    if (playbackRepository is PlaybackRepository) {
      _playbackSubscription = playbackRepository.playback.listen((snapshot) {
        playing = snapshot.playing;
        trackIndex = snapshot.trackIndex;
        progress = snapshot.progress;
        notifyListeners();
      });
      final restored = playbackRepository.restoredCollection;
      if (restored != null) {
        kind = restored.kind;
        _visible = repository.collections(restored.kind);
        _activeCollection = restored;
        browsedIndex = math.max(0, _visible.indexOf(restored));
        _browsedIndexes[restored.kind] = browsedIndex;
        playingCollectionIndex = browsedIndex;
        trackIndex = playbackRepository.restoredTrackIndex;
      }
    }
  }

  static final MusicCollection _emptyCollection = MusicCollection(
    '',
    '',
    '',
    LibraryKind.album,
    const [],
  );
  static const Track _emptyTrack = Track('', '', '', duration: 0);

  final PlayerRepository repository;
  List<MusicCollection> _visible;
  MusicCollection? _activeCollection;
  LibraryKind kind = LibraryKind.album;
  int browsedIndex = 0;
  int playingCollectionIndex = 0;
  int trackIndex = 0;
  bool playing = false;
  double progress = 0;
  StreamSubscription<PlaybackSnapshot>? _playbackSubscription;
  int _activationGeneration = 0;
  bool loadingTracks = false;
  final Map<LibraryKind, int> _browsedIndexes = {
    for (final kind in LibraryKind.values) kind: 0,
  };
  Timer? _sleepTimer;
  int sleepTimerMinutes = 0;

  List<MusicCollection> get visible =>
      _visible.isEmpty ? [_emptyCollection] : _visible;
  bool get hasCollections => _visible.isNotEmpty;
  MusicCollection get playingCollection =>
      _activeCollection ??
      (_visible.isEmpty ? _emptyCollection : _visible.first);
  Track get track {
    final tracks = playingCollection.tracks;
    return tracks.isEmpty
        ? _emptyTrack
        : tracks[trackIndex.clamp(0, tracks.length - 1)];
  }

  LibraryKind get activeKind => playingCollection.kind;

  int activeIndexInVisible() {
    final active = _activeCollection;
    if (active == null) return 0;
    final index = _visible.indexWhere(
      (item) => item.id == active.id && item.kind == active.kind,
    );
    return index < 0 ? 0 : index;
  }

  void selectKind(LibraryKind value) {
    _browsedIndexes[kind] = browsedIndex;
    kind = value;
    _visible = repository.collections(value);
    browsedIndex = (_browsedIndexes[value] ?? 0).clamp(
      0,
      math.max(0, _visible.length - 1),
    );
    final active = _activeCollection;
    final activeIndex = active == null ? -1 : _visible.indexOf(active);
    playingCollectionIndex = activeIndex < 0 ? 0 : activeIndex;
    notifyListeners();
  }

  void reloadVisible() {
    _visible = repository.collections(kind);
    browsedIndex = browsedIndex.clamp(0, math.max(0, _visible.length - 1));
    notifyListeners();
  }

  void browseTo(int index) {
    if (_visible.isEmpty) return;
    browsedIndex = index.clamp(0, _visible.length - 1);
    _browsedIndexes[kind] = browsedIndex;
    notifyListeners();
  }

  void cycleSleepTimer() {
    sleepTimerMinutes = switch (sleepTimerMinutes) {
      0 => 60,
      60 => 120,
      _ => 0,
    };
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (sleepTimerMinutes > 0) {
      _sleepTimer = Timer(Duration(minutes: sleepTimerMinutes), () {
        sleepTimerMinutes = 0;
        _sleepTimer = null;
        if (playing) togglePlaying();
        notifyListeners();
      });
    }
    notifyListeners();
  }

  bool activateCentered(int index) {
    if (_visible.isEmpty || index != browsedIndex) return false;
    final collection = _visible[index];
    final playbackRepository = repository;
    if (playbackRepository is PlaybackRepository) {
      unawaited(_activate(playbackRepository, collection, null));
    } else {
      _commitActivation(collection, index, 0, true);
    }
    return true;
  }

  Future<void> activateTrack(MusicCollection collection, int index) async {
    final playbackRepository = repository;
    if (playbackRepository is! PlaybackRepository) return;
    await _activate(playbackRepository, collection, index);
  }

  Future<void> ensureBrowsedTracks() async {
    if (_visible.isEmpty || loadingTracks) return;
    final collection = _visible[browsedIndex];
    if (collection.tracks.isNotEmpty) return;
    final playbackRepository = repository;
    if (playbackRepository is! PlaybackRepository) return;
    loadingTracks = true;
    notifyListeners();
    try {
      await playbackRepository.loadTracks(collection);
    } catch (error) {
      debugPrint('Unable to load tracks: $error');
    } finally {
      loadingTracks = false;
      notifyListeners();
    }
  }

  Future<void> _activate(
    PlaybackRepository playbackRepository,
    MusicCollection collection,
    int? requestedTrackIndex,
  ) async {
    final generation = ++_activationGeneration;
    try {
      final resolvedIndex = await playbackRepository.activate(
        collection,
        trackIndex: requestedTrackIndex,
      );
      if (generation != _activationGeneration) return;
      final index = _visible.indexWhere(
        (item) => item.id == collection.id && item.kind == collection.kind,
      );
      _commitActivation(collection, index < 0 ? 0 : index, resolvedIndex, true);
    } catch (error) {
      if (generation != _activationGeneration) return;
      debugPrint('Unable to start playback: $error');
    }
  }

  void _commitActivation(
    MusicCollection collection,
    int collectionIndex,
    int newTrackIndex,
    bool isPlaying,
  ) {
    _activeCollection = collection;
    playingCollectionIndex = collectionIndex;
    trackIndex = newTrackIndex;
    playing = isPlaying;
    progress = 0;
    notifyListeners();
  }

  void togglePlaying() {
    if (playingCollection.tracks.isEmpty && repository is PlaybackRepository) {
      return;
    }
    playing = !playing;
    notifyListeners();
    final playbackRepository = repository;
    if (playbackRepository is PlaybackRepository) {
      unawaited(
        playbackRepository.togglePlaying().then((value) {
          playing = value;
          notifyListeners();
        }),
      );
    }
  }

  void previous() {
    if (playingCollection.tracks.isEmpty) return;
    final playbackRepository = repository;
    if (playbackRepository is PlaybackRepository) {
      unawaited(playbackRepository.previous().then(_setTrackIndex));
    } else {
      _setTrackIndex(trackIndex - 1);
    }
  }

  void next() {
    if (playingCollection.tracks.isEmpty) return;
    final playbackRepository = repository;
    if (playbackRepository is PlaybackRepository) {
      unawaited(playbackRepository.next().then(_setTrackIndex));
    } else {
      _setTrackIndex(trackIndex + 1);
    }
  }

  void _setTrackIndex(int value) {
    final length = playingCollection.tracks.length;
    trackIndex = length == 0 ? 0 : value.clamp(0, length - 1);
    progress = 0;
    notifyListeners();
  }

  void seek(double value) {
    progress = value.clamp(0, 1);
    notifyListeners();
    final playbackRepository = repository;
    if (playbackRepository is PlaybackRepository) {
      unawaited(playbackRepository.seek(progress));
    }
  }

  static List<int> returnPath({required int from, required int to}) {
    if ((from - to).abs() <= 3) return [to];
    return [to + (from > to ? 3 : -3), to];
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _playbackSubscription?.cancel();
    super.dispose();
  }
}
