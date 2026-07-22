import 'package:flutter_test/flutter_test.dart';
import 'package:wyyyy/player.dart';
import 'package:wyyyy/rust_player_repository.dart';
import 'package:wyyyy/src/rust/models.dart';

void main() {
  test('cached playlists with an empty cover require a foreground refresh', () {
    const items = [
      CollectionSummary(
        id: '1',
        collectionType: CollectionType.playlist,
        title: 'Playlist',
        subtitle: 'Owner · 创建于 2024-01-01',
        coverUrl: '',
      ),
    ];

    expect(cachedLibraryNeedsRefresh(LibraryKind.playlist, items), isTrue);
  });

  test('cached playlists with covers keep the fast cached startup path', () {
    const items = [
      CollectionSummary(
        id: '1',
        collectionType: CollectionType.playlist,
        title: 'Playlist',
        subtitle: 'Owner · 创建于 2024-01-01',
        coverUrl: 'https://example.com/cover.jpg',
      ),
    ];

    expect(cachedLibraryNeedsRefresh(LibraryKind.playlist, items), isFalse);
  });

  test('saved playback is selected by exact collection kind and id', () {
    final records = [
      PlaybackRecord(
        collectionKey: 'album:7',
        position: SavedPosition(
          trackId: 'album-track',
          trackIndex: 1,
          position: 12.0,
          updatedAt: BigInt.zero,
        ),
      ),
      PlaybackRecord(
        collectionKey: 'playlist:7',
        position: SavedPosition(
          trackId: 'playlist-track',
          trackIndex: 3,
          position: 87.5,
          updatedAt: BigInt.one,
        ),
      ),
    ];
    const collection = MusicCollection(
      '7',
      'Playlist',
      'Owner',
      LibraryKind.playlist,
      [],
    );

    final saved = savedPositionForCollection(records, collection);

    expect(saved?.trackId, 'playlist-track');
    expect(saved?.trackIndex, 3);
    expect(saved?.position, 87.5);
  });
}
