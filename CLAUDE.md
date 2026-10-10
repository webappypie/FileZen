# FileZen — Claude Code instructions

## Start here
- Read `QUICK_START.md` first and follow its reading order and AI-agent startup protocol.
- Follow the existing project documentation (`01_`–`07_` docs, `docs/`, `prompts/`, `FileZen_PreRelease_Remediation_Plan.md`). Don't make product decisions silently.

## How to work
- Preserve the existing Gemini implementation (the remediation sprint work). Don't rewrite, revert, or replace it. Fix it in place.
- Find the root cause before editing: reproduce the problem, read the code involved, and explain the cause before changing anything.
- Keep changes minimal and on-task. No unrelated refactoring, renames, or reformatting.
- Preserve uncommitted Git changes and untracked files. Don't run destructive Git commands (`reset`, `clean`, `restore`, `checkout`, `stash`, `push`) without explicit approval.
- Ask before changing dependencies (`flutter pub get/upgrade`), running code generation (`dart run build_runner`), or running formatters that rewrite files.

## Secrets
- Never open, print, copy, or commit `08_Credentials.md`, `android/key.properties`, or any `*.jks` / `*.keystore` file.
- Never put credentials or signing details in code, logs, docs, or chat.

## Verify and report
- After a fix, run the relevant checks: `flutter analyze` and the related `flutter test <path>` (or the full `flutter test`).
- When finishing, list every file modified or created, and report test and analyze results exactly, failures included.
