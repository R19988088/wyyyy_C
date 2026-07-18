import 'dart:io';

import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

const _coverCacheKey = 'wyyyy-cover-cache';

class _PersistentFileSystem implements FileSystem {
  _PersistentFileSystem() : _directory = _coverDirectory();

  final Future<fs.Directory> _directory;

  static Future<fs.Directory> _coverDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = const LocalFileSystem().directory(
      '${support.path}${Platform.pathSeparator}$_coverCacheKey',
    );
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<fs.File> createFile(String name) async =>
      (await _directory).childFile(name);
}

class PersistentCoverCache extends CacheManager {
  PersistentCoverCache._()
    : super(
        Config(
          _coverCacheKey,
          stalePeriod: const Duration(days: 36500),
          maxNrOfCacheObjects: 100000,
          fileSystem: _PersistentFileSystem(),
        ),
      );

  static final PersistentCoverCache instance = PersistentCoverCache._();
}

Future<int> flutterCacheSize() async {
  final support = await getApplicationSupportDirectory();
  final root = Directory(
    '${support.path}${Platform.pathSeparator}$_coverCacheKey',
  );
  if (!await root.exists()) return 0;
  var bytes = 0;
  await for (final entry in root.list(recursive: true, followLinks: false)) {
    if (entry is File) {
      try {
        bytes += await entry.length();
      } on FileSystemException {
        // A concurrent cache replacement may remove a file while it is counted.
      }
    }
  }
  return bytes;
}

Future<void> clearFlutterMediaCache() =>
    PersistentCoverCache.instance.emptyCache();

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}
