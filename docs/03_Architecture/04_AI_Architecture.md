# AI Architecture

## Principle

On-device AI first. Cloud AI only for explicit, justified fallback scenarios.

## AI pipeline

```text
File
 → eligibility check
 → local extraction
 → local OCR/vision/parser
 → structured signals
 → classifier/entity extraction
 → index
 → retrieval
 → optional local reasoning
```

## AI capabilities

- OCR.
- Image labels/classification.
- Document category.
- Smart collection suggestions.
- Auto rename.
- Related-file intelligence.
- Semantic/local search.
- Query interpretation for Ask Your Files.
- Smart actions.

## Privacy boundary

A local AI task must never upload a file automatically.

Cloud fallback, if introduced, requires:
- explicit user action or approved user-visible setting;
- clear explanation;
- narrow data scope;
- failure handling;
- no background bulk upload.

## Deterministic fallback

If the AI model fails, return deterministic search/filter results where possible. AI must improve the experience, not become a single point of failure.
