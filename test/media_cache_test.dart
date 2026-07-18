import 'package:flutter_test/flutter_test.dart';
import 'package:wyyyy/services/media_cache.dart';

void main() {
  test('cache byte formatting stays compact', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1024), '1.0 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
  });
}
