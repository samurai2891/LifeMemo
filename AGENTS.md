# Repository Guidelines

## Project Structure & Module Organization
LifeMemo is an iOS app organized with Clean Architecture + MVVM:

- `App/`: app entry (`LifeMemoApp`) and dependency wiring (`AppContainer`).
- `Domain/`: pure models and service protocols (Foundation-focused).
- `Infrastructure/`: concrete implementations (audio, speech, persistence, security, export, search).
- `Presentation/`: SwiftUI views and view models by feature (for example `Recording/`, `Home/`, `Settings/`).
- `LifeMemoTests/`: XCTest unit/integration tests.
- `Resources/`: `Info.plist`, entitlements, localization, and assets.

`project.yml` is the source of truth for project settings; regenerate `LifeMemo.xcodeproj` after changes.

## Build, Test, and Development Commands
- `xcodegen generate`: regenerate the Xcode project from `project.yml`.
- `xcodebuild -project LifeMemo.xcodeproj -scheme LifeMemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`: simulator build.
- `xcodebuild -project LifeMemo.xcodeproj -scheme LifeMemo -sdk iphonesimulator -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17' test`: run all tests.
- `xcodebuild ... test -only-testing:LifeMemoTests/BackupCryptoTests`: run one test class (replace target as needed).
- `scripts/eval_stt.sh`: run STT-focused regression tests (WER/CER/finalization-related suites).

## Coding Style & Naming Conventions
- Swift 5.9, iOS 17+ target.
- Use 4-space indentation and keep one primary type per file.
- Naming: `UpperCamelCase` for types, `lowerCamelCase` for methods/properties.
- Follow existing suffix patterns: `View`, `ViewModel`, `Service`, `Manager`, `...Protocol`.
- No enforced SwiftLint/SwiftFormat config in-repo; keep code Xcode-formatted and reviewable.

## Testing Guidelines
- Framework: XCTest under `LifeMemoTests/`.
- Test file naming: `FeatureNameTests.swift`.
- Test methods: `test<Condition>_<ExpectedResult>()` (or equivalent readable `test...` form).
- Add regression tests for bug fixes and feature tests for new domain/infrastructure logic.
- No fixed coverage gate; include at least one success path and one edge/failure path for new behavior.

## Commit & Pull Request Guidelines
- Prefer Conventional Commit prefixes used in history: `feat:`, `fix:`, `chore:`.
- Keep commits focused and imperative (example: `fix: resolve playback seek desync`).
- PRs should include:
  - concise change summary and rationale,
  - test evidence (commands run),
  - screenshots/video for SwiftUI-visible changes,
  - linked issue/ticket when available.

## Security & Configuration Notes
- Do not add secrets or API keys to source.
- Keep permission text updates in `Resources/Info.plist` aligned with feature changes.
- For storage/backup features, preserve privacy-first defaults and validate file protection behavior in tests.
