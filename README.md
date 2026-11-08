# FreeShow iPad Remote

Native SwiftUI operator console for FreeShow. The desktop renders presentations; the iPad browses the service, previews slides, controls output, and searches the desktop Bible library.

## Current status

The foundation, connection prototype, early scripture increment, and implementation work for Milestones 3–7 are complete. The app now includes discovery, remembered connections, optional Keychain credentials, automatic reconnect/synchronization, ordered projects/slides, an adaptive operator interface, and an offline demo.

**Ready for Xcode simulator review.** Xcode 27.1 simulator builds pass for arm64/x86_64. Automated suites pass **182 checks** (52 connection, 59 scripture, 71 operator), including 200 sequential navigation operations. Live FreeShow compatibility, physical-iPad permissions, and real-service/extended soak acceptance still require testing. No supported desktop version or live-service reliability guarantee is claimed yet.

## Open and review in Xcode

1. Open `FreeShowRemote.xcodeproj` and choose the **FreeShowRemote** scheme.
2. Select an installed **iPad simulator**, then **Product → Run**. The minimum app OS is iPadOS 17; use Xcode 16+ with Swift 6 and an installed iOS SDK/runtime.
3. Tap **Try offline demo** in Operator or Connection. The demo supplies a sample service, slides, live state, and sample scripture text without any network connection.
4. Select service items and slides, including the sample PDF item; check that preview differs from the live indicator. Tap to live starts off: taps preview and a half-second hold presents; enabling it makes a single tap present. The bottom dock has Tap to live and Clear output / Go live on the left, Previous/Next on the right, and secondary actions under More. Rotate to landscape to see the service, slide grid, and live/preview panels side by side.
5. Open Scripture and use `Sample 1:1–3` in demo mode. The text is explicitly demonstration content, not a Bible translation.
6. Review dark/light appearance, larger accessibility text, portrait/landscape, and smaller iPad windows. The [simulator and device checklist](docs/operator-guide.md) covers the full review.

For automatic demo startup in a Debug build, add `--demo` under **Product → Scheme → Edit Scheme → Run → Arguments Passed On Launch**. Remove it when testing a real connection. For a physical iPad, select your development team in Signing & Capabilities; simulator builds do not need a team.

Xcode resolves Socket.IO-Client-Swift **16.1.1** and Starscream **4.0.8** on the first build. Revisions are pinned in `FreeShowRemote.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. No CocoaPods or XcodeGen is needed.

## Connect to FreeShow

The integrated app uses **RemoteShow**, normally port **5510**, for presentation and scripture features. Enable RemoteShow in desktop settings, allow iPad local-network access, then choose **Connection → Find FreeShow computers**, or enter the host/IP and port manually. Supply the **RemoteShow password**, if configured.

This is separate from the General API/REST password and default port **5506** used by the earlier connection prototype. Normal operator use does not require enabling both services. Existing REST client/prototype sources and tests are retained for diagnostics/development.

The app remembers the last successful computer, stores passwords in Keychain only when requested, and refreshes all desktop state after reconnecting. It never replays presentation commands. Browsing alone changes no output; selecting a project on the desktop and presenting a slide are explicit actions.

## Build and checks

```sh
./scripts/check-foundation.sh
./scripts/test-connection.sh
./scripts/test-scripture.sh
./scripts/test-operator.sh
./scripts/build-ipad.sh
```

The build helper uses unsigned simulator builds, shared package checkouts, and ignored `build/DerivedData`, with indexing disabled to reduce storage. To build a particular iPad:

```sh
./scripts/build-ipad.sh 'platform=iOS Simulator,id=<UDID>'
```

If needed, use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before these commands. The build helper does not install or launch. CLI tests use injected transports and isolated preferences; they do not contact a live FreeShow computer or touch real Keychain credentials. The Xcode scheme currently has no XCTest target.

## Scope and limitations

- Native shows and scripture are controllable. Supported existing image/video/PDF/audio/overlay/player items can be started by a confirmed action when uniquely named in the active desktop project. Ambiguous, unnamed or unsupported items remain desktop-operated. Embedded media in a native show also renders on the desktop.
- Live indicators monitor the **first active output**. Broad controls may affect multiple active outputs. Output locks, cached restore behavior, and differences between outputs need live acceptance testing.
- Thumbnails load lazily and fall back to readable text. Desktop push updates are combined with polling for content that is not consistently broadcast.
- Local preview and desktop-reported live state remain separate. A command reply is not treated as proof that output changed. A slide is re-fetched/validated before Present, but FreeShow provides no atomic revision/locking contract against another operator editing immediately afterward.
- Scripture supports individual translations, same-chapter references/ranges/lists, up to 200 preview verses, and up to 50 text matches. Collections and cross-chapter selection are not implemented.
- Editing, uploads, cloud sync, and release/distribution artwork remain outside the MVP.

## Documentation

[Operator guide and acceptance checklist](docs/operator-guide.md), [architecture](docs/architecture.md), [API research](docs/freeshow-api.md), [roadmap](docs/roadmap.md), and [development log](docs/development-log.md) describe the current build. The earlier connection/scripture notes preserve incremental history. Product planning and review notes are maintained in the user's Obsidian project folder; the build does not depend on that vault.

## Upstream and licensing

References: [FreeShow Desktop](https://github.com/ChurchApps/FreeShow), [FreeShow Remote](https://github.com/ChurchApps/FreeShowRemote), and [API reference](https://freeshow.app/api). Reviewed FreeShow source is pinned to `ff784eb388c7baef60d67e6d4e7c504f4322bca3` (`1.6.8-beta.3`); source verification is not live compatibility verification.

Original Swift integration code contains no copied FreeShow implementation/assets. Socket.IO-Client-Swift (MIT) and Starscream (Apache 2.0) notices are bundled and accessible under Connection → Open-source notices. FreeShow Desktop declares GPL-3.0, and its reference mobile remote declares MIT. This repository's own license has not been selected; choose one before publishing an open-source release.
