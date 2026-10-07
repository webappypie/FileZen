# 07 — Release Checklist

## Product

- [ ] All approved V1 requirements implemented.
- [ ] Non-goals remain excluded.
- [ ] Major user flows reviewed.
- [ ] Empty/loading/error states reviewed.
- [ ] Accessibility reviewed.
- [ ] Dark/light themes reviewed.

## Storage

- [ ] Permissions verified.
- [ ] Copy/move/rename/delete verified.
- [ ] Large files verified.
- [ ] Interrupted operations verified.
- [ ] SAF locations verified where supported.
- [ ] SD/OTG behavior verified where supported.

## AI

- [ ] Local processing works without internet where designed.
- [ ] No automatic cloud upload.
- [ ] AI failures have deterministic fallback.
- [ ] AI suggestions require appropriate confirmation.
- [ ] Model/data footprint reviewed.

## Security

- [ ] Vault tested.
- [ ] Secrets excluded from repository.
- [ ] Logs contain no sensitive file contents.
- [ ] Private files are excluded from unintended previews/share flows.
- [ ] Release signing configuration verified.

## Notifications

- [ ] Bell icon works.
- [ ] Manual/admin notification handling works.
- [ ] App-generated notification handling works.
- [ ] Read/unread state works.
- [ ] Individual dismiss works.
- [ ] Clear All works.
- [ ] Notification failure does not break the app.

## Monetization

- [ ] Ad placements are non-intrusive.
- [ ] Ads do not block core file operations.
- [ ] One-time ad-removal flow works.
- [ ] Provider failure falls back safely.
- [ ] No subscription paywall is accidentally introduced.

## WAPCentral

- [ ] `WAPCentral_App_Integration_Guide` reviewed.
- [ ] App ID/configuration verified.
- [ ] SDK integration verified.
- [ ] Integration works when WAPCentral is unavailable.
- [ ] No credentials committed.

## Release engineering

- [ ] Clean release build.
- [ ] Upgrade from previous version tested.
- [ ] Database migrations tested.
- [ ] Crash-free smoke test.
- [ ] Final Git tag created.
- [ ] Release notes prepared.
- [ ] Store assets/legal requirements verified.
