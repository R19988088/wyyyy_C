import 'package:flutter_test/flutter_test.dart';
import 'package:wyyyy/rust_player_repository.dart';
import 'package:wyyyy/src/rust/models.dart';

void main() {
  test('cached playlists with an empty cover require a foreground refresh', () {
    const items = [
      CollectionSummary(
        id: '1',
        collectionType: CollectionType.playlist,
        title: 'Playlist',
        subtitle: 'Owner',
        coverUrl: '',
      ),
    ];

    expect(cachedPlaylistNeedsCoverRefresh(items), isTrue);
  });

  test('cached playlists with covers keep the fast cached startup path', () {
    const items = [
      CollectionSummary(
        id: '1',
        collectionType: CollectionType.playlist,
        title: 'Playlist',
        subtitle: 'Owner',
        coverUrl: 'https://example.com/cover.jpg',
      ),
    ];

    expect(cachedPlaylistNeedsCoverRefresh(items), isFalse);
  });
}
