import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  bool _isUnlocked = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!_isUnlocked) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.typeVault.withValues(alpha: isDark ? 0.15 : 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 56,
                    color: AppColors.typeVault,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Vault is Locked',
                  style: AppTypography.headlineMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Hardware-backed AES-256-GCM encryption with Biometric/PIN protection.\nThumbnails and previews never leak outside.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _isUnlocked = true);
                  },
                  icon: const Icon(Icons.fingerprint_rounded, size: 22),
                  label: const Text('Unlock with Biometrics / PIN'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Private Files',
                style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _isUnlocked = false),
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
                label: const Text('Lock Now'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Row(
                children: [
                  const Icon(Icons.security_rounded, color: AppColors.typeVault),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Auto-locks when app goes to background. Full encryption pipeline activates in Phase 09.',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
