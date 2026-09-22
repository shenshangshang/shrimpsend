import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/file_utils.dart';
import '../utils/safe_filename.dart';
import '../utils/receive_destination.dart';
import 'desktop_trash.dart';
import 'android_receive_storage.dart';
import 'receive_dir_resolver.dart';
import 'visible_export_target.dart';

/// Lightweight projection of a row from the `received_files` index.
class ReceivedFileInfo {
  final String messageId;
  final String path;
  final String displayName;
  final String protocol;
  final int size;
  final DateTime modified;
  final DateTime createdAt;
  final FileCategory category;
  final String? threadKey;
  final String? s3Key;
  final String? fromDeviceId;
  final String? cachePath;
  final String? visiblePath;
  final ExportStatus exportStatus;
  final bool gallerySaved;

  ReceivedFileInfo({
    required this.messageId,
    required this.path,
    required this.displayName,
    required this.protocol,
    required this.size,
    required this.modified,
    required this.createdAt,
    required this.category,
    this.threadKey,
    this.s3Key,
    this.fromDeviceId,
    this.cachePath,
    this.visiblePath,
    this.exportStatus = ExportStatus.pending,
    this.gallerySaved = false,
  });
}

/// Storage layout:
///
/// Receives use the selected destination directly. The separate cache is only
/// for outgoing clipboard/share imports and legacy files.
class FileStore {
  static ReceiveDirResolution? _cachedResolution;

  static Future<String> getCacheDir() => ReceiveDirResolver.resolveCacheDir();

  static Future<String> getReceiveDir() async =>
      (await getReceiveDirResolution()).path;

  static Future<ReceiveDirResolution> getReceiveDirResolution() async {
    if (_cachedResolution != null) return _cachedResolution!;

    final visible = await ReceiveDirResolver.resolveVisibleExportTarget();
    final receivePath = visible.posixPath;
    // Document-provider destinations still need their native export adapter.
    final root = receivePath ?? await ReceiveDirResolver.resolveCacheDir();
    await ReceiveDirResolver.assertWritableDirectory(root);
    final isCustom = visible.isCustom;

    _cachedResolution = ReceiveDirResolution(
      path: root,
      kind: receivePath == null
          ? ReceiveStorageKind.appCache
          : ReceiveStorageKind.publicExternal,
      isCustom: isCustom,
      customSafTreeUri: visible.safTreeUri,
      customSafDisplayName: visible.displayName,
      visibleExportTarget: visible,
    );
    return _cachedResolution!;
  }

  static Future<VisibleExportTarget> getVisibleExportTarget() async {
    final resolution = await getReceiveDirResolution();
    return resolution.visibleExportTarget ??
        await ReceiveDirResolver.resolveVisibleExportTarget();
  }

  static Future<String?> getDesktopDownloadsDir() async {
    final base = await ReceiveDirResolver.getPublicDownloadsBase();
    if (base == null || base.trim().isEmpty) return null;
    return ReceiveDirResolver.ensureDirectory(base);
  }

  static const int _exportCopyMaxAttempts = 5;

  /// Copies [sourcePath] into [directoryPath] via a `.part` temp file, then
  /// renames atomically and verifies byte length matches the source.
  static Future<String> exportCopyVerified({
    required String sourcePath,
    required String directoryPath,
    required String fileName,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _exportCopyMaxAttempts; attempt++) {
      try {
        return await _exportCopyVerifiedOnce(
          sourcePath: sourcePath,
          directoryPath: directoryPath,
          fileName: fileName,
        );
      } catch (e) {
        lastError = e;
        if (attempt == _exportCopyMaxAttempts) break;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
    if (lastError is Exception) throw lastError;
    throw Exception(
      'Export copy failed after $_exportCopyMaxAttempts attempts: $lastError',
    );
  }

  static Future<String> _exportCopyVerifiedOnce({
    required String sourcePath,
    required String directoryPath,
    required String fileName,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Source file does not exist', sourcePath);
    }
    final expectedSize = await source.length();
    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final targetPath = resolveUniquePath(dir.path, fileName);
    final partPath = '$targetPath.part';
    final partFile = File(partPath);
    try {
      if (await partFile.exists()) {
        await partFile.delete();
      }
      await source.copy(partPath);
      final copiedSize = await partFile.length();
      if (copiedSize != expectedSize) {
        throw FileSystemException(
          'Export copy size mismatch: expected $expectedSize, got $copiedSize',
          partPath,
        );
      }
      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(targetPath);
      final finalSize = await targetFile.length();
      if (finalSize != expectedSize) {
        throw FileSystemException(
          'Export rename size mismatch: expected $expectedSize, got $finalSize',
          targetPath,
        );
      }
      return targetPath;
    } catch (e) {
      try {
        if (await partFile.exists()) {
          await partFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  static Future<String> exportCopyToPath({
    required String sourcePath,
    required String directoryPath,
    required String fileName,
  }) => exportCopyVerified(
    sourcePath: sourcePath,
    directoryPath: directoryPath,
    fileName: fileName,
  );

  static Future<String> reserveCacheDir(String messageId) async {
    final root = await getCacheDir();
    final dir = p.join(root, _safeDirName(messageId));
    return ReceiveDirResolver.ensureDirectory(dir);
  }

  static String reserveCacheDirSync(String root, String messageId) {
    final dir = p.join(root, _safeDirName(messageId));
    final d = Directory(dir);
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
    return d.path;
  }

  /// Build cache staging path: `<cacheRoot>/<messageId>/<name>`.
  static Future<String> buildCachePath(
    String messageId,
    String originalName,
  ) async {
    final dir = await reserveCacheDir(messageId);
    return resolveUniquePath(dir, originalName);
  }

  static String buildCachePathSync(
    String root,
    String messageId,
    String originalName,
  ) {
    final dir = reserveCacheDirSync(root, messageId);
    return resolveUniquePath(dir, originalName);
  }

  /// Flat destination path; receives never enter the outgoing cache.
  static Future<String> buildReceivePath(
    String messageId,
    String originalName,
  ) async =>
      await AndroidReceiveStorage.prepare('receive:$messageId', originalName) ??
      reserveReceiveDestination(await getReceiveDir(), originalName);

  static String buildReceivePathSync(
    String root,
    String messageId,
    String originalName,
  ) => reserveReceiveDestination(root, originalName);

  static Future<String> reserveReceiveDir(String messageId) => getReceiveDir();

  static String reserveReceiveDirSync(String root, String messageId) => root;

  static String resolveUniquePath(String dir, String originalName) {
    final base = sanitizeFileNameForLocalStorage(originalName);
    final candidate = p.join(dir, base);
    if (!File(candidate).existsSync()) return candidate;
    final ext = p.extension(base);
    final stem = ext.isEmpty
        ? base
        : base.substring(0, base.length - ext.length);
    for (int i = 1; i < 10000; i++) {
      final next = p.join(dir, '$stem ($i)$ext');
      if (!File(next).existsSync()) return next;
    }
    return p.join(dir, '$stem ${DateTime.now().millisecondsSinceEpoch}$ext');
  }

  /// Best readable path: cache if present, else visible POSIX path.
  static String resolveReadablePath({
    required String? cachePath,
    required String? visiblePath,
    required String absPath,
  }) {
    if (cachePath != null &&
        cachePath.isNotEmpty &&
        File(cachePath).existsSync()) {
      return cachePath;
    }
    if (visiblePath != null &&
        visiblePath.isNotEmpty &&
        !visiblePath.startsWith('content://') &&
        File(visiblePath).existsSync()) {
      return visiblePath;
    }
    return absPath;
  }

  static String _safeDirName(String messageId) {
    if (messageId.isEmpty) {
      return 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    }
    final cleaned = messageId.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return cleaned.isEmpty
        ? 'unknown_${DateTime.now().millisecondsSinceEpoch}'
        : cleaned;
  }

  static void invalidateReceiveDirCache() {
    _cachedResolution = null;
  }

  static Future<void> assertWritableDirectory(String path) =>
      ReceiveDirResolver.assertWritableDirectory(path);

  static final List<void Function()> _onReceiveDirChanged = [];

  static void addReceiveDirChangedListener(void Function() callback) {
    _onReceiveDirChanged.add(callback);
  }

  static void removeReceiveDirChangedListener(void Function() callback) {
    _onReceiveDirChanged.remove(callback);
  }

  static void notifyReceiveDirChanged() {
    for (final cb in _onReceiveDirChanged) {
      cb();
    }
  }

  /// Deletes the file at [path]. When [useTrash] is true and the current
  /// platform is a desktop OS, the file is moved to the system recycle bin
  /// instead of being permanently removed (falling back to a hard delete if
  /// the trash operation fails). Returns true when the file is gone.
  static Future<bool> deleteFile(String path, {bool useTrash = false}) async {
    final file = File(path);
    if (!await file.exists()) {
      return true;
    }
    var deleted = false;
    if (useTrash && DesktopTrash.isSupported) {
      deleted = await DesktopTrash.moveToTrash(path);
    }
    if (!deleted) {
      try {
        await file.delete();
        deleted = true;
      } catch (_) {
        deleted = false;
      }
    }
    final parent = file.parent;
    try {
      // Only app-owned cache folders may be removed. Never remove Downloads
      // or a user's selected destination when its last file is deleted.
      if (isPathUnderDirectory(parent.path, await getCacheDir()) &&
          await parent.exists()) {
        final empty = await parent.list().isEmpty;
        if (empty) {
          await parent.delete();
        }
      }
    } catch (_) {}
    return deleted;
  }

  /// Removes `<cacheRoot>/<messageId>/` staging directory. Returns true when gone.
  static Future<bool> deleteByMessageId(String messageId) async {
    final root = await getCacheDir();
    final dir = Directory(p.join(root, _safeDirName(messageId)));
    if (!await dir.exists()) return true;
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      return !await dir.exists();
    }
    return !await dir.exists();
  }

  /// iOS may keep cache files open while previewing; retry cleanup in background.
  static Future<void> deleteCacheEntryWhenReady(String messageId) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
      if (await deleteByMessageId(messageId)) return;
    }
  }

  /// Deletes all files and subdirectories directly under the app cache root.
  /// Does not touch paths outside [getCacheDir].
  static Future<int> clearCacheContents() async {
    final root = Directory(await getCacheDir());
    if (!await root.exists()) return 0;
    var count = 0;
    for (final entry in root.listSync(followLinks: false)) {
      try {
        if (entry is Directory) {
          await entry.delete(recursive: true);
          count++;
        } else if (entry is File) {
          await entry.delete();
          count++;
        }
      } catch (_) {}
    }
    return count;
  }

  static bool isPathUnderDirectory(String? path, String directoryPath) {
    if (path == null || path.trim().isEmpty) return false;
    final normDir = p.normalize(directoryPath);
    final normPath = p.normalize(path);
    return p.equals(normPath, normDir) || p.isWithin(normDir, normPath);
  }
}
