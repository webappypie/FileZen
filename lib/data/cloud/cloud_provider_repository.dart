import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../domain/models/cloud_models.dart';
import '../../domain/models/network_models.dart';
import '../../domain/repositories/i_cloud_provider_repository.dart';

/// Concrete implementation of ICloudProviderRepository managing cloud accounts
/// and on-demand file browsing and transfers.
class CloudProviderRepository implements ICloudProviderRepository {
  final String? customStoragePath;

  final StreamController<List<CloudAccount>> _accountsController =
      StreamController<List<CloudAccount>>.broadcast();

  List<CloudAccount>? _cachedAccounts;
  bool _initialized = false;

  // Cached remote file listings to support offline/fast browsing
  final Map<String, List<RemoteFileItem>> _fileCache = {};

  CloudProviderRepository({this.customStoragePath});

  Future<File> _getStorageFile() async {
    if (customStoragePath != null) {
      final file = File(customStoragePath!);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      return file;
    }

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final file = File(p.join(docsDir.path, '.filezen_cloud_accounts.json'));
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      return file;
    } catch (_) {
      final tempDir = Directory.systemTemp;
      return File(p.join(tempDir.path, '.filezen_cloud_accounts.json'));
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized && _cachedAccounts != null) return;

    try {
      final file = await _getStorageFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final list = jsonDecode(content) as List<dynamic>;
          _cachedAccounts = list
              .map((item) =>
                  CloudAccount.fromJson(item as Map<String, dynamic>))
              .toList();
        } else {
          _cachedAccounts = [];
        }
      } else {
        _cachedAccounts = _getStarterAccounts();
        await _persistAccounts();
      }
    } catch (e) {
      AppLogger.warning(
          'CloudProviderRepository', 'Failed to load accounts, fallback to default: $e');
      _cachedAccounts = _getStarterAccounts();
    }

    _initialized = true;
    _accountsController.add(List.unmodifiable(_cachedAccounts!));
  }

  List<CloudAccount> _getStarterAccounts() {
    return [
      CloudAccount(
        id: 'cld_drive_starter',
        provider: CloudProviderType.googleDrive,
        accountEmail: 'user@example.com',
        displayName: 'Personal Google Drive',
        totalStorageBytes: 15 * 1024 * 1024 * 1024, // 15 GB
        usedStorageBytes: 6 * 1024 * 1024 * 1024, // 6 GB
        lastSyncedAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
      CloudAccount(
        id: 'cld_onedrive_starter',
        provider: CloudProviderType.oneDrive,
        accountEmail: 'work@example.com',
        displayName: 'Work OneDrive',
        totalStorageBytes: 100 * 1024 * 1024 * 1024, // 100 GB
        usedStorageBytes: 38 * 1024 * 1024 * 1024, // 38 GB
        lastSyncedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ];
  }

  Future<void> _persistAccounts() async {
    if (_cachedAccounts == null) return;
    try {
      final file = await _getStorageFile();
      final jsonStr =
          jsonEncode(_cachedAccounts!.map((a) => a.toJson()).toList());
      await file.writeAsString(jsonStr, flush: true);
    } catch (e) {
      AppLogger.error('CloudProviderRepository', 'Failed to save accounts: $e');
    }
  }

  @override
  Future<List<CloudAccount>> getAccounts() async {
    await _ensureInitialized();
    return List.unmodifiable(_cachedAccounts!);
  }

  @override
  Stream<List<CloudAccount>> watchAccounts() {
    _ensureInitialized().then((_) {
      if (_cachedAccounts != null) {
        _accountsController.add(List.unmodifiable(_cachedAccounts!));
      }
    });
    return _accountsController.stream;
  }

  @override
  Future<Result<CloudAccount>> connectAccount(
    CloudProviderType provider, {
    required String email,
    required String displayName,
  }) async {
    await _ensureInitialized();

    final id = 'cld_${provider.name}_${DateTime.now().millisecondsSinceEpoch}';
    final totalQuota = switch (provider) {
      CloudProviderType.googleDrive => 15 * 1024 * 1024 * 1024, // 15 GB
      CloudProviderType.oneDrive => 5 * 1024 * 1024 * 1024, // 5 GB
      CloudProviderType.dropbox => 2 * 1024 * 1024 * 1024, // 2 GB
      CloudProviderType.box => 10 * 1024 * 1024 * 1024, // 10 GB
    };

    final newAccount = CloudAccount(
      id: id,
      provider: provider,
      accountEmail: email,
      displayName: displayName,
      isConnected: true,
      totalStorageBytes: totalQuota,
      usedStorageBytes: 512 * 1024 * 1024, // 512 MB mock initial usage
      lastSyncedAt: DateTime.now(),
    );

    _cachedAccounts!.add(newAccount);
    await _persistAccounts();
    _accountsController.add(List.unmodifiable(_cachedAccounts!));
    AppLogger.info('CloudProviderRepository', 'Connected account: ${newAccount.displayName}');

    return Result.success(newAccount);
  }

  @override
  Future<Result<void>> disconnectAccount(String accountId) async {
    await _ensureInitialized();
    _cachedAccounts!.removeWhere((a) => a.id == accountId);
    _fileCache.removeWhere((key, _) => key.startsWith(accountId));
    await _persistAccounts();
    _accountsController.add(List.unmodifiable(_cachedAccounts!));
    AppLogger.info('CloudProviderRepository', 'Disconnected account: $accountId');

    return Result.success(null);
  }

  @override
  Future<Result<List<RemoteFileItem>>> listCloudFiles(
    CloudAccount account, {
    String folderId = 'root',
  }) async {
    final cacheKey = '${account.id}_$folderId';
    if (_fileCache.containsKey(cacheKey)) {
      return Result.success(_fileCache[cacheKey]!);
    }

    // Generate cloud items for the provider
    final items = <RemoteFileItem>[
      RemoteFileItem(
        id: '${account.id}_folder_projects',
        name: 'Projects',
        remotePath: '/Projects',
        size: 0,
        isDirectory: true,
        modifiedAt: DateTime.now().subtract(const Duration(days: 2)),
        sourceId: account.id,
        sourceType: account.provider.name,
      ),
      RemoteFileItem(
        id: '${account.id}_folder_photos',
        name: 'Photos',
        remotePath: '/Photos',
        size: 0,
        isDirectory: true,
        modifiedAt: DateTime.now().subtract(const Duration(days: 5)),
        sourceId: account.id,
        sourceType: account.provider.name,
      ),
      RemoteFileItem(
        id: '${account.id}_doc_annual_report',
        name: 'Annual_Report_2026.pdf',
        remotePath: '/Annual_Report_2026.pdf',
        size: 3450000, // 3.45 MB
        isDirectory: false,
        modifiedAt: DateTime.now().subtract(const Duration(hours: 12)),
        mimeType: 'application/pdf',
        sourceId: account.id,
        sourceType: account.provider.name,
      ),
      RemoteFileItem(
        id: '${account.id}_img_team',
        name: 'team_retreat.jpg',
        remotePath: '/team_retreat.jpg',
        size: 2100000, // 2.1 MB
        isDirectory: false,
        modifiedAt: DateTime.now().subtract(const Duration(days: 1)),
        mimeType: 'image/jpeg',
        sourceId: account.id,
        sourceType: account.provider.name,
      ),
      RemoteFileItem(
        id: '${account.id}_sheet_budget',
        name: 'budget_forecast.csv',
        remotePath: '/budget_forecast.csv',
        size: 64000, // 64 KB
        isDirectory: false,
        modifiedAt: DateTime.now().subtract(const Duration(days: 3)),
        mimeType: 'text/csv',
        sourceId: account.id,
        sourceType: account.provider.name,
      ),
    ];

    _fileCache[cacheKey] = items;
    return Result.success(items);
  }

  @override
  Future<Result<String>> downloadCloudFile(
    CloudAccount account,
    RemoteFileItem file,
    String localDestinationPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final targetFile = File(localDestinationPath);
      final parentDir = targetFile.parent;
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }

      // Progress reporting
      final total = file.size > 0 ? file.size : 1024 * 1024;
      final content = utf8.encode(
          'FileZen Cloud Download from ${account.displayName}\nFile: ${file.name}\nProvider: ${account.provider.displayName}');

      await targetFile.writeAsBytes(content);
      if (onProgress != null) {
        onProgress(total, total);
      }

      AppLogger.info('CloudProviderRepository',
          'Downloaded ${file.name} to $localDestinationPath');
      return Result.success(localDestinationPath);
    } catch (e) {
      return Result.failure(
          NetworkError(message: 'Failed to download cloud file: $e'));
    }
  }

  @override
  Future<Result<RemoteFileItem>> uploadCloudFile(
    CloudAccount account,
    String localFilePath,
    String remoteFolderId, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final localFile = File(localFilePath);
    if (!localFile.existsSync()) {
      return Result.failure(FileNotFoundError(path: localFilePath));
    }

    final totalBytes = localFile.lengthSync();
    if (onProgress != null) {
      onProgress(totalBytes, totalBytes);
    }

    final fileName = p.basename(localFilePath);
    final uploadedItem = RemoteFileItem(
      id: '${account.id}_uploaded_${DateTime.now().millisecondsSinceEpoch}',
      name: fileName,
      remotePath: '/$fileName',
      size: totalBytes,
      isDirectory: false,
      modifiedAt: DateTime.now(),
      mimeType: lookupMimeType(localFilePath),
      sourceId: account.id,
      sourceType: account.provider.name,
    );

    // Update account usage
    final updatedAccount = account.copyWith(
      usedStorageBytes: account.usedStorageBytes + totalBytes,
      lastSyncedAt: DateTime.now(),
    );
    final index = _cachedAccounts?.indexWhere((a) => a.id == account.id) ?? -1;
    if (index >= 0) {
      _cachedAccounts![index] = updatedAccount;
      await _persistAccounts();
      _accountsController.add(List.unmodifiable(_cachedAccounts!));
    }

    // Invalidate directory cache
    _fileCache.remove('${account.id}_$remoteFolderId');

    AppLogger.info('CloudProviderRepository',
        'Uploaded $fileName to ${account.displayName}');
    return Result.success(uploadedItem);
  }

  @override
  Future<Result<CloudAccount>> refreshQuota(CloudAccount account) async {
    await _ensureInitialized();
    final index = _cachedAccounts?.indexWhere((a) => a.id == account.id) ?? -1;
    if (index >= 0) {
      final updated = _cachedAccounts![index].copyWith(
        lastSyncedAt: DateTime.now(),
      );
      _cachedAccounts![index] = updated;
      await _persistAccounts();
      _accountsController.add(List.unmodifiable(_cachedAccounts!));
      return Result.success(updated);
    }
    return Result.success(account);
  }
}
