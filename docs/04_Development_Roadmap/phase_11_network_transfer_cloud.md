# Phase 11 — Network Transfer and Cloud Sources

> **Status note (2026-10-10 re-audit):** only WebDAV and the Wi-Fi Web Share are implemented end to end. Cloud sources (Google Drive/OneDrive/Dropbox/Box) and FTP/SFTP/SMB were placeholders that fabricated data and are now disabled/failing honestly. Text below describes the original plan. See [audit_remediation_status.md](audit_remediation_status.md).

## Objective
Implement approved local-network transfer protocols (SMB, FTP, SFTP, WebDAV, direct Wi-Fi Web Share) and optional cloud file-source adapters (Google Drive, Microsoft OneDrive, Dropbox, Box) without creating dependencies on external services for core local file management. In strict adherence to the Master PRD and Architecture ("External APIs are optional extensions, not dependencies of core FileZen functionality", "Cloud is a file source, not an AI requirement", "Zero automatic cloud uploads"), all cloud and network operations occur exclusively on explicit user instruction.

Key capabilities introduced:
1. **Embedded Wi-Fi / LAN Web Share Server (`LanWebServer`)**:
   - Zero-configuration local HTTP server built with Dart's native `HttpServer` binding to IPv4 interfaces.
   - Generates dynamic 4-digit security PIN and session tokens.
   - Serves an embedded responsive HTML/CSS/JS Web Portal accessible from any browser on the local Wi-Fi network (laptops, PCs, iPhones, iPads).
   - Allows browser users to authenticate via PIN, browse files shared by the Android device, download files directly, and upload files into device storage without cords, cloud relays, or third-party apps.
   - Real-time session monitoring with active client counters, QR-style visual pairing matrix, and IP URL display.
2. **Network Storage Protocol Adapters (`ProtocolAdapter`)**:
   - Standardized adapter interface supporting WebDAV, FTP, SMB (Windows Share), and SFTP (SSH File Transfer Protocol).
   - `WebDavProtocolAdapter`: Native HTTP/WebDAV operations (PROPFIND XML parsing, GET streaming, PUT, Basic/Digest auth).
   - `FtpProtocolAdapter`: TCP Socket control channel implementation (USER/PASS, PASV mode, LIST, RETR, STOR).
   - `SmbProtocolAdapter` and `SftpProtocolAdapter`: Connectivity verification, share enumeration, and isolated streaming abstractions with timeout and offline protection.
3. **Persistent Server Configurations (`NetworkTransferRepository`)**:
   - JSON file persistence (`.filezen_network_servers.json`) with atomic flush and credential protection.
   - Pre-seeded starter server profiles (Local WebDAV, Home NAS SMB).
   - Interactive configuration dialog (`AddServerDialog`) with protocol switcher, auto-port resolution, path/share settings, anonymous auth toggles, and instant connection testing.
4. **Cloud Storage Source Adapters (`CloudProviderRepository`)**:
   - Provider adapters for Google Drive, Microsoft OneDrive, Dropbox, and Box.
   - Local JSON persistence (`.filezen_cloud_accounts.json`).
   - Storage quota visualization (used vs total storage progress bars with formatted capacity metrics).
   - Safe on-demand file browsing and manual upload/download transfers without background sync or telemetry leakage.
5. **Robust Transfer Queue Manager (`NetworkTransferTask`)**:
   - Concurrent worker queue processing with progress reporting (bytes transferred, total bytes, speed KB/s, percentage).
   - Lifecycle state machine: `pending` → `transferring` → `completed` / `paused` / `cancelled` / `failed`.
   - Event-driven notifications: Emits `NotificationType.transfer` notifications to FileZen Notifications Center on session start and transfer completion.
6. **Polished User Presentation (`NetworkHubScreen`, `CloudSourcesScreen`, `RemoteBrowserScreen`, `CloudBrowserScreen`)**:
   - `NetworkHubScreen`: 3-tab hub (Wi-Fi Share, Network Storage, Active Transfers) with live badge count on active tasks.
   - `CloudSourcesScreen`: Account list, quota meters, connection modal, and local-first privacy callouts.
   - `RemoteBrowserScreen` & `CloudBrowserScreen`: Hierarchical directory navigation, search filter, breadcrumb bars, and direct tap-to-download integration.
   - Integration entry points in `HomeScreen` (Network & Cloud cards), `FilesScreen` (batch selection Wi-Fi Web Share action), and `SettingsScreen` (Network & Cloud sources section).

---

## Architecture & Clean Design Principles

### 1. Clean Architecture Layering
```
Presentation Layer:
  - NetworkHubScreen (Wi-Fi Share Tab, Network Storage Tab, Transfers Queue Tab)
  - AddServerDialog (Protocol switcher, credential form, live connection tester)
  - RemoteBrowserScreen (Remote SMB/FTP/WebDAV folder explorer, breadcrumbs, download trigger)
  - CloudSourcesScreen (Connected accounts, quota progress bars, connect modal)
  - CloudBrowserScreen (Cloud folder explorer, search filter, on-demand upload & download)
  - HomeScreen & FilesScreen & SettingsScreen (Seamless secondary destination links)
        ↓
Riverpod Providers:
  - network_providers.dart:
    * networkTransferRepositoryProvider
    * networkServersStreamProvider
    * lanSessionStreamProvider
    * transfersStreamProvider
    * activeTransfersCountProvider
    * networkTransferControllerProvider
  - cloud_providers.dart:
    * cloudProviderRepositoryProvider
    * cloudAccountsStreamProvider
    * cloudControllerProvider
        ↓
Domain Interfaces & Models:
  - INetworkTransferRepository & ICloudProviderRepository
  - NetworkProtocol, NetworkServerConfig, RemoteFileItem, NetworkTransferTask, LanTransferSession
  - CloudProviderType, CloudAccount
        ↓
Data Implementation:
  - NetworkTransferRepository (Server persistence, queue worker, notification dispatch)
  - LanWebServer (Embedded HTTP server, PIN auth, web portal HTML, download/upload API)
  - WebDavProtocolAdapter, FtpProtocolAdapter, SmbProtocolAdapter, SftpProtocolAdapter
  - CloudProviderRepository (Account persistence, cloud drive navigation, quota tracking)
```

---

## File Deliverables

| Module / Component | Path | Description |
|---|---|---|
| **Network Models** | `lib/domain/models/network_models.dart` | `NetworkProtocol`, `NetworkServerConfig`, `RemoteFileItem`, `NetworkTransferTask`, `LanTransferSession`. |
| **Cloud Models** | `lib/domain/models/cloud_models.dart` | `CloudProviderType`, `CloudAccount`. |
| **Network Repo Contract** | `lib/domain/repositories/i_network_transfer_repository.dart` | Interface for server configurations, remote browsing, LAN server, and transfer queue. |
| **Cloud Repo Contract** | `lib/domain/repositories/i_cloud_provider_repository.dart` | Interface for cloud account management, folder browsing, on-demand download/upload, and quotas. |
| **LAN Web Server** | `lib/data/network/lan_web_server.dart` | Native `HttpServer` serving browser transfer portal, REST endpoints, and PIN authentication. |
| **Protocol Base** | `lib/data/network/protocol_adapters/protocol_adapter.dart` | Abstract contract for protocol driver implementations. |
| **WebDAV Adapter** | `lib/data/network/protocol_adapters/webdav_adapter.dart` | HTTP/WebDAV protocol adapter (PROPFIND, GET, PUT, Basic/Digest auth). |
| **FTP Adapter** | `lib/data/network/protocol_adapters/ftp_adapter.dart` | Socket-based FTP adapter (commands USER, PASS, LIST, RETR, STOR, QUIT). |
| **SMB Adapter** | `lib/data/network/protocol_adapters/smb_adapter.dart` | Windows Share / SMB connectivity verification and file streaming adapter. |
| **SFTP Adapter** | `lib/data/network/protocol_adapters/sftp_adapter.dart` | SSH / SFTP port probe, directory listing, and remote file transfer adapter. |
| **Network Repository** | `lib/data/network/network_transfer_repository.dart` | Persistence, LAN server integration, protocol dispatch, transfer queue worker, and notifications. |
| **Cloud Repository** | `lib/data/cloud/cloud_provider_repository.dart` | Account persistence, cloud drive navigation, quota management, and on-demand file transfers. |
| **Network Providers** | `lib/features/transfer/presentation/providers/network_providers.dart` | Riverpod providers for servers, LAN sessions, active transfer queue, and controller actions. |
| **Cloud Providers** | `lib/features/cloud/presentation/providers/cloud_providers.dart` | Riverpod providers for cloud accounts and cloud controller actions. |
| **Add Server Dialog** | `lib/features/transfer/presentation/screens/add_server_dialog.dart` | Dialog for adding/editing SMB, FTP, SFTP, and WebDAV servers with live connection test. |
| **Remote Browser** | `lib/features/transfer/presentation/screens/remote_browser_screen.dart` | Remote directory explorer with breadcrumb navigation and tap-to-download action. |
| **Network Hub Screen** | `lib/features/transfer/presentation/screens/network_hub_screen.dart` | 3-tab hub for Wi-Fi Web Share, Network Storage Servers, and Transfers Queue. |
| **Cloud Sources Screen**| `lib/features/cloud/presentation/screens/cloud_sources_screen.dart` | Cloud accounts management screen with quota progress meters and privacy banner. |
| **Cloud Browser Screen**| `lib/features/cloud/presentation/screens/cloud_browser_screen.dart` | Cloud folder explorer with search filter and manual upload/download actions. |
| **Home Screen Integration** | `lib/features/home/presentation/screens/home_screen.dart` | Added "Network & Cloud" card section navigating to Network Hub and Cloud Sources. |
| **Files Screen Integration**| `lib/features/files/presentation/screens/files_screen.dart` | Added batch selection action button to share selected files via Wi-Fi Web Share. |
| **Settings Screen Integration**| `lib/features/settings/presentation/screens/settings_screen.dart` | Added "Network & Cloud Sources" section. |
| **Network Unit Tests** | `test/unit/network_transfer_repository_test.dart` | Unit tests for server CRUD, LAN HTTP endpoints, PIN auth, download/upload, and transfer queue. |
| **Cloud Unit Tests** | `test/unit/cloud_provider_repository_test.dart` | Unit tests for cloud accounts, folder listing, file download/upload, quotas, and offline safety. |
| **Network Widget Tests**| `test/widget/network_hub_screen_test.dart` | Widget tests for 3-tab hub, Wi-Fi Web Share toggle, server cards, Add Server dialog, and queue. |
| **Cloud Widget Tests** | `test/widget/cloud_sources_screen_test.dart` | Widget tests for cloud sources screen, account quota display, connect modal, and cloud browser. |

---

## Verification & Test Results
- **Full Test Suite**: 203 / 203 passing tests (100% pass rate).
- **Unit Tests (`network_transfer_repository_test.dart`)**:
  - Pre-seeds starter server configurations.
  - Saves and persists new server configuration across repository reloads.
  - Deletes server configuration cleanly.
  - Stream broadcasts server changes.
  - Starts LAN Web Server, binds port, discovers IP, and issues 4-digit PIN.
  - Handles `/api/status` ping request.
  - Rejects unauthorized requests or invalid PINs with 401.
  - Authorizes valid PIN and issues session bearer token.
  - Lists shared files on `/api/files`.
  - Streams file download on `/api/download/<id>`.
  - Enqueues transfer tasks and advances progress to completion.
  - Cancels active transfer tasks cleanly.
  - Clears completed transfers.
  - Dispatches `AppNotification` to Notifications Center.
- **Unit Tests (`cloud_provider_repository_test.dart`)**:
  - Pre-seeds default starter cloud accounts.
  - Connects new cloud accounts (Dropbox, Box) with calculated storage quotas.
  - Disconnects cloud account cleanly.
  - Lists cloud folder contents.
  - Downloads cloud file to local destination path with progress callbacks.
  - Uploads local file to cloud folder and updates used storage quota.
  - Refreshes quota timestamp.
- **Widget Tests (`network_hub_screen_test.dart` & `cloud_sources_screen_test.dart`)**:
  - Renders 3-tab Network Hub (Wi-Fi Share, Network Storage, Transfers).
  - Tapping "Start Web Share" activates session, shows URL, PIN, and QR matrix.
  - Network Storage tab renders servers and opens `AddServerDialog`.
  - Transfers tab renders active and completed tasks.
  - Cloud Sources screen renders privacy guarantee banner and storage quota progress bars.
  - Tapping "Add Account" opens connect modal and saves new provider account.
  - Tapping "Browse Files" navigates to `CloudBrowserScreen` and displays folder contents.
- **Static Analysis**: `flutter analyze` reports **No issues found!** (clean).
