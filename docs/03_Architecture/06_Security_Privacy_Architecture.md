# Security and Privacy Architecture

## Principles

- Least privilege.
- Local-first.
- Explicit consent.
- No sensitive data in logs.
- No secrets in source control.
- Vault data isolated from normal previews/search where required.
- User-controlled destructive operations.

## Android security

Use Android Keystore/biometric APIs for appropriate credential protection. Sensitive vault content should use authenticated encryption with keys protected by platform facilities.

## Permissions

Request only permissions required for the current task. Explain why a permission is needed. Handle denial, partial access, revocation, and settings changes.

## Vault

Vault indexing must be separated from normal indexing according to the approved threat model. Private thumbnails/previews must not leak into public caches, notifications, analytics, or share targets.

## Secure deletion

Secure deletion claims must be conservative because filesystem/storage layers may prevent guaranteed physical overwriting. Prefer logical deletion plus recovery controls unless a platform-supported stronger guarantee exists.
