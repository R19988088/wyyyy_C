import 'package:flutter_test/flutter_test.dart';
import 'package:wyyyy/player.dart';

void main() {
  test('browsing a collection does not change the playing collection', () {
    final controller = PlayerController(InMemoryPlayerRepository.demo());

    controller.browseTo(2);

    expect(controller.browsedIndex, 2);
    expect(controller.playingCollectionIndex, 0);
  });

  test('switching category does not replace active playback', () {
    final controller = PlayerController(InMemoryPlayerRepository.demo())
      ..browseTo(1)
      ..activateCentered(1);

    final active = controller.playingCollection;
    controller.selectKind(LibraryKind.playlist);

    expect(controller.playingCollection, same(active));
    expect(controller.track.title, '晴天');
  });

  test('empty repository remains safe to inspect and control', () {
    final controller = PlayerController(InMemoryPlayerRepository(const []));

    expect(controller.visible, isNotEmpty);
    expect(controller.playingCollection.tracks, isEmpty);
    expect(controller.track.title, isEmpty);
    expect(controller.activateCentered(0), isFalse);
    controller
      ..previous()
      ..next()
      ..togglePlaying()
      ..seek(.5);
  });

  test('only tapping the centered collection activates it', () {
    final controller = PlayerController(InMemoryPlayerRepository.demo())
      ..browseTo(1);

    expect(controller.activateCentered(0), isFalse);
    expect(controller.playingCollectionIndex, 0);
    expect(controller.activateCentered(1), isTrue);
    expect(controller.playingCollectionIndex, 1);
  });

  test('previous and next stay inside the active track list', () {
    final controller = PlayerController(InMemoryPlayerRepository.demo());

    controller.previous();
    expect(controller.trackIndex, 0);
    controller.next();
    expect(controller.trackIndex, 1);
    controller.next();
    controller.next();
    expect(controller.trackIndex, 2);
  });

  test(
    'return path prepositions at most three covers from a distant target',
    () {
      expect(PlayerController.returnPath(from: 8, to: 1), [4, 1]);
      expect(PlayerController.returnPath(from: 3, to: 1), [1]);
      expect(PlayerController.returnPath(from: 0, to: 7), [4, 7]);
    },
  );

  test('switching categories restores each browsed cover', () {
    final controller = PlayerController(InMemoryPlayerRepository.demo())
      ..browseTo(2)
      ..selectKind(LibraryKind.playlist)
      ..browseTo(1)
      ..selectKind(LibraryKind.album);

    expect(controller.browsedIndex, 2);
    controller.selectKind(LibraryKind.playlist);
    expect(controller.browsedIndex, 1);
  });

  test('sleep timer cycles through 60, 120, and off', () {
    final controller = PlayerController(InMemoryPlayerRepository.demo());

    controller.cycleSleepTimer();
    expect(controller.sleepTimerMinutes, 60);
    controller.cycleSleepTimer();
    expect(controller.sleepTimerMinutes, 120);
    controller.cycleSleepTimer();
    expect(controller.sleepTimerMinutes, 0);
    controller.dispose();
  });
}
