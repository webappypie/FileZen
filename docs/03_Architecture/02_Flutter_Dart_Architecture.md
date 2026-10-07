# Flutter and Dart Architecture

## Recommended structure

```text
lib/
├── app/
│   ├── bootstrap/
│   ├── navigation/
│   ├── theme/
│   └── config/
├── core/
│   ├── error/
│   ├── logging/
│   ├── result/
│   ├── utils/
│   └── platform/
├── features/
│   ├── home/
│   ├── files/
│   ├── search/
│   ├── ai/
│   ├── clean/
│   ├── vault/
│   ├── media/
│   ├── documents/
│   ├── notifications/
│   ├── transfer/
│   ├── cloud/
│   └── settings/
├── data/
├── domain/
└── services/
```

Approved in Phase 00: State management and dependency injection use Riverpod (`flutter_riverpod`) exclusively. Bloc/Cubit and separate `get_it` containers are excluded. Provider hierarchy and overrides are used consistently across application and feature modules.

## Native Android

Use native Android integrations where Flutter cannot safely provide the required capability, including storage access edge cases, Media3 playback, foreground/background behavior, biometric/Keystore operations, filesystem APIs, and platform-specific viewers.

Platform channels must be thin, typed, tested, and isolated from business logic.
