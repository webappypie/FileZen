# Phase 08 — Storage Hygiene, Deduplication Engine & Timeline

## Objective
Establish a comprehensive on-device Storage Hygiene, Deduplication, and Timeline architecture for FileZen. The engine strictly enforces the **Zero Silent Deletions Contract** and introduces:
1. **Storage Intelligence & Analysis Engine**: Visual breakdown of total, used, and free storage, category occupancy (Images, Videos, Audio, Documents, APKs, Archives, Other), directory storage treemaps, largest file rankings, and locally recorded usage growth trends.
2. **3-Tier Deduplication Engine**: Cryptographic exact-match clustering:
   - Tier 1: Instant file-size candidate clustering (O(1) bucket sort).
   - Tier 2: Stream-chunked cryptographic checksum calculation (MD5/SHA-256).
   - Tier 3: Cluster synthesis with automated "Keep Original" protection, assigning the earliest modified file as the primary and leaving it unselected by default while selecting redundant duplicates.
3. **Reviewable Cleanup Opportunities**: Specialized heuristic scanners for:
   - Similar & Burst Photos (timestamp proximity within burst window and filename patterns).
   - Blurry & Low-Quality Photos (low file size and naming heuristics).
   - Large Files (> 50 MB threshold ranking).
   - Old APK Installers lingering in Downloads.
   - Old Screenshots (> 14 days).
   - Repeated Downloads (`file (1).ext`, `_copy`).
   - Empty Folders (directories containing zero files or subdirectories).
   - Never-Opened & Dormant Files (> 90 days inactive).
   - Old Voice Recordings (> 30 days).
4. **Safe Recycle Bin (Trash & Recovery Engine)**: Dedicated local `.filezen_trash/` directory and JSON manifest preserving complete file metadata and original file paths. Supports 1-click individual restoration, batch restoration, conflict resolution on restore (appending `_restored` if destination is occupied), permanent deletion, and empty trash.
5. **Storage Timeline Feed**: Chronological media and document browsing grouped into temporal buckets: Today, Yesterday, Earlier This Week, Earlier This Month, [Month Year], and Past Years, with multi-category filters (Images, Videos, Documents, Audio, Archives).
6. **Destructive-Action Contract Dialog**: Standardized modal requiring candidate list preview, item count quantification, space freed calculation, explicit confirmation, and default Recycle Bin routing.

---

## Architecture & Clean Design Principles

### 1. Zero Silent Deletions Contract
Under no circumstances does FileZen automatically delete user content in the background. Every cleanup action:
1. Previews candidate items.
2. Shows exact item count.
3. Shows calculated size impact (e.g. "Free up 142 MB").
4. Requests explicit user confirmation.
5. Routes to Recycle Bin by default for instant recovery.
6. Returns an execution result summary with an Undo/View Trash prompt.

### 2. Clean Architecture Layering
```
Presentation Layer:
  - CleanScreen (Main Hygiene Hub & Safety Contract Banner)
  - DuplicateReviewScreen (Duplicate Sets with Keep Original Protection)
  - CleanupCategoryScreen (Individual Hygiene Category Reviewer)
  - StorageAnalysisScreen (Storage Ring, Treemap, Category Breakdown, Trends)
  - TimelineScreen (Temporal Calendar Buckets & Category Filter Chips)
  - TrashScreen (Recycle Bin with 1-Click Restoration)
  - DestructiveActionDialog (Contract Enforcement Modal)
        ↓
Riverpod Providers:
  - clean_providers.dart (Storage overview, trends, top folders, duplicates, opportunities, trash, timeline)
        ↓
Domain Interfaces & Models:
  - IStorageHygieneService, IDeduplicationService, ITrashRecoveryService, ITimelineService
  - StorageOverview, FolderStorageItem, StorageTrendPoint,
    DuplicateGroup, DuplicateScanProgress,
    CleanupCandidateGroup, CleanupCategoryType, CleanupExecutionPlan, CleanupExecutionResult,
    TrashItem, TimelineGroup, TimelineBucket
        ↓
Data Implementation:
  - StorageHygieneService, DeduplicationService, TrashRecoveryService, TimelineService
        ↓
Database & Filesystem:
  - Drift AppDatabase (FileRecords) & Dart I/O filesystem
```

---

## Detailed Components

### 1. Storage Intelligence (`StorageHygieneService`)
- Reads physical storage capacities from `IStorageRepository.getStorageLocations()`.
- Calculates category sizes and counts by querying SQLite `FileRecords` or falling back to filesystem traversal.
- Ranks top space-consuming directories with child file counts and storage percentages.
- Tracks historical snapshots in `storage_trends.json` to visualize storage growth over time.

### 2. Deduplication Engine (`DeduplicationService`)
- **Tier 1 (Size Clustering)**: Groups files by exact byte size. Single-file sizes are discarded with zero disk read overhead.
- **Tier 2 (Cryptographic Hashing)**: Sizes with $\ge 2$ files are streamed through chunked cryptographic hashing (MD5/SHA-256) to ensure 100% collision-free matching.
- **Tier 3 (Group Synthesis & Original Protection)**: For each checksum cluster, files are sorted chronologically by modification time. The earliest file is designated as `primaryFile` ("KEEP ORIGINAL"). Redundant copies are listed with checkboxes and smart auto-selection.

### 3. Reviewable Cleanup Scanner (`DeduplicationService`)
- **Similar Photos**: Identifies camera burst photos taken within $\le 5$ seconds of each other or sharing burst naming conventions.
- **Blurry Media**: Flags low-resolution thumbnails or photos marked as blurry.
- **Large Files**: Ranks files exceeding configurable threshold (50 MB) descending by size.
- **Old APKs**: Scans installer packages older than 7 days.
- **Old Screenshots**: Scans screenshots older than 14 days.
- **Repeated Downloads**: Regex pattern matching for duplicated browser downloads.
- **Empty Directories**: Recursively identifies zero-byte, zero-item folders and removes them cleanly.
- **Dormant Files**: Detects files untouched for $\ge 90$ days.
- **Old Recordings**: Detects voice notes and audio memos older than 30 days.

### 4. Recycle Bin & Safe Recovery (`TrashRecoveryService`)
- Stores deleted files safely in an isolated `.filezen_trash/` folder.
- Maintains `trash_manifest.json` recording original paths, file sizes, MIME types, and deletion timestamps.
- Restoration automatically recreates parent directories if needed and resolves naming collisions by appending `_restored`.
- Supports 1-click restore, batch restore, individual permanent delete, and Empty Bin.

### 5. Timeline Browser (`TimelineService`)
- Aggregates storage files into calendar buckets:
  - `Today`
  - `Yesterday`
  - `Earlier This Week`
  - `Earlier This Month`
  - `Earlier This Year` (organized by month)
  - `Past Years` (organized by year)
- Supports on-the-fly category filtering across Images, Videos, Documents, Audio, and Archives.

---

## Verification & Testing

### Unit Tests (`test/unit/storage_hygiene_test.dart`):
1. **TrashRecoveryService**:
   - Verified moving files to trash updates manifest and removes from source directory.
   - Verified restoring files restores contents to original path and updates manifest.
   - Verified collision resolution creates `_restored` files when destination exists.
   - Verified permanent deletion and complete empty bin purge.
2. **DeduplicationService**:
   - Verified 3-tier exact duplicate clustering, oldest original designation, and redundant copy selection.
   - Verified similar photos burst detection.
   - Verified blurry photo filtering.
   - Verified large files threshold sorting.
   - Verified old APKs and screenshots age filtering.
   - Verified repeated download copy pattern regex.
   - Verified empty folder recursive discovery and deletion.
   - Verified safe execution routing to Recycle Bin.
3. **StorageHygieneService**:
   - Verified storage overview calculation across categories.
   - Verified top folders ranking and treemap percentage.
   - Verified largest files ranking.
   - Verified storage trend snapshot recording and retrieval.
4. **TimelineService**:
   - Verified chronological calendar bucket classification.
   - Verified category filtering.

### Widget Tests (`test/widget/clean_screen_test.dart`):
1. **CleanScreen**:
   - Verified Zero Silent Deletions Contract banner.
   - Verified storage usage indicator and deep analysis link.
   - Verified navigation shortcut cards (Analysis, Timeline, Recycle Bin).
   - Verified exact duplicate engine banner.
   - Verified reviewable cleanup opportunities list.
2. **DuplicateReviewScreen**:
   - Verified duplicate sets rendering with "KEEP ORIGINAL" badge.
   - Verified "Smart Select Copies" toggle.
   - Verified space impact calculation and clean action.
3. **CleanupCategoryScreen**:
   - Verified candidate items display, select all toggle, and clean action.
4. **StorageAnalysisScreen**:
   - Verified category occupancy breakdown, usage trends, and top space-consuming folders.
5. **TrashScreen**:
   - Verified recycle bin items display, safe recovery banner, restore button, and permanent delete button.
6. **TimelineScreen**:
   - Verified filter chips and chronological calendar headers.
7. **DestructiveActionDialog**:
   - Verified candidate preview, item count, space freed, and "Move to Recycle Bin" toggle.

---

## Phase Gate Checklist
- [x] All 10 hygiene categories implemented and accessible via UI.
- [x] 3-tier duplicate detection algorithm implemented with stream hashing.
- [x] Zero Silent Deletions Contract enforced with preview, impact, confirmation, and recovery.
- [x] Recycle Bin (Trash) with 1-click restore and conflict resolution.
- [x] Storage Intelligence dashboard with treemap and historical trend tracking.
- [x] Chronological Timeline Browser with category filters.
- [x] Unit test suite passing (`18/18` unit tests).
- [x] Widget test suite passing (`7/7` widget tests).
- [x] Entire project test suite passing (`133/133` tests with zero failures).
- [x] `flutter analyze` passing with 0 warnings or lint issues.
