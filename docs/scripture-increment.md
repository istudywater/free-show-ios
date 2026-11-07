# Early scripture increment — November 7, 2026

> November 7 integration update: this note records an earlier increment. The normal app now shares one RemoteShow connection for presentation and scripture, with discovery/reconnection and the integrated operator console. The user authorized all remaining milestones without intermediate stops. Use [operator guide](operator-guide.md) for current setup and simulator review.


## Status and setup

Implemented after approval to move past Milestone 2. The Scripture tab uses FreeShow's **RemoteShow** service, normally port **5510**, and its separate password. Live Controls continues using the General REST API, normally port **5506**. Enter the same FreeShow host in both tabs; either service can be used independently. Enable the relevant services in the desktop settings. No connection information is persisted.

The research baseline remains FreeShow revision `ff784eb388c7baef60d67e6d4e7c504f4322bca3` (`1.6.8-beta.3`). A supported desktop version is not yet declared. The original source-machine report of `1.5.2` is not a compatibility claim.

## Operator behavior

1. Connect Scripture using the RemoteShow host, port, and password.
2. Choose an individual translation supplied by that desktop. Collections are excluded because the upstream retrieval handler cannot load them as a single Bible.
3. Choose Reference or Text. Reference accepts full book names, unambiguous prefixes/available abbreviations, a single chapter, a verse, or same-chapter ranges/lists such as `John 3:16–18`. Cross-chapter ranges are rejected; an invalid/missing verse rejects the whole preview. Up to 200 verses can be previewed.
4. Text search requires three characters and shows up to 50 results. Tap a result to fetch/preview that verse. Searching and previewing never invoke presentation commands.
5. Review the actual passage text, translation, and supplied attribution. Present passage requires a separate confirmation. Previous/Next scripture controls become available only after an explicit Present in the current session.

Changing the query, mode, or translation removes the preview. A command reply establishes only that a request was handled, not that the live display changed. The preview is not a live output monitor; navigation affects the desktop's current scripture. Other operators and output locks may change the result.

## Implementation decisions

- `SocketIOTransport` uses Socket.IO-Client-Swift **16.1.1**, with transitive Starscream **4.0.8**, pinned in the checked-in `Package.resolved`. The library handles Engine.IO/Socket.IO framing and heartbeat over WebSocket. Reconnection and protocol logging are disabled. No custom Socket.IO framing is implemented in the app.
- Authentication sends `REMOTE` / `PASSWORD` with null data, followed by `ACCESS` with a password **string** when needed. Readiness requires both ACCESS and SCRIPTURE metadata; either arrival order is accepted.
- `RemoteSession` serializes requests and checks echoed translation/query or book/chapter keys. Timeout/cancellation/loss discards the socket and pending operations; stale callbacks are generation-scoped. Presentation commands are never replayed automatically. Desktop translation-metadata changes also invalidate cached previews and require reconnecting.
- `RemoteScriptureService` reads `GET_SCRIPTURE`. Local Bible data is cached only in memory and searched off the main actor. API translations load book metadata, chapters, then actual chapter verses. API text search uses `SEARCH_SCRIPTURE` with `{id, searchTerm, searchType:"text"}`. Reference parsing uses the retrieved book metadata for both sources; no invented REST endpoints or independent Bible database are used.
- Book/chapter/verse numbers remain distinct from array positions. API request keys and zero-based book/chapter indices are taken from the fetched metadata. `API:start_scripture` receives `{id, reference:"book.chapter.verse,verse,..."}` only for a prepared preview; navigation uses `API:scripture_previous` / `API:scripture_next`.
- Remote passwords are memory-only and are not reused from REST. Backgrounding disconnects both services. The two tabs prevent overlapping UI operations. No scripture text, search terms, password, or host is logged by the adapter.
- Dependency notices are bundled as `SocketIO-LICENSE.txt` (MIT, including its third-party notice) and `Starscream-LICENSE.txt` (Apache 2.0) in the app resources.

## Automated validation

```sh
./scripts/check-foundation.sh
./scripts/test-connection.sh
./scripts/test-scripture.sh
./scripts/build-ipad.sh 'platform=iOS Simulator,id=<installed-iPad-UDID>'
```

The connection suite passes 52 checks; the scripture suite passes 56 checks. Synthetic fixtures contain original sample sentences, not captured desktop traffic or a bundled translation. They verify authentication/initialization order, read-only search/preview, API lazy retrieval and keys, complete ranges, invalid references, attribution, cache invalidation, explicit presentation, navigation, timeouts/no replay, wrong-query replies, cancellation, stale callbacks, and UI state.

The simulator build passes with Xcode 27.1, iOS simulator SDK 27.1, for arm64 and x86_64 simulator architectures. A targeted iPad Pro 11-inch (M5) build also passed. The first build attempt ran out of disk space; generated project caches were cleared, and the build helper now avoids indexing and uses one shared package checkout. Host checks intentionally exclude the package-specific transport and SwiftUI views; the Xcode build compiles those.

## Remaining device/server acceptance

- The final app launch and portrait tabbed shell are verified on iPad Pro 11-inch (M5), iOS 27.0. Still exercise the Scripture tab flow on simulator and physical iPad; check portrait/landscape, dark/light appearance, large text, and accessibility.
- Test no-password, correct-password, wrong-password, connection limits, disabled RemoteShow, custom ports, and unsupported desktop versions.
- Test an imported local translation and an API-backed translation, including its network/authentication failures and attribution. Confirm book/chapter identifiers on the actual release.
- Verify reference ranges and selected text hits against desktop content. Search and preview must leave output unchanged; canceling Present must send no presentation command.
- Explicitly Present on a non-live output, then navigate scripture. Check desktop output, lock behavior, and interaction with another operator; do not infer success from a null API reply.
- Interrupt Wi-Fi or background during retrieval/presentation. Confirm previews/credentials are invalidated, reconnection is explicit, and uncertain commands are not replayed. Change the desktop's translation metadata and verify reconnect is required.

Automatic discovery, remembered credentials, automatic reconnection, and desktop state synchronization remain Milestone 3 or later. The subsequent Milestones 3–7 implementation is now complete; the current review is the integrated MVP simulator review.
