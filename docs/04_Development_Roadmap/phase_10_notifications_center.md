# Phase 10 — Notifications Center

## Objective
Establish a dedicated, event-driven in-app Notifications Center for FileZen. In strict adherence to the Master PRD ("Do not generate noisy notifications merely to increase engagement"), the Notifications Center alerts users only to meaningful file-lifecycle events, storage health warnings, on-device AI processing updates, and security notices.

Key capabilities introduced:
1. **Persistent Local Notification Storage (`NotificationRepository`)**:
   - Lightweight, cross-platform JSON file persistence (`.filezen_notifications.json`) with atomic flush.
   - Broadcast live streams (`Stream<List<AppNotification>>` and `Stream<int>`) for instant UI synchronization.
   - Pre-seeded starter events (Welcome to FileZen, Storage Safety Contract Active, 100% Offline AI Ready).
2. **Safe Offline Operation & Remote Sync**:
   - `syncRemoteNotifications({bool isOnline = true})` checks connectivity; in offline scenarios, it completes gracefully without throwing exceptions or blocking the user experience.
   - When online, safely integrates administrative updates and feature release notices.
3. **Event-Driven App Notifications**:
   - System notices (e.g. initial onboarding, offline status, app version announcements).
   - Storage alerts (e.g. disk space exceeding thresholds, cleanup opportunities).
   - Duplicate detection alerts (e.g. exact duplicate clusters discovered with recoverable space metrics).
   - Security alerts (e.g. vault auto-lock notices, sensitive export boundary warnings).
   - On-device AI completion alerts (e.g. background indexing completed).
4. **Rich Interactive Presentation (`NotificationsScreen`)**:
   - Category filter chips (All, Unread with live count badge, Storage, Security, AI, System).
   - Read/unread visual distinction with accent category coloring and unread indicators.
   - Relative timestamps ("Just now", "5m ago", "2h ago", "1d ago").
   - Deep linking: Direct action buttons navigate to target screens (`/clean`, `/clean/duplicates`, `/vault`, `/ai`, `/settings`).
   - Dismissible swipe-to-delete with background undo/feedback snackbars.
   - "Mark all as read" and "Clear all notifications" actions with confirmation safeguard.
   - Empty state view (`EmptyView`) when all notifications are caught up.
5. **Reactive App Shell Badge (`NavigationShell`)**:
   - Navigation AppBar bell icon is reactively wired to `unreadNotificationCountProvider`.
   - The unread badge dot automatically displays when unread notifications exist (`> 0`) and automatically disappears when all items are read or cleared (`== 0`).

---

## Architecture & Clean Design Principles

### 1. Clean Architecture Layering
```
Presentation Layer:
  - NotificationsScreen (Header, Filter Chips, List View, Actions)
  - NotificationCard (Category-coded icon, relative time, swipe-dismiss, action button)
  - NotificationFilterChips (Filter chips with unread count indicator)
  - NavigationShell (Reactive unread badge dot in top action bar)
        ↓
Riverpod Providers:
  - notification_providers.dart:
    * notificationRepositoryProvider
    * notificationsStreamProvider
    * unreadNotificationCountProvider
    * notificationFilterProvider
    * filteredNotificationsProvider
    * notificationControllerProvider
        ↓
Domain Interfaces & Models:
  - INotificationRepository
  - AppNotification, NotificationType, NotificationPriority, NotificationFilter
        ↓
Data Implementation:
  - NotificationRepository (JSON persistence, broadcast controllers, offline sync, event factories)
```

---

## File Deliverables

| Module / Component | Path | Description |
|---|---|---|
| **Domain Models** | `lib/domain/models/notification_models.dart` | `AppNotification`, `NotificationType`, `NotificationPriority`, `NotificationFilter`. |
| **Repository Interface** | `lib/domain/repositories/i_notification_repository.dart` | Contract for notifications listing, reactive streams, unread counts, mutations, and offline sync. |
| **Repository Data** | `lib/data/notifications/notification_repository.dart` | JSON file persistence, broadcast stream controllers, starter seeds, offline sync, and event factory helpers. |
| **Riverpod Providers** | `lib/features/notifications/presentation/providers/notification_providers.dart` | State providers for notifications streams, unread count, filter selection, and controller actions. |
| **Notification Card** | `lib/features/notifications/presentation/widgets/notification_card.dart` | Interactive card with category icons, relative time formatting, swipe-to-delete, and deep-link actions. |
| **Filter Chips** | `lib/features/notifications/presentation/widgets/notification_filter_chips.dart` | Horizontal filter chips bar with live unread count badge. |
| **Notifications Screen** | `lib/features/notifications/presentation/screens/notifications_screen.dart` | Notifications Center screen with filtering, deep linking, mark all as read, and clear all. |
| **Navigation Shell Integration** | `lib/app/navigation/navigation_shell.dart` | Connected bell action button to `unreadNotificationCountProvider` for reactive badge display. |
| **Unit Tests** | `test/unit/notification_repository_test.dart` | 11 unit tests for persistence, stream emissions, unread count, mark as read, delete, clear, and offline sync. |
| **Widget Tests** | `test/widget/notifications_screen_test.dart` | 6 widget tests for screen rendering, filtering, mark all read, clear all, deep-link navigation, and reactive badge. |

---

## Verification & Test Results
- **Full Test Suite**: 180 / 180 passing tests (100% pass rate).
- **Unit Tests (`notification_repository_test.dart`)**:
  - Pre-seeds default starter notifications on fresh storage.
  - Calculates unread count accurately.
  - Adds new notification and prepends to list.
  - Marks individual notification as read.
  - `markAllAsRead` sets all items read and resets count to 0.
  - Deletes individual notification cleanly.
  - `clearAll` removes all notifications.
  - Persistence round-trip verifies saved items restore on new repository instance.
  - Offline synchronization completes safely without errors or crashes.
  - Synchronizes remote announcement when online.
  - Event factory helpers construct properly typed storage, duplicate, and vault alerts.
- **Widget Tests (`notifications_screen_test.dart`)**:
  - Renders notifications screen with header, filter chips, and cards.
  - Filters list by selecting filter chips (Unread, Storage, AI, All).
  - Tapping "Mark All as Read" marks all items read.
  - "Clear All" empties list and displays `EmptyView`.
  - Tapping deep link action opens target screen (e.g. `CleanScreen`).
  - Reactive badge in `NavigationShell` displays dot when `unreadCount > 0` and hides when `unreadCount == 0`.
- **Static Analysis**: `flutter analyze` reports **0 issues found** (clean).
