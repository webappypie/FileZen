import 'package:flutter/material.dart';

import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/empty_view.dart';

/// Cloud drives are not integrated in this version (no OAuth or provider API
/// clients exist), so this screen says so instead of offering fake accounts.
class CloudSourcesScreen extends StatelessWidget {
  const CloudSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Sources'),
      ),
      body: const Padding(
        padding: AppSpacing.screenPadding,
        child: EmptyView(
          title: 'Cloud Drives Are Not Available Yet',
          subtitle:
              'Connecting Google Drive, OneDrive, Dropbox or Box is planned for a future release. '
              'Nothing is uploaded or synced today. To move files between devices, use Wi-Fi Share '
              'or add a WebDAV server from Network & Cloud.',
          icon: Icons.cloud_off_rounded,
        ),
      ),
    );
  }
}
