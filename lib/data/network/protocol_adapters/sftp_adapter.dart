import '../../../domain/models/network_models.dart';
import 'protocol_adapter.dart';

/// SFTP is not implemented yet (no real SSH/SFTP client exists in FileZen).
///
/// The previous placeholder returned a canned directory listing and wrote
/// fabricated "downloaded" files while reporting success; it was removed so the
/// app never claims a transfer it did not perform. Every operation now fails
/// with an explicit "not supported" error (see docs/04_Development_Roadmap/
/// audit_remediation_status.md).
class SftpProtocolAdapter extends UnsupportedProtocolAdapter {
  const SftpProtocolAdapter() : super(NetworkProtocol.sftp);
}
