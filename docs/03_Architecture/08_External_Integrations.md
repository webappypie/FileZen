# External Integrations

## Principle

External APIs are optional extensions, not dependencies of core FileZen functionality.

## Integration classes

### Cloud file providers
Potential sources:
- Google Drive
- OneDrive
- Dropbox
- Box

Cloud is a file source, not an AI requirement.

### Network
Potential protocols:
- SMB
- FTP
- SFTP
- WebDAV
- LAN/browser transfer.

### WAPCentral
WAPCentral controls ecosystem-level functionality such as notifications, multiple ad networks, custom app promotion, and related app-side services.

**Boundary:** FileZen implements the app-side SDK/client contract only. The separate `WAPCentral_App_Integration_Guide` is authoritative for integration details.

## Failure behavior

Any external integration must:
- time out;
- retry conservatively;
- surface meaningful errors;
- cache safe local state;
- not block local file management;
- support offline operation where applicable.
