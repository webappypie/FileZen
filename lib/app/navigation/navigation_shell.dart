import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_constants.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/files/presentation/screens/files_screen.dart';
import '../../features/ai/presentation/screens/ai_screen.dart';
import '../../features/clean/presentation/screens/clean_screen.dart';
import '../../features/vault/presentation/screens/vault_screen.dart';
import '../../features/vault/presentation/widgets/secure_surface.dart';
import '../../features/notifications/presentation/providers/notification_providers.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import 'navigation_provider.dart';

class NavigationShell extends ConsumerWidget {
  const NavigationShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(currentTabProvider);

    final titles = [
      AppConstants.appName,
      'Files',
      'AI Intelligence',
      'Storage Clean',
      'Vault',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[currentTab]),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Universal Search',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              );
            },
          ),
          Builder(
            builder: (context) {
              final unreadCountAsync = ref.watch(unreadNotificationCountProvider);
              final hasUnread = (unreadCountAsync.valueOrNull ?? 0) > 0;

              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: 'Notifications Center',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      );
                    },
                  ),
                  if (hasUnread)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      // The Vault tab (index 4) blocks screenshots / recents thumbnails while visible.
      body: SecureSurface(
        active: currentTab == 4,
        child: IndexedStack(
          index: currentTab,
          children: const [
            HomeScreen(),
            FilesScreen(),
            AiScreen(),
            CleanScreen(),
            VaultScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentTab,
        onDestinationSelected: (index) {
          ref.read(currentTabProvider.notifier).state = index;
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Files',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.cleaning_services_outlined),
            selectedIcon: Icon(Icons.cleaning_services_rounded),
            label: 'Clean',
          ),
          NavigationDestination(
            icon: Icon(Icons.lock_outline_rounded),
            selectedIcon: Icon(Icons.lock_rounded),
            label: 'Vault',
          ),
        ],
      ),
    );
  }
}
