# Data Model Architecture

## Core entities

### FileRecord
- stable identity;
- path/source;
- name;
- extension/type;
- size;
- timestamps;
- media/document metadata;
- hash/signature;
- index state.

### SearchDocument
- file reference;
- searchable text;
- normalized metadata;
- tags/categories;
- OCR/document extraction state;
- semantic representation where supported.

### Collection
- ID;
- name;
- rule definition;
- generated item references;
- last evaluation timestamp.

### Notification
- ID;
- type;
- title;
- body;
- timestamp;
- read state;
- action/deep-link;
- source;
- dismissal state.

### Operation
- ID;
- type;
- source/target;
- progress;
- state;
- error;
- cancellation capability.

### VaultItem
- protected file identity;
- encrypted metadata;
- vault state.

Exact schemas are implementation details and must be finalized with the selected database and migration strategy.
