import '../../core/result/result.dart';
import '../models/cloud_models.dart';
import '../models/network_models.dart';

/// Contract for managing cloud storage accounts (Google Drive, OneDrive, Dropbox, Box)
/// and browsing/transferring files on demand.
abstract class ICloudProviderRepository {
  /// Returns all currently registered cloud accounts.
  Future<List<CloudAccount>> getAccounts();

  /// Reactive stream broadcasting connected cloud accounts.
  Stream<List<CloudAccount>> watchAccounts();

  /// Connects a new cloud storage account.
  Future<Result<CloudAccount>> connectAccount(
    CloudProviderType provider, {
    required String email,
    required String displayName,
  });

  /// Disconnects and removes a cloud storage account.
  Future<Result<void>> disconnectAccount(String accountId);

  /// Lists files and folders located in a specific cloud folder.
  Future<Result<List<RemoteFileItem>>> listCloudFiles(
    CloudAccount account, {
    String folderId = 'root',
  });

  /// Downloads a cloud file to a local filesystem destination.
  Future<Result<String>> downloadCloudFile(
    CloudAccount account,
    RemoteFileItem file,
    String localDestinationPath, {
    void Function(int received, int total)? onProgress,
  });

  /// Uploads a local file to a specific cloud folder on explicit user request.
  Future<Result<RemoteFileItem>> uploadCloudFile(
    CloudAccount account,
    String localFilePath,
    String remoteFolderId, {
    void Function(int sent, int total)? onProgress,
  });

  /// Updates and returns the latest storage quota usage for an account.
  Future<Result<CloudAccount>> refreshQuota(CloudAccount account);
}
