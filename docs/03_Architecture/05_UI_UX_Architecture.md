# UI/UX Architecture

## Primary navigation

Bottom navigation:
- Home
- Files
- AI
- Clean
- Vault

Secondary destinations:
- Transfer
- Network
- Cloud
- Settings
- Smart Collections
- Timeline
- Favorites
- Recent

## Home composition

Universal search, Ask Your Files, recent/continue, categories, storage usage, smart collections, cleanup opportunities, AI suggestions, recently added files, favorites, and controlled ad placement.

## Core interaction principles

- One obvious primary action per screen.
- File operations accessible through contextual actions.
- Multi-select must clearly expose selection count and batch actions.
- Destructive actions visually separated and confirmed.
- AI suggestions are explainable and dismissible.
- Empty states teach the user what to do next.
- Loading states show progress for long operations.
- Error states explain recovery.

## Visual system

Premium, clean, information-dense without feeling crowded. Support dark/light themes, dynamic text sizing, accessible contrast, touch-friendly controls, and consistent iconography.

## View states

Every major screen defines:
- loading;
- empty;
- populated;
- refreshing;
- error;
- permission-required;
- offline/limited-service;
- selection mode where applicable.
