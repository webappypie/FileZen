# 08 — Credentials & Configuration

## Security rule

This file is an inventory and sourcing guide only. **Never commit real production secrets, API keys, private keys, signing keys, passwords, tokens, or certificates to Git.**

## FileZen-owned configuration

| Item | Source | Storage rule | Used by |
|---|---|---|---|
| Android application ID | Approved project config | Non-secret | Build |
| Firebase project configuration | WAPCentral integration guide / approved environment | Follow project secret/config policy | Firebase services |
| Crash monitoring config | Approved environment | Non-secret config where applicable | Monitoring |
| Ad provider identifiers | WAPCentral integration guide | Treat provider secrets separately | Ads |
| WAPCentral app ID | WAPCentral integration guide | Non-secret identifier | Integration |
| WAPCentral x-app-key | WAPCentral integration guide | Secret; never hardcode | Integration |
| Signing credentials | Secure release environment | Secret | Release |
| Cloud provider OAuth configuration | Provider-specific | Secrets outside repository | Cloud source integrations |

## WAPCentral source of truth

The separate `WAPCentral_App_Integration_Guide` supplied to the AI team is authoritative for:
- app IDs;
- x-app-key;
- Firebase configuration;
- custom SDK integration;
- notification integration;
- ad provider integration;
- custom promotion integration.

Do not copy those values into this documentation repository.

## Environment model

At minimum distinguish:
- development;
- internal/test;
- production.

Each environment must have independent configuration where practical.

## Secret handling

Use platform/build-system secret facilities or secure CI/CD secret storage. Never log secrets. Never include secrets in screenshots, test fixtures, crash payloads, or AI prompts.

## Secret Rotation Notice (Remediation Finding 15)

- **Remediation Action Taken:** A hardcoded production WAPCentral App Key pattern previously referenced in `test/unit/core_test.dart` has been expunged and replaced with a non-production synthetic token. The promo signing secret in `WapCentralManager` has been transitioned to environment injection (`WAP_PROMO_SECRET`).
- **Required Operator Action:** The exposed production WAPCentral X-App-Key (`wap_key_b3314615802b82d33b53540deaf007681d118d27`) must be rotated/regenerated within the WAPCentral administration portal before public Play Store distribution.
- **Production Build Injection:** Supply secrets strictly at build time via:
  `--dart-define=WAP_APP_KEY=<ROTATED_KEY>` and `--dart-define=WAP_PROMO_SECRET=<SECURE_PROMO_SECRET>`.
