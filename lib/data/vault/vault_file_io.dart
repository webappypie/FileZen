import 'dart:io';

/// Writes [bytes] to a sibling temp file, flushes, then renames over [target]
/// so a crash can never leave a truncated vault file, manifest or config.
Future<void> atomicWriteBytes(File target, List<int> bytes) async {
  if (!await target.parent.exists()) {
    await target.parent.create(recursive: true);
  }
  final tmp = File('${target.path}.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  try {
    await tmp.rename(target.path);
  } on FileSystemException {
    // Some platforms refuse to rename over an existing file.
    if (await target.exists()) await target.delete();
    await tmp.rename(target.path);
  }
}
