# Full Application Audit & Repair — 2026-10-10

**Branch:** `claude/sweet-ride-xluwcf` (base `d93a2a8`)
**Scope:** complete debugging / functionality / performance pass requested by the owner. The PRD,
architecture documents and earlier decisions (`audit_remediation_status.md`,
`DECISION_LOG_ISSUE_7_VAULT_SECURITY.md`) remain the source of truth; nothing was removed to look stable.
**Status:** fixes implemented and verified on the host (analyze + tests + benchmark).
**Nothing in this pass was verified on a phone or emulator.** See §5.

## 1. Verification environment (read first)

| Item | State |
|---|---|
| Flutter | 3.47.7 stable (Dart 3.13.5), installed for this run |
| Dependencies | resolved from the committed `pubspec.lock`; lockfile, `pubspec.yaml`, Gradle files and `.gitignore` unchanged |
| WAPCentral SDKs | `wap_ads_sdk` and `wap_promo_sdk` come from the public `webappypie/wapcentral` repo. `wap_core_sdk` and `wap_notifications_sdk` exist only on the owner's machine, and that repo's `wap_ads_sdk` lacks `WapAds`. Small **verification-only shims** were placed in the local `../WAPCentral` clone (never committed) so the app compiles. Ads, promo and notification behaviour is therefore **not verified** |
| Android SDK | **Not installable** (the environment's network policy blocks `dl.google.com`). No APK build, no Gradle tasks |
| Native Kotlin | `DeviceChannel.kt` (new) type-checked with `kotlinc` 2.1.21 against Robolectric `android-all` (API 34) + the Flutter embedding jar. `VaultCryptoTest` (10 tests) compiled with `kotlinc` and run with JUnit 4 directly. `MainActivity.kt` (3-line channel wiring) not compiled: AndroidX jars unavailable |

## 2. Issue inventory

Severity: C = critical, H = high, M = medium, L = low. "Host-verified" means covered by automated tests
on real files, SQLite and widgets on the host. Device behaviour is not verified for any of them.

| ID | Sev | Issue (how it reproduces) | Root cause | Fix | Regression tests | Status |
|---|---|---|---|---|---|---|
| AUD-01 | H | Home showed ~35% used, Storage Intelligence ~50% | Neither was measured. Home hard-coded 46/128 GB (35.9% truncated). `getStorageLocations()` returned a nominal 128 GB / 64 GB free for **both** "Internal" and "Downloads" (one volume), and Storage Intelligence summed them: 256/128 GB = 50.0% | Native `StatFs` (`DeviceChannel.storageStats`). One `deviceStorageStatsProvider` feeds Home and the overview; one rounding rule; "unavailable" when unmeasurable; indexed totals labelled separately | `storage_consistency_test`, `storage_hygiene_test` | Fixed, host-verified |
| AUD-02 | H | Video rows always showed a movie icon | No thumbnail pipeline existed | `ThumbnailService` + native single-frame extraction, disk cache (path+size+mtime), 2 concurrent, off-screen skip, failure memo, cache trim, Vault eviction | `thumbnail_service_test`, `video_thumbnail_widget_test` | Fixed; **frames not seen on a device** |
| AUD-03 | H | Fresh install: every Home category reads "0 items" until the user finds "Scan Storage" in Search | Indexing was only started from a Search button | `IndexingCoordinator`: scan after launch once access is granted, on resume (≥10 min apart), every 30 min while open; paused in background; refreshes all index-derived views | `indexing_coordinator_test`, `home_screen_test` | Fixed, host-verified |
| AUD-04 | H | Indexing large libraries was quadratic | No indexes on `file_records` (a `WHERE path=?` per file); `DELETE … WHERE file_id=?` on an UNINDEXED FTS5 column scanned the whole FTS table per file | Schema v3 indexes + `search_doc_rowids` map (migration backfills); one preloaded path map; batched transactions | `database_migration_test` (real v2→v3 upgrade), benchmark | Fixed, host-verified |
| AUD-05 | H | Short query ("a") on a big index: huge result sets / "too many SQL variables" | FTS had no LIMIT; every id went into one `IN (…)` | Cap 500, chunked record fetch, browse queries limited | benchmark (`hits == 500`) | Fixed, host-verified |
| AUD-06 | H | DOCX/XLSX/PPTX opened from Search, Ask Your Files, Smart Collection or Related Files showed binary garbage; ZIP/APK showed a fake "Opening …" snackbar | Four duplicated openers bypassed the central resolver | `FileTypeResolver` (signature sniffing first, then extension/MIME; NUL bytes never go to the text viewer; SVG → markup); all entry points use `FileViewerResolver` | `file_type_resolver_test` (real PDF/OOXML/ZIP files etc.) | Fixed, host-verified |
| AUD-07 | H | Possible multi-second UI freeze at launch on a fresh install | Clean tab is built at startup (IndexedStack); with an empty index its duplicate/timeline scans did a **synchronous recursive `listSync` of all shared storage** on the UI isolate; empty-folder scan always did | `FileWalker` (async + yields); whole-device fallback skipped when the index is empty | existing hygiene tests | Fixed (host); **jank not measured on device** |
| AUD-08 | H | Deleting in a category list: files reappear, counts unchanged, failures reported as success. Files tab batch delete: "Deleted N" even if some failed, and those still-existing files dropped from the index | Category delete never touched the index and swallowed errors; `batchDelete` swallows per-file errors | `FileDeletion`: verify each path is gone, un-index/evict only those, honest summary | `file_deletion_test` | Fixed, host-verified |
| AUD-09 | H | Files deleted outside FileZen stayed in search/categories forever | Scans never pruned | Prune after discovery, never under unreadable folders | `indexing_incremental_test` | Fixed (unreadable-folder case only asserted when permissions are enforced; the host runs as root) |
| AUD-10 | M | Downloads indexed twice per scan | Downloads root is inside Internal Storage | `distinctRoots` | `storage_consistency_test`, `indexing_coordinator_test` | Fixed |
| AUD-11 | M | OCR made the first scan very slow and ignored battery/heat; a new ML Kit recognizer per image | OCR inline in the scan | Separate OCR pass tracked in `ocr_state` (never twice per version), deferred under battery saver / <20% not charging / thermal ≥ SEVERE, shared recognizer, >30 MB images skipped | `indexing_incremental_test` | Fixed (host, with an injected recognizer); **ML Kit output not verified on device** |
| AUD-12 | M | Vault: two different setup flows (Vault tab had no confirmation); no recovery warning; an empty PIN on the Vault tab started a biometric prompt even when biometrics were off | UX built ad hoc | Single `VaultSetupScreen`; PIN unlock + biometric button only when enabled | `vault_screen_test` | Fixed (widget-level) |
| AUD-13 | M | "Export to Storage" always wrote to `Download`, silently ignored failures, and actually removed the item from the Vault | Label/flow mismatch | "Move out of Vault": confirm, original folder (fallback Downloads), re-index, error message | — (service already tested) | Fixed |
| AUD-14 | M | Auto-lock "after 30 s / 1 / 5 min" kept the key in memory for the whole background period | Lock only evaluated on resume | Timer locks when the timeout elapses in background | `vault_security_surface_test` | Fixed, host-verified |
| AUD-15 | M | Storage "Usage Trends" showed invented history | Hard-coded baseline points | Real points every ≥12 h; empty state otherwise | `storage_hygiene_test` | Fixed |
| AUD-16 | M | Tapping a search result showed a dialog instead of opening; no file actions | — | Tap opens; menu: Open, Details, Favorite, Move to Vault; thumbnails | `search_screen_test` | Fixed |
| AUD-17 | M | PRD FZ-FM-004 (favorites/recent) missing: no Recent or Favorites on Home, no way to set a favorite | Not implemented | Home strips, full lists, toggles in category/Files/Search; favorites survive re-index | `home_screen_test`, `indexing_incremental_test` | Implemented, host-verified |
| AUD-18 | L | Category list re-sorted the whole category on every selection tap and sorted the provider's list in place | — | Memoised copy | — | Fixed |
| AUD-19 | L | Backgrounding showed "Indexing paused" even with no scan; a paused scan allowed a second concurrent scan | `pause()` always emitted; `isRunning` excluded `paused` | — | existing + coordinator tests | Fixed |
| AUD-20 | L | "Recent Tax Receipts & Invoices" ordered by rank | — | Newest first | — | Fixed |
| AUD-21 | L | Indexing progress subscription never cancelled | — | Cancelled on dispose | — | Fixed |

## 3. Measured performance (host, real files, `FILEZEN_BENCH=100000 flutter test test/perf`)

| Operation (100,000 files) | Before | After |
|---|---|---|
| Unchanged re-scan | 36.4 s (already with the new indexes) | 5.5 s |
| 1 deleted + 1 new file | 36.0 s | 5.4 s |
| First full index | — | 132 s (one-time; yields to the UI throughout) |
| FTS "invoice" / prefix "i*" | — | 59 ms / 150 ms (500-result cap) |
| Storage overview / top folders / largest / category counts | — | 81 / 297 / 3 / 94 ms |

Without the v3 indexes and FTS rowid map the per-file work was O(n) per file (O(n²) per scan); it was
not timed at 100k. Host is a desktop container; phones are slower — compare builds, do not read these as device timings.

## 4. Remaining items / limits (not fixed here)

1. **Indexing while FileZen is closed** needs a WorkManager job → new dependency (`workmanager`) requires owner approval. Today: startup, resume, periodic while open.
2. **First full index runs on the UI isolate** with yields (132 s / 100k files on the host). Moving it to a background isolate is the next step if devices show jank.
3. **Category / Recent lists** load the whole category into memory (fine for tens of thousands; not paginated).
4. **SAF**: FileZen browses with file paths under All-files access. The native thumbnailer accepts `content://` URIs, but there are no SAF document-tree flows.
5. Mixed extension convention in the index (`.pdf` from scans, `pdf` from single-file indexing) is tolerated by every reader (normalised), not migrated.
6. Smart-collection keyword rules (e.g. `id*`) are broad; product decision.
7. Owner actions from `audit_remediation_status.md` §6 still open (Billing, X-App-Key rotation, cloud/FTP/SMB scope, 100 MB vault item cap, pdfx).

## 5. Device checklist additions (in addition to `audit_remediation_status.md` §7)

1. Home and Storage Intelligence show the same "% used" as Android Settings › Storage (Android counts system; FileZen measures the shared volume via StatFs — small differences vs Settings are expected, between the two FileZen screens there must be none).
2. Videos in Home › Videos, Recent, Search show real frames; scroll a folder of 500+ videos without jank; edit/replace a video → new frame.
3. Fresh install → grant All-files access → categories fill without visiting Search; take a photo, return to FileZen → it appears (within the resume/periodic window).
4. Battery saver on → "images waiting for text recognition" in Search; off → OCR resumes on the next scan.
5. Vault: first setup from Vault tab and from "Move to Vault" (single and multi-select) → same screen; biometric switch only on devices with biometrics; "Move out of Vault" restores into the original folder; auto-lock 30 s locks while backgrounded.
6. Open one real file of each type from Search and from a category (PDF, DOCX, XLSX, PPTX, ZIP, TXT, CSV, JSON, XML, HTML, JPG, MP4, MP3, APK).
