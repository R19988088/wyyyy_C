import 'package:flutter_test/flutter_test.dart';
import 'package:wyyyy/services/audio_handler.dart';

void main() {
  test('adjacent queue navigation clamps at both ends', () {
    expect(adjacentQueueIndex(0, 3, -1), 0);
    expect(adjacentQueueIndex(1, 3, -1), 0);
    expect(adjacentQueueIndex(1, 3, 1), 2);
    expect(adjacentQueueIndex(2, 3, 1), 2);
    expect(adjacentQueueIndex(0, 0, 1), -1);
  });
}
