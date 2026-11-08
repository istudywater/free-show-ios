# Operator guide and simulator review

November 7, 2026

## Start in Xcode

Open FreeShowController.xcodeproj, choose FreeShowController and an iPad simulator, then Run. Xcode resolves the pinned Socket.IO packages the first time. The app targets iPadOS 17+; simulator signing does not require a team. Physical-device runs need your development team and the local-network permission prompt.

Tap **Try offline demo**, or add `--demo` to the Debug scheme's Run arguments for automatic offline startup. The demo never connects to a computer and uses original sample service text. Its sample passage is `Sample 1:1–3`, explicitly not Bible content. Remove the launch argument before testing a real server.

Rotate to landscape for the three-panel layout: service, slides, and live/preview. Portrait/narrow windows use Service / Slides / Live & preview panes. The command dock remains visible in every pane. Larger accessibility sizes switch to the compact layout.

## Connect a real desktop

Enable **RemoteShow** in FreeShow Desktop. In Connection, find nearby computers or enter hostname/IP and RemoteShow port (normally **5510**). Enter its Remote password if one is configured. The General API/REST port/password from the earlier prototype is separate and is not required by the normal operator interface.

Discovery uses the advertised `_freeshow._udp` service to resolve the RemoteShow hostname/port; control still uses Socket.IO over TCP/WebSocket. It does not send commands over UDP. Discovery begins only when requested. If permission or network isolation prevents browsing, manual entry remains available.

The last successful host/port is remembered. Passwords remain in memory unless Save Remote password in Keychain is enabled. Forget removes the current computer's saved credential. No password is stored in preferences. HTTP/WebSocket traffic is local and unencrypted by the desktop service; Keychain protects storage, not transport.

## Browse and present

PDF decks now have a rendered page grid. Select the PDF or follow a live PDF, then use the same Tap to live / long-press controls as native slides. Current-page state follows desktop Previous/Next. Use Reload PDF pages after editing a file. The app requests 480-pixel-wide JPEG previews, with limits of 500 pages and 24 MB of decoded images. When starting a different PDF, it must still belong to the active desktop project; current-PDF page-count changes reject the old selection and require reload. Native-show validation still compares fresh slide data. PDF content changes with the same page count require an explicit reload.

- Choose a project to browse locally. **Follow desktop** tracks its active project; **Select on desktop** explicitly changes that project on the desktop.
- Choose a native show to load its ordered layout. Repeated project entries and parent/child slides keep their occurrence positions. Existing image/video/PDF/audio/overlay/player items with a unique explicit name can be started from the active desktop project using **Start item**, after confirmation and a fresh project/name check. Choose **Select on desktop** first if browsing another project. Ambiguous, unnamed or unsupported entries remain desktop-operated. Native shows containing media still render through the desktop engine.
- The live show’s slide grid loads on connection. **Tap to live** starts off: tap to preview, or hold a slide for half a second to present it. Turn it on for single-tap live changes. Every activation still validates the layout; disabled slides cannot be presented. **Present selected slide** retains confirmation, and VoiceOver provides a **Go live** action on each slide.
- **Previous / Next** act on desktop output, including PDF pages, not the locally selected preview. Command–[ and Command–] are keyboard equivalents. Media rendering/layer/loop/mute behavior follows the desktop API handler and needs live acceptance; it is not a media editor.
- Bottom left, **Clear output / Go live** clears active outputs immediately, including audio, backgrounds, overlays and timers. Once the slide layer is clear, **Go live** presents the selected slide, starts supported selected media after confirmation, or restores cached desktop output if no slide is selected. **Tap to live** sits immediately to its left; **Previous / Next** are on the right. **More** contains Restore and confirmed Clear all. Desktop output locks still apply.
- **Go to live slide** follows the current output in the navigator. Current/next output and selected preview remain distinct. ON OUTPUT identifies the presentation, not a guaranteed occurrence among duplicate project entries.

Live monitoring reads the first active output. Broad commands can affect active outputs collectively. A successful command reply is not presented as proof that the display changed; the output indicator follows desktop-reported state. Missing/temporary/cleared/unknown output is labeled explicitly.

Visible slide thumbnails load lazily, with readable text as fallback. **Refresh**, **Retry preview**, and **Retry images** reset failed image attempts and retry content. Preview errors distinguish missing show data from unavailable rendered images; successful content retry clears the content error. Render availability depends on desktop output/capture support. Images are cached with a count/size limit; slow renders do not block live commands. The preview text is presentation source text, and desktop styling/dynamic values may differ.

## Scripture

The Scripture tab shares the operator's authenticated session. Choose an individual local or API-backed translation, then reference or text search. Search/result selection only retrieves and previews content. Confirmed Present is the only path from a preview to live scripture. Navigation is available only after Present in the current session.

Reference parsing supports a chapter, verse, or same-chapter range/list, up to 200 preview verses. Missing verses reject the whole selection. Text search needs three characters and returns up to 50 matches. Collections, cross-chapter selection, and nonnumeric verse identifiers are not supported. Local data is session-memory only; API-backed translations still depend on the desktop's API credentials/internet/content availability.

## Interruptions

Output becomes unknown/stale on loss. Controls pause when snapshots age past eight seconds. Automatic reconnect reauthenticates and refreshes projects, content and output, with backoff capped at 30 seconds. Wrong passwords/connection limits require intervention; turn reconnection off or disconnect to stop attempts.

Commands are never replayed after an uncertain send. If an interruption occurs while a native or scripture command is in flight, check actual desktop output and acknowledge that check before continuing. Returning from background reconnects and synchronizes when enabled; a scripture preview/navigation session is reset. Metadata changes invalidate Bible caches.

The protocol has no global revision cursor or atomic edit/present transaction. The app checks layouts immediately before Present, but concurrent desktop edits after that check remain possible. Use the simultaneous-operator test below before live use.

## Build and automated verification

```sh
./scripts/check-foundation.sh
./scripts/test-connection.sh
./scripts/test-scripture.sh
./scripts/test-operator.sh
./scripts/build-ipad.sh
```

Results: 52 connection + 59 scripture + 79 operator checks = **190 checks**. Operator coverage includes a 200-operation sequential navigation stress run, rapid-tap suppression, revalidation before Present, foreground refresh, native/scripture uncertain-send recovery, credential preferences, independent thumbnail/live channels, update stream termination, stale callback protection, and push/query ordering. Tests use synthetic data, isolated preferences and an injected credential vault, not real Keychain entries or live computers.

The app builds with Xcode 27.1 for both simulator architectures. Host checks typecheck domain/services/state and Bonjour/Keychain sources; Xcode compiles the Socket.IO adapter and SwiftUI views. See development-log.md for simulator launch/visual verification details. These results do not replace device/server/long-duration acceptance.

## Simulator review checklist

1. Launch normally and in demo; ensure the demo label is persistent and no network prompt is needed for demo.
2. Browse projects, including the empty demo project and repeated show. Compare preview, ON OUTPUT badge, and current/next output.
3. Try the sample PDF with confirmed Start item and Next/Previous, then return to a native show. Select different slides without presenting; output must remain unchanged. Cancel a Present confirmation; then confirm one and navigate.
4. Try the dock’s immediate Clear output / Go live toggle, then More → Restore and the cancelable Clear all action. Test Tap to live off (tap previews, hold presents) and on (tap presents). Confirm the dock stays reachable while scrolling or switching compact panes.
5. Search/preview Sample 1:1–3 in Scripture and explicitly Present. Try a text search and invalid/cross-chapter reference.
6. Rotate between portrait/landscape, resize the window, toggle appearance, and test large/accessibility text and VoiceOver. Check all touch targets, labels, scrolling and empty states.
7. Background/foreground and verify reconnect/reset behavior. Exit demo, inspect Connection preferences/notices, and confirm normal manual entry remains available.

## Real desktop/device acceptance still required

- Record actual FreeShow/Xcode/iPadOS versions and desktop ports. The source baseline is 1.6.8-beta.3; no supported desktop release is declared yet.
- Test discovery across adapters/hosts, manual fallback, denied/allowed physical-iPad local-network permission, and Wi-Fi client isolation.
- Test password/no-password/wrong-password and connection limits; verify Keychain opt-in, forgetting, device lock behavior, remembered computer, and reconnect preference.
- Compare project order, selected vs active project, duplicates, child/repeated slides, disabled entries, empty/deleted shows, project-specific layouts, and desktop-originated edits.
- Verify slide/media rendering, thumbnail capture on actual outputs, styling/text fallbacks, and multiple-output scope. Check locks and restore with/without cache.
- Test native and scripture commands with desktop/iPad operating simultaneously, rapid presentation changes, and real output feedback. Confirm no unrequested output changes while browsing.
- Verify imported/API-backed Bible content, attribution, unavailable translations, desktop API/internet failures, and metadata changes.
- Interrupt Wi-Fi/restart FreeShow/background during reads and mutations; confirm unknown/stale state, bounded retries, fresh sync and no command replay.
- Run an extended service rehearsal while watching memory/CPU/network behavior in Instruments. Automated bounded stress is not a long-duration field soak.

Editing/uploads, cloud sync, app artwork/release signing, and repository-license selection remain outside this simulator-review build.
