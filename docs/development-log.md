# Development log

## November 7, 2026 — Milestones 3–7 implementation and simulator handoff

The user explicitly authorized completing all remaining milestones without intermediate approval pauses, followed by Xcode simulator review. This supersedes earlier incremental stop/review instructions for this build.

### Implemented

- Native Bonjour discovery of RemoteShow advertisements, manual fallback, last-successful host/port preferences, explicit optional Keychain password storage/forgetting, capped reconnect backoff, full reauthentication/synchronization, and background/foreground recovery.
- One shared operator/scripture session. Typed per-channel pending requests allow independent reads while live commands proceed. Generations reject old callbacks/results and stale cleanup. Wrong passwords and unsupported replies do not silently enable controls.
- RemotePresentationService implements connection/presentation/output contracts. Projects preserve order and duplicate occurrences; layouts expand parents/children/repeated occurrences. Project-specific layouts and disabled slides are honored. Missing references cannot silently change output indices.
- Added confirmed start for supported existing media/PDF/audio/overlay/player items. Fresh project/library validation requires the intended active project and a unique explicit name; ambiguous/unnamed entries are rejected. PDF output/page state remains navigable with native Next/Previous.
- Local project/show/slide preview is separate from output. Explicit desktop-project selection and confirmed direct Present use verified payloads. Direct Present revalidates the layout before sending; arbitrary simultaneous edits after validation remain a server limitation.
- Desktop pushes plus periodic reads synchronize projects/library/output/show content. A newer output push wins over an older query. Unknown/stale state pauses controls; a watchdog catches stale snapshots before a slow request times out.
- Lazy, bounded thumbnails with text fallback, independent live command channels, explicit scope for first-active-output monitoring vs broad mutations, and labeling for temporary scripture/unsupported project content.
- Responsive iPad UI: landscape service/slides/live panels, compact/accessible pane switcher, persistent command dock, current/next/selected previews, visible output/connection state, confirmations, badges and accessibility labels. Added an offline sample service/passage using the same service/controller paths, clearly labeled demo and never network-connected.
- Native and scripture command uncertainty is preserved after interruption; no command replay occurs. Further mutations require an output check. Added source/model/state/reconnect/concurrency and bounded stress checks.
- Updated repository docs and the user-designated Obsidian planning folder with the integrated build/review handoff and explicit field-test limits.

### Validation

- 52 connection, 56 scripture and 59 operator checks passed: **167 total**. Operator tests include 200 sequential navigation operations, rapid taps, pre-Present revalidation, independent thumbnail/control requests, explicit project activation, foreground refresh, native/scripture uncertain sends without replay, preference/vault behavior, stale watchdog, stream termination and old-read/new-push ordering, absent-output vs cleared-state semantics, visible shared-session schema errors without reconnect loops, confirmed media start, duplicate-name/wrong-project rejection and PDF navigation.
- Host structural/Swift 6 checks passed for 20 application Swift sources. The Xcode build covers UIKit/SwiftUI and the pinned package adapter. Shell syntax and git diff whitespace checks passed.
- Unsigned Debug simulator build passed in Xcode 27.1 for arm64 and x86_64, with iPadOS 17 deployment target. Bonjour declarations are present in the built Info.plist; dependency notices are bundled.
- Installed/launched on iPad Pro 11-inch (M5), iOS 27.0, using --demo. The portrait screenshot confirms the sample service, live-vs-preview badges, compact pane selector, shared tabs and persistent command dock. The final header keeps output status visible across compact panes.
- One development demo idle snapshot after 3m40s showed 123,968 KiB RSS (about 121 MiB) and 0.0% CPU. This is a spot observation, not a peak-memory benchmark or long-duration service soak.
- No real FreeShow computer or physical display outputs were controlled. Native simulator UI automation was unavailable through the enabled computer-use surface; user interaction/layout/accessibility review remains in the checklist.

### Files and acceptance

Added BonjourDiscovery, ConnectionPreferences/KeychainVault, DemoTransport/SwitchableRemoteTransport, RemotePresentationService, OperatorStore/OperatorView/OperatorConnectionView, OperatorTests/test-operator.sh and operator-guide.md. Updated the session request model, presentation models, shared scripture state/view, app root, Bonjour plist, project membership, validation helpers and documentation.

Implementation through Milestones 3–7 is ready for the requested simulator review. Actual desktop-release compatibility, network/discovery/Keychain permissions on iPad, multiple-output/media rendering, simultaneous operators, real Wi-Fi/restart tests, and extended rehearsal remain unverified acceptance items. Ambiguous, unnamed and unsupported project item types remain desktop-operated; scripture collections/cross-chapter selections and release artwork/distribution/license decisions are outside the MVP. No commit or push was performed.


## November 7, 2026 — Early scripture increment

### Implemented

- Continued after approval to progress beyond Milestone 2. Added a Scripture tab with its own RemoteShow host/port/password connection, translation selection, reference/text search, passage preview/attribution, separately confirmed Present, and scripture navigation.
- Added the typed RemoteSession and an injectable Socket.IO adapter. Pinned Socket.IO-Client-Swift 16.1.1 and Starscream 4.0.8 with Package.resolved; bundled their license notices. No custom Engine.IO/Socket.IO framing is in application code.
- Readiness waits for ACCESS and SCRIPTURE metadata. Requests are serialized and checked against echoed translation/query or book/chapter keys; timeout, cancellation, disconnect, and library metadata changes invalidate the session and cached text. Reconnect is explicit and presentation commands are not replayed.
- Local Bibles are fetched and searched in memory off the main actor. API translations lazily retrieve books, chapters, and actual verses; API text search uses SEARCH_SCRIPTURE. Both sources parse references against retrieved book metadata and reject incomplete ranges.
- Search/preview only use read channels. Present requires a prepared passage and sends its selected translation and canonical numeric reference. Command replies are not reported as proof of live output changes. Preview and live navigation remain distinct.
- Fixed generation handling so cleanup from an old connection cannot disconnect a replacement. Removed duplicate background disconnect handling, and guarded stale REST disconnect tasks before they can touch the client.
- Updated planning/review documentation in the user's iCloud Obsidian project folder as requested: both original plans, a current-status banner/corrected repository paths on the historical Milestone 1 handoff, and new Scripture Search Review and Testing.md. Repository docs retain implementation/build/API details.

### Validation

- `scripts/test-scripture.sh`: passed 56 checks, including auth/initialization order, range validation, source-specific retrieval/search, no presentation during preview/search, API keys/indices, attribution, explicit presentation/navigation, timeout/no replay, cancellation, mismatched replies, stale callbacks, reconnect race, and UI state. Fixtures use original sample sentences.
- `scripts/test-connection.sh`: passed 52 checks; existing REST behavior remains covered.
- `scripts/check-foundation.sh`: project membership/shared scheme and Swift 6 core/service/state checks passed for 12 app Swift sources. The package-specific adapter and views are compiled by Xcode.
- Xcode 27.1 simulator builds passed for arm64 and x86_64; a targeted iPad Pro 11-inch (M5) build also passed. The first attempt failed due to disk exhaustion; only generated project caches were cleared. The build helper now uses shared package checkouts and skips indexing.
- Final app installed and launched on the iPad Pro 11-inch (M5), iOS 27.0 simulator. A portrait screenshot confirms the Live Controls / Scripture tabs and disconnected shell; the full scripture UI flow remains a live/manual acceptance item. Both dependency license files are present in the built app.
- `git diff --check` passed. No live FreeShow instance was contacted.

### Files and acceptance

Added RemoteSession.swift, SocketIOTransport.swift, RemoteScriptureService.swift, ScriptureState.swift, ScriptureView.swift, ScriptureTests.swift, test-scripture.sh, the package lockfile, dependency license resources, and scripture-increment.md. Updated scripture models, the app root/lifecycle, project/package/resource settings, build/check helpers, README, roadmap, API notes, architecture, handoff, and this log.

Collections, cross-chapter references, arbitrary nonnumeric identifiers, discovery, persistence, automatic reconnection, playlist/slide UI, and desktop push synchronization remain outside this increment. Real desktop-version/authentication/content/output compatibility, physical-iPad network permissions, and extended UI/accessibility acceptance remain in the [scripture checklist](scripture-increment.md). The next canonical milestone is connection management/discovery; stop for scripture-increment review before starting it. No commit or push was performed.


## November 6, 2026 — Milestone 2 connection prototype

### Implemented

- Rechecked the pinned FreeShow REST listener, action registry, and clearance helper using upstream source. Added an injectable native URLSession REST transport, optional Bearer API-password handling, read-only connection validation, bounded timeouts, and explicit HTTP/query errors.
- Replaced the welcome shell with manual host/port/password entry and Previous, Next, Clear all, and Restore controls. Clear all requires confirmation. Controls remain disabled until a valid `get_cleared` response arrives and while requests are in progress.
- Added timestamped output-status snapshots, manual refresh, post-command reads, and explicit wording that command acceptance does not confirm an output change. Errors invalidate output state. No automatic replay or optimistic live-slide state.
- Added generation-scoped stale-reply rejection, task cancellation on disconnect/background, in-memory credentials, redirect rejection, and action/status-only OSLog messages. Added local-network purpose text and local HTTP ATS configuration without a global arbitrary-load exception.
- Updated architecture, API notes, README, roadmap, handoff, and the new `docs/connection-prototype.md` acceptance checklist. Scripture, discovery, reconnect, playlist, and slide UI remain later increments.

### Validation

- `scripts/check-foundation.sh`: passed project/scheme/source checks and Swift 6 core/service/state host typechecking. The helper now explicitly leaves SwiftUI validation to the iPad build.
- `scripts/test-connection.sh`: passed 52 mock-based checks covering endpoint validation, IPv6 formatting, POST/auth payloads, absent/wrong/expired password behavior, malformed/empty query responses, command mapping, one-based slide conversion, timeout/no-retry behavior, overlapping operations, stale replies, UI state, and output snapshot semantics.
- `scripts/build-ipad.sh`: unsigned generic simulator Debug build passed with Xcode 27.1 (27A9275), simulator SDK 27.1, deployment target 17.0, arm64 and x86_64. Xcode's SwiftUI compiler plugin required running outside the restrictive sandbox.
- Installed and launched on iPad Pro 11-inch (M5), iOS 27.0; inspected a portrait screenshot of the connection form. Applied disabled state directly to controls and explicit muted styling for disabled custom button labels. Extended visual/device checks remain in the checklist.
- Inspected the built Info.plist: iPad-only family, minimum OS 17.0, local-network usage string, and `NSAllowsLocalNetworking` are present. `git diff --check` passed.

### Files changed

Added `Core/Networking/RESTClient.swift`, `Features/Connection/ConnectionView.swift`, `Info.plist`, `Tests/ConnectionTests.swift`, `scripts/test-connection.sh`, and `docs/connection-prototype.md`. Updated AppState, the app entry point, Xcode source membership/plist settings, the foundation check helper, and project documentation. Removed the superseded FoundationView.

### Remaining acceptance

Physical-iPad local-network permission behavior and real FreeShow authentication/command/output effects are not tested. No supported desktop release is declared. Use the documented non-live acceptance checklist, record the target desktop version, then review Milestone 2 before the early scripture increment. No commit or push was performed.


## November 6, 2026 — Milestone 1 foundation

### Implemented

- Reviewed official API documentation, desktop server/action/state code, and the existing mobile app's discovery, WebView, and API usage. Recorded upstream revisions and file blob hashes.
- Created a self-contained Xcode project with a shared scheme, iPad-only target, iPadOS 17 deployment target, and Swift 6 settings.
- Added the minimal SwiftUI shell and main-actor state owner. App launch state is disconnected with output unknown; preview selection is independent of live state.
- Added app-level project, presentation, slide, output, connection, and scripture models and service contracts. No networking or live control implementation.
- Added architecture/API research, roadmap, build instructions, source/project checks, and Mac Mini handoff.
- Reconciled the five-milestone overview with the seven-milestone build prompt. Following discussion, planned scripture search as an early increment after the connection prototype instead of waiting until after V1.

### Validation performed

| Check | Result |
| --- | --- |
| Swift 6 typecheck of all six Swift files with the installed macOS host SDK | Passed; no compiler diagnostics |
| `plutil -lint` on Xcode project | Passed |
| Source membership, referenced file existence, iPad-only settings, shared-scheme target references | Passed via `scripts/check-project.py` |
| Shell syntax checks for validation/build helpers | Passed |
| iPadOS simulator build | Not run successfully: full Xcode is unavailable on this Mac |
| iPad simulator launch / visual QA | Pending on Mac Mini |
| Live FreeShow integration | Not performed; deferred to connection prototype |

Toolchain observed: Apple Swift 6.2.4; active developer directory `/Library/Developer/CommandLineTools`. `xcodebuild -version` reports that full Xcode is required. The installed FreeShow bundle is 1.5.2; researched source is 1.6.8-beta.3. Neither a successful iOS build nor compatibility with the installed desktop is claimed.

No behavioral unit tests were added for this static shell and data-only contracts. Add meaningful transport/authentication/index-conversion/reconnection tests as those behaviors are implemented. The shared scheme currently has no test target.

### Files created

- `.gitignore`, `.gitattributes`, `README.md`
- `FreeShowRemote.xcodeproj/project.pbxproj`
- `FreeShowRemote.xcodeproj/xcshareddata/xcschemes/FreeShowRemote.xcscheme`
- `FreeShowRemote/App/FreeShowRemoteApp.swift`
- `FreeShowRemote/App/AppState.swift`
- `FreeShowRemote/Core/PresentationModels.swift`
- `FreeShowRemote/Core/ScriptureModels.swift`
- `FreeShowRemote/Services/ServiceInterfaces.swift`
- `FreeShowRemote/Features/Foundation/FoundationView.swift`
- `scripts/check-foundation.sh`, `scripts/check-project.py`, `scripts/build-ipad.sh`
- `docs/architecture.md`, `docs/freeshow-api.md`, `docs/research-sources.json`
- `docs/roadmap.md`, `docs/mac-mini-handoff.md`, `docs/development-log.md`

Obsidian received a milestone status/handoff note and brief dated clarifications in both original planning documents. Those notes point to the repository for implementation details rather than duplicating the API contract.

### Outstanding acceptance and next step

Build and launch on an iPad simulator on the Mac Mini, then record Xcode/runtime versions and visual checks. Confirm the target FreeShow release before implementing networking. Decide the repository license before open-source distribution.

Milestone 1 implementation is ready for review, with build/launch acceptance outstanding. Milestone 2 has not started. All repository changes remain local; no commit or push was performed.
# RemoteShow device connection follow-up — November 7, 2026

The user confirmed that RemoteShow loads in iPad Safari, while the native app immediately reports a generic disconnect. This establishes browser reachability but does not identify the native transport failure.

- Removed forced WebSocket-only transport; Socket.IO now starts with its default HTTP polling and negotiates an upgrade.
- Preserve transport error/disconnect details in the app's connection error instead of replacing them with host/port advice. These failures remain eligible for automatic reconnection; pending requests close and commands are never replayed.
- Added regression checks for preserving the failure reason and disabling session readiness after a transport failure. Scripture and operator suites each pass 59 checks. The unsigned simulator build passes. Physical-device reconnection still requires a rebuilt app and a user retest; no live fix is claimed yet.
