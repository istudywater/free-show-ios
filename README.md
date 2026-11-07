# FreeShow iPad Remote

A native SwiftUI operator console for FreeShow. The desktop remains responsible for rendering presentations and managing display outputs.

## Current status

Milestone 1 foundation is implemented: an iPad application shell, app-level models, service contracts, and source-backed integration research. The shell starts disconnected, with unknown output state. It does not connect to FreeShow or send commands yet.

The iPadOS build and simulator launch are **pending verification on the Mac Mini**. This development Mac has Command Line Tools, not full Xcode. Host-SDK source checks are not an iPadOS build.

## Open and run on the Mac Mini

Requirements: Xcode 16 or newer with Swift 6 support, an installed iOS SDK and iPad simulator runtime, and an iPad running iPadOS 17 or newer for physical-device testing. No package downloads, CocoaPods, XcodeGen, or third-party libraries are needed.

1. Transfer this entire repository folder to the Mac Mini, or commit/push it and clone there. Merely cloning the GitHub remote will not include uncommitted local work.
2. Open `FreeShowRemote.xcodeproj` in Xcode.
3. Select the **FreeShowRemote** scheme and an installed **iPad simulator**.
4. Choose **Product → Build**, then **Product → Run**.
5. Confirm the welcome screen appears with **Not connected**, rotate to landscape, and check light/dark appearance and larger text. There should be no network permission prompt or live presentation controls.

For a physical iPad, select your development team in Signing & Capabilities and change the placeholder bundle identifier if needed. Simulator builds do not require a team. Release artwork and App Store configuration are deferred.

From the repository root, optional terminal checks:

```sh
./scripts/check-foundation.sh
./scripts/build-ipad.sh
```

If the active developer directory still points to Command Line Tools:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-ipad.sh
```

The build script uses an unsigned simulator destination and writes to ignored `build/DerivedData`. For an installed simulator, use `./scripts/build-ipad.sh 'platform=iOS Simulator,id=<UDID>'`. List devices with `xcrun simctl list devices available`. Launch and visually verify through Xcode; the build script alone does not launch the app. See [Mac Mini handoff](docs/mac-mini-handoff.md).

## Project layout

- `FreeShowRemote/App`: app entry point and main-actor UI state.
- `FreeShowRemote/Core`: presentation, connection, output, and scripture domain models.
- `FreeShowRemote/Services`: connection, presentation, output, and scripture interfaces.
- `FreeShowRemote/Features/Foundation`: minimal SwiftUI welcome screen.
- `FreeShowRemote.xcodeproj`: checked-in Xcode project and shared scheme.
- `scripts`: source/project validation and simulator build helpers.
- `docs`: architecture, verified API contract, roadmap, development log, and handoff.

## Documentation and scope

Start with [architecture](docs/architecture.md), [FreeShow API research](docs/freeshow-api.md), and [roadmap](docs/roadmap.md). [Development log](docs/development-log.md) records completed work and outstanding validation.

Obsidian remains the product-planning base. This repository is the source of truth for implementation, build instructions, and verified integration details. The detailed seven-milestone build prompt takes precedence over the original five-milestone summary. Scripture search is now planned as a separately reviewed increment immediately after the connection prototype, subject to checking the installed FreeShow version.

## Upstream references and licensing

Research references: [FreeShow Desktop](https://github.com/ChurchApps/FreeShow), [FreeShow Remote](https://github.com/ChurchApps/FreeShowRemote), and [official API reference](https://freeshow.app/api). Reviewed revisions and file fingerprints are recorded in [API research](docs/freeshow-api.md) and [source manifest](docs/research-sources.json).

Desktop declares GPL-3.0; the existing mobile remote declares MIT. This foundation contains original Swift code and no copied upstream implementation, assets, or bundled dependencies. A license for this new repository has not yet been selected; choose one before publishing it as an open-source release.
