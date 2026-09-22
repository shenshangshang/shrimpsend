import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../file_store.dart';

/// Staging files for shares ingested into `<cacheRoot>/shrimpsend/share_*`.
class SharePendingCache {
  SharePendingCache._();

  static Future<void> deleteStagingFile(
    String? path, {
    String? cacheRoot,
  }) async {
    if (path == null || path.isEmpty) return;
    final root = cacheRoot ?? await FileStore.getCacheDir();
    if (!_isShareStagingPath(path, root)) return;
    await FileStore.deleteFile(path);
    // The caller may supply a staging root (e.g. an imported share batch).
    // Clean only its empty app-owned folder, never the user's receive folder.
    final parent = File(path).parent;
    if (FileStore.isPathUnderDirectory(parent.path, root) &&
        await parent.exists() &&
        await parent.list().isEmpty) {
      await parent.delete();
    }
  }

  static Future<void> deleteStagingFiles(
    Iterable<PlatformFile> files, {
    String? cacheRoot,
  }) async {
    for (final file in files) {
      await deleteStagingFile(file.path, cacheRoot: cacheRoot);
    }
  }

  static bool _isShareStagingPath(String path, String cacheRoot) {
    if (!FileStore.isPathUnderDirectory(path, cacheRoot)) return false;
    final relative = p.relative(
      p.normalize(path),
      from: p.normalize(cacheRoot),
    );
    final firstSegment = relative.split(Platform.pathSeparator).firstOrNull;
    return firstSegment != null && firstSegment.startsWith('share_');
  }
}
