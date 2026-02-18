# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

This is an iOS (iPhone-only, iOS 17.0+) Swift project using **XcodeGen** to generate the Xcode project from `project.yml`.

```bash
# Regenerate Xcode project after changing project.yml
xcodegen generate

# Build
xcodebuild -project LifeMemo.xcodeproj -scheme LifeMemo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run all tests
xcodebuild -project LifeMemo.xcodeproj -scheme LifeMemo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test class
xcodebuild -project LifeMemo.xcodeproj -scheme LifeMemo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LifeMemoTests/BackupCryptoTests

# Run a single test method
xcodebuild -project LifeMemo.xcodeproj -scheme LifeMemo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:LifeMemoTests/BackupCryptoTests/testEncryptDecryptRoundTrip
```

No linter, formatter, or CI/CD is configured. No third-party dependencies — the app uses only Apple frameworks.

## Architecture

**Clean Architecture + MVVM** with four layers:

```
App/                → Entry point + DI container (AppContainer)
Domain/             → Pure value-type models + service protocols (Foundation only)
Infrastructure/     → Concrete service implementations (AVFoundation, Speech, CoreData, NaturalLanguage, SQLite3, CryptoKit, etc.)
Presentation/       → SwiftUI Views + ObservableObject ViewModels
```

**Dependency rule:** Domain has zero framework imports beyond Foundation. Infrastructure conforms to Domain protocols. Presentation depends on both.

### Dependency Injection

`AppContainer` is the single composition root — a `@MainActor ObservableObject` that manually wires all 25+ services in `init()` with explicit ordering. Injected into views via `@EnvironmentObject`. No DI framework.

### Concurrency Model

- ViewModels and most services are `@MainActor`
- `TranscriptionQueueActor` is the only Swift `actor` (serial background transcription)
- `FTS5Manager` uses a dedicated `DispatchQueue` for SQLite operations
- `ChunkedAudioRecorder` uses `DispatchSourceTimer` for chunk rotation and metering

### Core Data

The schema is defined **programmatically** in `CoreDataStack.swift` (no `.xcdatamodeld` file). Six entities: `SessionEntity`, `ChunkEntity`, `TranscriptSegmentEntity`, `HighlightEntity`, `TagEntity`, `FolderEntity`.

### Dual Search

- `SimpleSearchService` — Core Data `CONTAINS[cd]` predicate for basic search
- `AdvancedSearchService` — Standalone SQLite FTS5 database at `Library/Application Support/LifeMemo/FTS/search_index.sqlite`, separate from Core Data. Index must be rebuilt via `rebuildSearchIndex()`.

## What the App Does

LifeMemo is a privacy-first, fully on-device voice recorder with automatic speech-to-text. Key capabilities:

- **Chunked recording** — 60-second AAC m4a chunks with configurable quality
- **On-device transcription** — `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`; serial queue actor processes chunks
- **Live transcription** — AVAudioEngine + SFSpeechAudioBufferRecognitionRequest, restarts every 55s (60s recognizer limit)
- **Extractive summarization** — TF-IDF scoring via NaturalLanguage framework
- **Encrypted backup** — AES-256-GCM with PBKDF2 (600k iterations), custom `.lifememobackup` format
- **App Lock** — Face ID / Touch ID via LocalAuthentication
- **Synced playback** — Stitches 60-second chunks; highlights active transcript segment
- **Multi-format export** — Markdown, plain text, PDF, JSON

## Key Implementation Details

- All data stored in `Library/Application Support/LifeMemo/` with `isExcludedFromBackup` and file protection (`.completeUnlessOpen` for DB, `.completeUntilFirstUserAuthentication` for audio)
- `project.yml` version is `0.3.0`; the app is in active phased development (Phase 1, 2A/B/D/E visible in `AppContainer` comments)
- Audio interruption recovery handles phone calls, Siri, headset unplug with 3-attempt backoff
- Memory pressure monitoring via `DispatchSourceMemoryPressure`; recording health check every 30s
