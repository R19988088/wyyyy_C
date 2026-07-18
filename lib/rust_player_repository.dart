import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'player.dart';
import 'services/audio_handler.dart';
import 'src/rust/api.dart' as rust_api;
import 'src/rust/models.dart' as rust;

class RustPlayerRepository implements PlaybackRepository {
  RustPlayerRepository._(this._handler);

  static Future<RustPlayerRepository> create(WyyyyAudioHandler handler) async {
    final repository = RustPlayerRepository._(handler);
    await Future.wait(LibraryKind.values.map(repository._loadLibrary));
    await repository._restorePlayback();
    return repository;
  }

  final WyyyyAudioHandler _handler;
  final Map<LibraryKind, List<MusicCollection>> _libraries = {
    for (final kind in LibraryKind.values) kind: <MusicCollection>[],
  };
  MusicCollection? _active;
  MusicCollection? _restoredCollection;
  int _restoredTrackIndex = 0;
  int _activationGeneration = 0;
  Timer? _saveTimer;

  @override
  MusicCollection? get restoredCollection => _restoredCollection;

  @override
  int get restoredTrackIndex => _restoredTrackIndex;

  @override
  Stream<PlaybackSnapshot> get playback => _handler.playbackState.map((state) {
    _scheduleSave();
    final duration = _handler.player.state.duration.inMilliseconds;
    final position = _handler.player.state.position.inMilliseconds;
    return PlaybackSnapshot(
      playing: state.playing,
      trackIndex: state.queueIndex ?? _handler.currentIndex.clamp(0, 1 << 30),
      progress: duration <= 0 ? 0 : (position / duration).clamp(0, 1),
    );
  });

  @override
  List<MusicCollection> collections(LibraryKind kind) => _libraries[kind]!;

  @override
  Future<void> reload() => Future.wait(
    LibraryKind.values.map((kind) async {
      final items = await rust_api.refreshLibraryNow(category: kind.name);
      _replaceLibrary(kind, items);
    }),
  );

  Future<void> _loadLibrary(LibraryKind kind) async {
    try {
      final result = await rust_api.getLibrary(category: kind.name);
      _replaceLibrary(kind, result.items);
      if (result.fromCache &&
          kind == LibraryKind.playlist &&
          cachedPlaylistNeedsCoverRefresh(result.items)) {
        final fresh = await rust_api.refreshLibraryNow(category: kind.name);
        _replaceLibrary(kind, fresh);
      }
    } catch (_) {
      // A logged-out or offline launch intentionally starts with an empty library.
    }
  }

  void _replaceLibrary(LibraryKind kind, List<rust.CollectionSummary> items) {
    final target = _libraries[kind]!;
    target
      ..clear()
      ..addAll(items.map((item) => _collection(item, kind)));
  }

  MusicCollection _collection(rust.CollectionSummary item, LibraryKind kind) =>
      MusicCollection(
        item.id,
        item.title,
        item.subtitle,
        kind,
        <Track>[],
        coverUrl: item.coverUrl,
      );

  @override
  Future<void> loadTracks(MusicCollection collection) async {
    if (collection.tracks.isEmpty) {
      final result = await rust_api.getCollectionTracks(
        collectionType: collection.kind.name,
        collectionId: collection.id,
      );
      collection.tracks.addAll(result.items.map(_track));
    }
  }

  @override
  Future<int> activate(
    MusicCollection collection, {
    int trackIndex = 0,
    bool autoplay = true,
  }) async {
    final generation = ++_activationGeneration;
    await _saveNow();
    await loadTracks(collection);
    if (generation != _activationGeneration) {
      throw StateError('播放请求已过期');
    }
    if (collection.tracks.isEmpty) {
      throw StateError('该集合暂无可播放曲目');
    }
    final items = collection.tracks
        .map((track) => _mediaItem(track, collection))
        .toList(growable: false);
    final index = trackIndex.clamp(0, items.length - 1);
    await _handler.setPlayableQueue(
      items,
      initialIndex: index,
      autoplay: autoplay,
      resolveUri: _resolveMediaUri,
    );
    if (generation != _activationGeneration) {
      throw StateError('播放请求已过期');
    }
    _active = collection;
    return index;
  }

  Track _track(rust.Track track) => Track(
    track.id,
    track.title,
    track.artist,
    duration: track.duration.round(),
    coverUrl: track.coverUrl,
  );

  MediaItem _mediaItem(Track track, MusicCollection collection) {
    final cover = track.coverUrl ?? collection.coverUrl;
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      duration: Duration(seconds: track.duration),
      artUri: cover.isEmpty ? null : Uri.tryParse(cover),
      extras: {'collectionKey': '${collection.kind.name}:${collection.id}'},
    );
  }

  Future<String> _resolveMediaUri(MediaItem item) async {
    final trackId = item.id;
    final cached = await rust_api.lookupAudioCache(trackId: trackId);
    final collectionKey = item.extras!['collectionKey']! as String;
    final uri = cached == null
        ? await rust_api.getStreamUrl(
            collectionKey: collectionKey,
            trackId: trackId,
          )
        : Uri.file(cached).toString();
    if (cached == null) {
      unawaited(
        rust_api
            .cacheAudioTrack(collectionKey: collectionKey, trackId: trackId)
            .catchError((_) => ''),
      );
    }
    return uri;
  }

  @override
  Future<int> previous() async {
    await _saveNow();
    await _handler.skipToPrevious();
    return _handler.currentIndex;
  }

  @override
  Future<int> next() async {
    await _saveNow();
    await _handler.skipToNext();
    return _handler.currentIndex;
  }

  @override
  Future<bool> togglePlaying() async {
    if (_handler.playbackState.value.playing) {
      await _handler.pause();
      await _saveNow();
    } else {
      await _handler.play();
    }
    return _handler.player.state.playing;
  }

  @override
  Future<void> seek(double progress) async {
    final duration = _handler.player.state.duration;
    await _handler.seek(duration * progress.clamp(0, 1));
  }

  @override
  Future<void> clearCache() => rust_api.clearMediaCache();

  Future<void> _restorePlayback() async {
    List<rust.PlaybackRecord> records;
    try {
      records = await rust_api.loadPlaybackState();
    } catch (_) {
      return;
    }
    if (records.isEmpty) return;
    records.sort(
      (a, b) => b.position.updatedAt.compareTo(a.position.updatedAt),
    );
    final record = records.first;
    final separator = record.collectionKey.indexOf(':');
    if (separator <= 0) return;
    final kind = LibraryKind.values.where(
      (value) => value.name == record.collectionKey.substring(0, separator),
    );
    if (kind.isEmpty) return;
    final id = record.collectionKey.substring(separator + 1);
    final collection = _libraries[kind.first]!.where((item) => item.id == id);
    if (collection.isEmpty) return;
    try {
      final item = collection.first;
      final index = await activate(
        item,
        trackIndex: record.position.trackIndex,
        autoplay: false,
      );
      await _handler.seek(
        Duration(milliseconds: (record.position.position * 1000).round()),
      );
      _restoredCollection = item;
      _restoredTrackIndex = index;
    } catch (_) {}
  }

  void _scheduleSave() {
    _saveTimer ??= Timer(const Duration(seconds: 5), () {
      _saveTimer = null;
      unawaited(_saveNow().catchError((_) {}));
    });
  }

  Future<void> _saveNow() async {
    final collection = _active;
    if (collection == null || collection.tracks.isEmpty) return;
    final index = _handler.currentIndex;
    if (index < 0 || index >= collection.tracks.length) return;
    await rust_api.savePlaybackState(
      collectionKey: '${collection.kind.name}:${collection.id}',
      position: rust.SavedPosition(
        trackId: collection.tracks[index].id,
        trackIndex: index,
        position: _handler.player.state.position.inMilliseconds / 1000,
        updatedAt: BigInt.from(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }
}

bool cachedPlaylistNeedsCoverRefresh(List<rust.CollectionSummary> items) =>
    items.any((item) => item.coverUrl.trim().isEmpty);
