import '../../core/error/app_error.dart';
import '../../core/result/result.dart';
import '../../domain/models/cloud_models.dart';
import '../../domain/models/network_models.dart';
import '../../domain/repositories/i_cloud_provider_repository.dart';

/// Cloud storage is NOT integrated in this version.
///
/// A real integration needs provider OAuth (client IDs registered with Google,
/// Microsoft, Dropbox and Box) plus REST clients for listing, download, upload
/// and quota. None of that exists yet, and the previous implementation faked it
/// (seeded accounts, hard-coded file lists, "downloads" that wrote placeholder
/// text, uploads that reported success without sending anything).
///
/// This repository therefore never reports an account, file or transfer it does
/// not have: there are no accounts, and every operation fails with an explicit
/// "not available" error. See docs/04_Development_Roadmap/audit_remediation_status.md.
class CloudProviderRepository implements ICloudProviderRepository {
  /// Retained so existing call sites keep compiling; nothing is persisted.
  final String? customStoragePath;

  const CloudProviderRepository({this.customStoragePath});

  /// Whether any cloud provider can actually be used.
  static const bool isAvailable = false;

  ProviderUnavailableError _unavailable(String providerName) => ProviderUnavailableError(
        providerName: providerName,
        message: '$providerName is not available in this version of FileZen.',
        recoverySuggestion:
            'Use Wi-Fi Share or a WebDAV server to move files. Cloud drives are planned for a future release.',
      );

  @override
  Future<List<CloudAccount>> getAccounts() async => const [];

  @override
  Stream<List<CloudAccount>> watchAccounts() => Stream.value(const <CloudAccount>[]);

  @override
  Future<Result<CloudAccount>> connectAccount(
    CloudProviderType provider, {
    required String email,
    required String displayName,
  }) async =>
      Result.failure(_unavailable(provider.displayName));

  @override
  Future<Result<void>> disconnectAccount(String accountId) async => Result.success(null);

  @override
  Future<Result<List<RemoteFileItem>>> listCloudFiles(
    CloudAccount account, {
    String folderId = 'root',
  }) async =>
      Result.failure(_unavailable(account.provider.displayName));

  @override
  Future<Result<String>> downloadCloudFile(
    CloudAccount account,
    RemoteFileItem file,
    String localDestinationPath, {
    void Function(int received, int total)? onProgress,
  }) async =>
      Result.failure(_unavailable(account.provider.displayName));

  @override
  Future<Result<RemoteFileItem>> uploadCloudFile(
    CloudAccount account,
    String localFilePath,
    String remoteFolderId, {
    void Function(int sent, int total)? onProgress,
  }) async =>
      Result.failure(_unavailable(account.provider.displayName));

  @override
  Future<Result<CloudAccount>> refreshQuota(CloudAccount account) async =>
      Result.failure(_unavailable(account.provider.displayName));
}
