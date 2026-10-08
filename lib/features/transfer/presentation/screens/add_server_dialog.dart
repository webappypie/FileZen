import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/models/network_models.dart';
import '../providers/network_providers.dart';

/// Modal dialog for adding or editing a network server configuration.
class AddServerDialog extends ConsumerStatefulWidget {
  final NetworkServerConfig? existingServer;

  const AddServerDialog({super.key, this.existingServer});

  @override
  ConsumerState<AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends ConsumerState<AddServerDialog> {
  final _formKey = GlobalKey<FormState>();

  late NetworkProtocol _protocol;
  late TextEditingController _nameController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _pathController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late bool _isAnonymous;

  bool _isTesting = false;
  String? _testStatusMessage;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingServer;
    _protocol = existing?.protocol ?? NetworkProtocol.smb;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _hostController = TextEditingController(text: existing?.host ?? '');
    _portController = TextEditingController(
      text: existing != null ? existing.port.toString() : _protocol.defaultPort.toString(),
    );
    _pathController = TextEditingController(text: existing?.path ?? '/');
    _usernameController = TextEditingController(text: existing?.username ?? '');
    _passwordController = TextEditingController(text: existing?.password ?? '');
    _isAnonymous = existing?.isAnonymous ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _pathController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onProtocolChanged(NetworkProtocol newProtocol) {
    setState(() {
      _protocol = newProtocol;
      _portController.text = newProtocol.defaultPort.toString();
      if (_nameController.text.isEmpty ||
          _nameController.text.endsWith('Server') ||
          _nameController.text.endsWith('Share')) {
        _nameController.text = '${newProtocol.shortName} Storage';
      }
    });
  }

  Future<void> _handleTestConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testStatusMessage = null;
      _testSuccess = null;
    });

    final testConfig = _buildConfig();
    final result = await ref
        .read(networkTransferControllerProvider.notifier)
        .testConnection(testConfig);

    if (!mounted) return;

    setState(() {
      _isTesting = false;
      if (result.isSuccess) {
        _testSuccess = true;
        _testStatusMessage = 'Connected successfully!';
      } else {
        _testSuccess = false;
        _testStatusMessage = result.errorOrNull?.message ?? 'Connection failed';
      }
    });
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final config = _buildConfig();
    await ref.read(networkTransferControllerProvider.notifier).saveServer(config);

    if (mounted) {
      Navigator.of(context).pop(config);
    }
  }

  NetworkServerConfig _buildConfig() {
    final id = widget.existingServer?.id ??
        'srv_${DateTime.now().millisecondsSinceEpoch}';
    final name = _nameController.text.trim().isEmpty
        ? '${_protocol.shortName} Storage'
        : _nameController.text.trim();

    return NetworkServerConfig(
      id: id,
      name: name,
      protocol: _protocol,
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? _protocol.defaultPort,
      path: _pathController.text.trim().isEmpty ? '/' : _pathController.text.trim(),
      username: _isAnonymous ? '' : _usernameController.text.trim(),
      password: _isAnonymous ? '' : _passwordController.text.trim(),
      isAnonymous: _isAnonymous,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppSpacing.roundedLg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: AppSpacing.roundedSm,
                      ),
                      child: const Icon(Icons.dns_rounded, color: AppColors.primary),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        widget.existingServer == null ? 'Add Network Storage' : 'Edit Network Storage',
                        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Protocol selector chips
                Text(
                  'Protocol',
                  style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: NetworkProtocol.values.map((p) {
                    final isSelected = _protocol == p;
                    return ChoiceChip(
                      label: Text(p.shortName),
                      selected: isSelected,
                      onSelected: (_) => _onProtocolChanged(p),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.md),

                // Server Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    hintText: 'e.g. Living Room NAS',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Host & Port Row
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _hostController,
                        decoration: const InputDecoration(
                          labelText: 'Host / IP Address *',
                          hintText: '192.168.1.100',
                          prefixIcon: Icon(Icons.router_outlined),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Host is required'
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port *',
                        ),
                        validator: (val) {
                          final p = int.tryParse(val ?? '');
                          if (p == null || p <= 0 || p > 65535) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // Path / Share
                TextFormField(
                  controller: _pathController,
                  decoration: InputDecoration(
                    labelText: _protocol == NetworkProtocol.smb ? 'Share Name' : 'Path',
                    hintText: _protocol == NetworkProtocol.smb ? 'Public' : '/files',
                    prefixIcon: const Icon(Icons.folder_open_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Anonymous toggle
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Anonymous Authentication'),
                  value: _isAnonymous,
                  onChanged: (val) {
                    setState(() {
                      _isAnonymous = val ?? false;
                    });
                  },
                ),

                if (!_isAnonymous) ...[
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],

                // Test Connection Feedback
                if (_testStatusMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: _testSuccess == true
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.error.withValues(alpha: 0.12),
                      borderRadius: AppSpacing.roundedSm,
                      border: Border.all(
                        color: _testSuccess == true ? AppColors.success : AppColors.error,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _testSuccess == true ? Icons.check_circle : Icons.error_outline,
                          color: _testSuccess == true ? AppColors.success : AppColors.error,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _testStatusMessage!,
                            style: AppTypography.bodySmall.copyWith(
                              color: _testSuccess == true ? AppColors.success : AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isTesting ? null : _handleTestConnection,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check_rounded, size: 16),
                      label: Text(_isTesting ? 'Testing...' : 'Test'),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        ElevatedButton(
                          onPressed: _handleSave,
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
