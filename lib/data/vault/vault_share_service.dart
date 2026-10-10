import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/vault_models.dart';
import '../../domain/repositories/i_vault_storage_service.dart';

enum VaultShareStatus { opened, noAppAvailable, failed }

class VaultShareOutcome {
  final VaultShareStatus status;
  final String? message;

  const VaultShareOutcome(this.status, [this.message]);
}

typedef VaultFileOpener = Future<VaultShareStatus> Function(String path);

/// "Share securely": decrypts an item to a short-lived temp copy and hands it
/// to an external app (which can then share it).
///
/// The plaintext copy necessarily leaves the Vault, so it is kept as briefly as
/// possible: it lives in a per-share folder under the app cache, is deleted
/// after [cleanupDelay], and any leftovers (for example if the process was
/// killed first) are swept the next time the service starts. It is deliberately
/// NOT deleted when the Vault locks — leaving FileZen to use the other app
/// auto-locks the Vault, which would otherwise pull the file away mid-share.
class VaultShareService {
  static const String folderName = 'filezen_vault_share';

  final IVaultStorageService storage;
  final Duration cleanupDelay;
  final VaultFileOpener _opener;
  final Future<Directory> Function() _tempDirectory;

  VaultShareService({
    required this.storage,
    this.cleanupDelay = const Duration(minutes: 2),
    VaultFileOpener? opener,
    Future<Directory> Function()? tempDirectory,
  })  : _opener = opener ?? _openWithPlatform,
        _tempDirectory = tempDirectory ?? getTemporaryDirectory;

  static Future<VaultShareStatus> _openWithPlatform(String path) async {
    final result = await OpenFilex.open(path);
    switch (result.type) {
      case ResultType.done:
        return VaultShareStatus.opened;
      case ResultType.noAppToOpen:
        return VaultShareStatus.noAppAvailable;
      default:
        return VaultShareStatus.failed;
    }
  }

  Future<Directory> _root() async => Directory(p.join((await _tempDirectory()).path, folderName));

  /// Deletes plaintext left behind by earlier shares. Call once at startup.
  Future<void> sweepStale() async {
    try {
      final root = await _root();
      if (await root.exists()) await root.delete(recursive: true);
    } catch (e) {
      AppLogger.warning('Could not clear stale shared copies: ${e.runtimeType}', 'VaultShare');
    }
  }

  Future<VaultShareOutcome> shareDecrypted(VaultItem item) async {
    final decrypted = await storage.getDecryptedBytes(item);
    final Uint8List? bytes = decrypted.dataOrNull;
    if (decrypted.isFailure || bytes == null) {
      return VaultShareOutcome(
        VaultShareStatus.failed,
        decrypted.errorOrNull?.message ?? 'Could not decrypt the file.',
      );
    }

    Directory? shareDir;
    try {
      final root = await _root();
      shareDir = Directory(p.join(root.path, DateTime.now().microsecondsSinceEpoch.toString()));
      await shareDir.create(recursive: true);

      var name = p.basename(item.originalFileName).replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
      if (name.isEmpty || name == '.' || name == '..') name = 'shared_file';
      final file = File(p.join(shareDir.path, name));
      await file.writeAsBytes(bytes, flush: true);

      final status = await _opener(file.path);
      _scheduleCleanup(shareDir);
      return VaultShareOutcome(status);
    } catch (e) {
      AppLogger.error('Secure share failed: ${e.runtimeType}', 'VaultShare');
      if (shareDir != null) await _deleteQuietly(shareDir);
      return const VaultShareOutcome(VaultShareStatus.failed, 'Could not prepare the file for sharing.');
    }
  }

  void _scheduleCleanup(Directory dir) {
    Timer(cleanupDelay, () => _deleteQuietly(dir));
  }

  Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      AppLogger.warning('Could not delete shared copy: ${e.runtimeType}', 'VaultShare');
    }
  }
}
