import 'dart:io';
import 'package:path/path.dart' as p;
import 'safe_filename.dart';

/// Atomically reserves a flat destination across simultaneous worker isolates.
/// The caller owns the empty file and may write/rename over it. Existing files,
/// directories and symlinks are never reused.
String reserveReceiveDestination(String directory, String originalName) {
  final name = sanitizeFileNameForLocalStorage(originalName);
  final ext = p.extension(name);
  final stem = p.basenameWithoutExtension(name);
  for (var suffix = 0; suffix < 100000; suffix++) {
    final candidate = p.join(directory, suffix == 0 ? name : '$stem ($suffix)$ext');
    try {
      File(candidate).createSync(exclusive: true);
      return candidate;
    } on FileSystemException {
      if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
          FileSystemEntityType.notFound) {
        rethrow;
      }
    }
  }
  throw FileSystemException('Too many files with the same name', directory);
}
