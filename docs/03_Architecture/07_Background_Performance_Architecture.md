# Background and Performance Architecture

## Background work

Use platform-appropriate scheduling for:
- incremental indexing;
- thumbnail generation;
- OCR;
- duplicate analysis;
- cleanup analysis.

Long-running work must be resumable and cancellable.

## Resource policy

- Prefer charging/idle conditions for expensive analysis.
- Reduce work under low battery.
- Bound concurrency.
- Use backpressure.
- Release large buffers promptly.
- Avoid decoding full-resolution media when thumbnails are sufficient.

## Startup

Startup should initialize only what is necessary for the first interactive frame. Heavy indexing/model initialization happens asynchronously.

## ANR prevention

Never perform large scans, hashing, decompression, OCR, or media decoding on the main/UI thread.
