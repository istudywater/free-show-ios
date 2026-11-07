# Architecture

## Current application

Native SwiftUI, iPadOS 17+, Swift 6. The app root owns OperatorStore and BonjourDiscovery. OperatorStore composes one RemoteSession with RemotePresentationService and RemoteScriptureService. ScriptureState adopts that same authenticated session; it no longer needs a second connection form in the normal app.

The normal transport is Socket.IO-Client-Swift 16.1.1 / Starscream 4.0.8. SwitchableRemoteTransport selects it or the explicitly labeled DemoTransport. Offline demo uses the same domain/service/controller paths without allocating a live socket or issuing Bonjour searches. The earlier RESTClient, AppState, and ConnectionView remain development/prototype sources and are not the primary operator UI.

| Component | Responsibility |
| --- | --- |
| OperatorView | Service list, slide grid, current/next/selected previews, persistent command dock, confirmations |
| OperatorConnectionView | Manual/discovered connection, preferences, optional Keychain consent, demo and notices |
| OperatorStore | Connection/retry/lifecycle policy, preview intent, live snapshot, command gating, stale-state watchdog and bounded thumbnail queue |
| RemotePresentationService | Read projects/shows/output, normalize layout order, publish snapshots, send verified API actions |
| ScriptureState / RemoteScriptureService | Search/results/preview, individual local/API translations, prepared-passage presentation and scripture navigation |
| RemoteSession | Remote password flow, initialization readiness, per-channel pending requests, timeouts, push observers, generation-scoped replies |
| SocketIOTransport | Untyped Socket.IO values and library callbacks confined to a main-queue adapter |
| BonjourDiscovery | Native `_freeshow._udp` browsing/resolution with REMOTE advertisement filtering and manual fallback |
| KeychainVault / ConnectionPreferences | Opt-in this-device password storage and password-free last-computer/preferences |

## Readiness and synchronization

An open socket is insufficient. The session waits for ACCESS and SCRIPTURE metadata; presentation readiness additionally requires successful project/library/output/clearance reads. The store only enables commands when the current session is synchronized, output is known, and no other mutation/scripture operation is active.

PROJECTS, PROJECT, SHOWS, and OUT_DATA pushes update authoritative state. A two-second heartbeat queries output/clearance; projects/library refresh every five ticks, selected presentation content every three ticks, and live presentation content is refreshed alongside output. These reads cover source paths that do not consistently broadcast library edits. A revision guard prevents an older output query from overwriting a newer push. Invalid project pushes do not replace valid cached project data.

After eight seconds without a fresh snapshot, a watchdog marks state stale and pauses controls while a request is still bounded by its timeout. Disconnect makes output unknown immediately. Automatic reconnect uses capped exponential backoff, reauthenticates, fetches a complete new snapshot, reloads previews, and never replays a command. Wrong passwords/connection limits and unsupported data require operator attention. Changing desktop scripture metadata invalidates cached Bibles and reconnects to fetch fresh metadata.

## Preview and live intent

Projects/items/slides are browsed locally. Make project active on desktop, Present, Start item, next/previous, Clear all, Restore, and scripture presentation/navigation are explicit operations. Clear all, direct presentation and media start require confirmation. Existing media/PDF/audio/overlay/player items use verified name_start_project_item only when their exact name is unique in the confirmed active project. Fresh project/library reads revalidate the captured item before dispatch; the app rejects ambiguous or changed names. PDF state/page counts stay known so native Next/Previous can navigate pages. Current/next output and selected preview are separate panels and states.

Projects preserve server item order; occurrence IDs include project ID and position. Slide layout order expands parent/child groups and repeated occurrences. Each slide identity includes presentation, layout, and zero-based flattened position. API:* Remote commands use those zero-based positions; the old general REST prototype converts to one-based at its boundary.

Before direct Present, the service re-fetches the selected layout and compares slide identities/content/disabled state with the confirmed preview. Changed/missing slides are rejected and refreshed. The protocol has no atomic revision token, so another operator can still edit after validation; simultaneous live editing remains a field acceptance case.

The monitored output is the first active output. Null output, cleared slide layers, broad all-cleared flags, temporary scripture output, and unknown/malformed data remain distinct. A null command reply indicates request handling, not successful physical output. ON OUTPUT can identify the foreground slide or media resource where the desktop reports it; audio/overlays and duplicate occurrences are not inferred as uniquely active. Duplicate project occurrences are separately selectable, but a presentation-level ON OUTPUT badge does not infer an unavailable occurrence identity.

## Request concurrency and failure

RemoteSession allows independent channels to progress concurrently, so a thumbnail render cannot block Next/Previous. Requests sharing a channel are serialized or rejected while busy. Show reads have a cancellation-aware ownership queue; UI mutations have a separate one-at-a-time gate. Conflicting replies are matched against echoed translation/query or book/chapter fields where available.

Any timeout/cancellation discards the connection and pending requests because there is no general request ID. Generations protect session callbacks, read results, tasks, and reconnect cleanup. A possibly executed native or scripture command is marked uncertain after interruption, is never retried, and requires an output check before further commands. A newer desktop push always wins over an older query response.

Backgrounding cancels work, disconnects, clears scripture preview/live truth, and preserves only in-memory reconnect intent/credentials when enabled. Foregrounding performs fresh synchronization. Turning reconnect off stops pending retry behavior. Explicit disconnect also cancels retries. Passwords are saved only by explicit Keychain preference; UserDefaults stores no password, and demo does not save credentials.

## Images, memory and accessibility

Visible slides queue thumbnails lazily, one render request at a time. Images are limited to 24 cached entries / approximately 16 MB compressed data, with text fallback for empty/unsupported/invalid results. Presentation changes invalidate images and in-flight image generations. A render interrupted by connection loss pauses automatic rendering until explicitly requested again. Thumbnail work does not share the mutation gate.

The landscape operator layout has three panels. Narrow windows and accessibility text sizes use a compact service/slides/live switcher. Next/Previous, Clear/Restore, and Present remain in a fixed dock; labels, badges, and accessible names distinguish selected, live, and disabled slides without relying solely on color. Full device/accessibility acceptance remains a manual checklist.

## Verification and scope

The source baseline is pinned in freeshow-api.md and research-sources.json. Mock tests use original sample sentences and isolated preferences/credential stores. They verify network/state behavior; they do not prove compatibility with a running desktop, physical display outputs, or real Wi-Fi interruptions. See operator-guide.md and development-log.md for exact results and remaining field checks.
