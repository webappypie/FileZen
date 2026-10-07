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
