# FreeShow integration contract — Milestone 1

Reviewed November 6, 2026. **Source-verified does not mean live-tested.** No presentation commands were sent during this milestone.

## Evidence baseline

- Desktop: `ChurchApps/FreeShow`, revision `ff784eb388c7baef60d67e6d4e7c504f4322bca3`; package version `1.6.8-beta.3`.
- Mobile reference: `ChurchApps/FreeShowRemote`, revision `1c034473fe91444073c8d99ab6c34d3e591b5e55`.
- [Official API reference](https://freeshow.app/api): consulted for the published action vocabulary. The server implementation below is the authority for transport behavior.
- Local installed desktop: `/Applications/FreeShow.app`, bundle version **1.5.2**. Its protocol compatibility has not been tested. Do not infer that all reviewed features exist in that release.

File blob hashes and source links are in [research-sources.json](research-sources.json). These identify the reviewed content independently of future changes to `main`.

## 1. Distinct integration surfaces

| Surface | Default port | Wire protocol | Intended role |
| --- | --- | --- | --- |
| General API | 5505 | Socket.IO, event `data` | Action requests and query responses |
| REST API | 5506 | HTTP requests at `/` with JSON | Native URLSession command/query prototype |
| RemoteShow | 5510 | Socket.IO, event `REMOTE` | Remote authentication, project/show state, output pushes |
| StageShow | 5511 | Socket.IO, event `STAGE` | Stage display, outside current scope |
| Controller | 5512 | Socket.IO | Separate desktop controller, outside current scope |
| Output stream | 5513 | Socket.IO | Separate output stream, outside current scope |
| OSC | API base port (5505) | UDP | Not selected for the iPad client |

Ports are configurable. REST defaults to the API base port plus one; both API HTTP servers share an Express app, so REST routes are also installed on the base port in the reviewed implementation. Do not infer enabled services from default numbers. The source uses Socket.IO 4.8.x dependencies; `URLSessionWebSocketTask` alone does not implement its protocol.

Sources: [API listener][api-server], [remote servers][servers], [package manifest][package].

## 2. General API request, authentication, and response

The REST route is `/`, not `/api/next_slide`. Recommended future request:

```http
POST / HTTP/1.1
Host: <host>:5506
Content-Type: application/json
Authorization: Bearer <configured-api-password>

{"action":"next_slide"}
```

The Authorization header is omitted when no API password is configured. The server also accepts several token fields, but the native adapter should use the header. The password is trimmed when configured. There is no separate login/token-exchange endpoint in the reviewed listener.

The route accepts all HTTP methods and supports query form `/?action=<action>&data=<JSON>`. Prefer POST JSON to avoid putting credentials in URLs. Authentication failure is HTTP 401 with `{"status":401,"error":"Unauthorized"}`.

For general Socket.IO, emit `data` with a JSON object or JSON string such as `{"action":"get_projects"}`. Responses arrive on `data`. Authentication can come from handshake auth (`password`, for example), Authorization headers, query fields, or the request payload. Socket connection success is not authentication success: the listener checks credentials per request and can emit an unauthorized result.

For `get_*` actions, the listener assigns an internal return ID. A successful response has the original request fields and a `data` value, with the internal return ID removed. Illustrative shape (IDs and content below are examples, not captured fixtures):

```json
{
  "action": "get_project",
  "id": "project-id",
  "data": { "name": "Sunday Service", "shows": [] }
}
```

Non-query actions normally return HTTP **204 with no body**, or no `data` response over general Socket.IO. Unknown actions and some missing results can also yield no content. A 204 proves neither action support nor an actual output change. The internal query wait is bounded at roughly ten seconds. No general API push subscription or command acknowledgement contract was found in this listener; use Remote state messages or deliberate polling.

Sources: [API listener][api-server], [action dispatch][actions].

## 3. Commands and data required for the MVP

All general API arguments are flattened beside `action`, not nested under `data` in the request body.

| Action | Extra request fields | Source-confirmed result/behavior |
| --- | --- | --- |
| `next_slide` | None | Advances outputs through desktop logic |
| `previous_slide` | None | Reverses outputs through desktop logic |
| `clear_all` | None | Clears presentation layers, audio, and timers; respects output lock |
| `restore_output` | None | Restores cached output/audio for active outputs; requires cache and unlocked state |
| `index_select_slide` | `index`; optional `showId`, `layoutId` | Sends the selected layout position live |
| `id_select_project` | `id` | Selects a project; not an app-local preview operation |
| `get_projects` | None | Dictionary keyed by project ID |
| `get_project` | `id` | Project object, including ordered `shows` items |
| `get_shows` | None | Dictionary keyed by show ID |
| `get_show` | `id` | Loads and returns a show with slides, layouts, settings, media |
| `get_show_layout` | `id` | Flattened layout references; use these for presentation order |
| `get_slide` | Optional `showId`, `slideId` | Slide object or null; not a slide list endpoint |
| `get_output` | Optional output `id` | The selected/first-active output's `out` object, or null |
| `get_cleared` | None | `{all, background, slide, overlays, audio, slideTimers}` booleans |
| `get_slide_thumbnail` | Optional `showId`, `layoutId`, `index` | Capture result's base64 string, or empty string |
| `get_thumbnail` | Media `path` | Media data URL, or empty string; not a full-slide render |

**Index convention:** general API dispatch decrements every supplied `index`, so the first slide is `index: 1`. Remote `API:*` requests invoke action handlers directly, so their first slide is `index: 0`. Returned output indexes are zero-based. Keep zero-based indexes in app models and test each adapter's conversion explicitly.

A show's `slides` is a dictionary; layout order and child expansion determine the navigable sequence. Never use dictionary enumeration order for next/previous or direct selection. `get_playlists` refers to audio playlists, not the service project.

The thumbnail function needs an active output, builds a temporary capture description, and returns an empty string when required context is absent. It does not establish a universal HTTP thumbnail URL. Verify MIME/encoding, inactive-show loading, capture latency, and output styling against the actual installation. Fall back to readable slide text; avoid capturing every slide at once.

Sources: [action registry and index conversion][actions], [query return shapes][queries], [slide and scripture helpers][helpers], [thumbnail capture][media], [clear and restore semantics][clear].

## 4. Remote session and password flow

Connect Socket.IO to the Remote port and use event `REMOTE`. Envelope:

```json
{"channel":"PASSWORD","data":null}
```

The browser client includes its socket ID, but the desktop server replaces inbound IDs with the actual socket ID. This is a connection ID, not a request-correlation token.

1. Send `PASSWORD` after transport connection.
2. If a password is configured, receive `PASSWORD` with `{dictionary, password: true}`.
3. Send `ACCESS` with the password string as `data`, not a password object.
4. Wrong password produces `ERROR` with `{key:"wrongPass"}`. Capacity limits produce `{key:"overLimit", max: ...}` followed by disconnect.
5. Successful access produces `ACCESS` with null data, plus initialization state. Without a password, the initial `PASSWORD` request can go straight to access/initialization instead of returning a `password:false` response.

Remote password and general API password must not be conflated. The reviewed Remote handler gates control/API requests when a Remote password is set. These are local HTTP connections; adding Keychain persistence does not encrypt transport.

Example Remote action after access:

```json
{"channel":"API:next_slide","data":{}}
```

Remote `API:*` replies retain the channel and place the handler result in `data`, often null for commands. A null reply is not proof of a live change, and an unknown API handler can also produce null. For ordinary Remote channels the payload shapes differ from general API query wrappers.

Sources: [browser socket client][remote-client], [Remote handlers][remote-handlers], [authentication gate and API bridge][bridge], [server connection lifecycle][servers].

## 5. State synchronization and preview selection

| Remote channel | Shape/use |
| --- | --- |
| `SHOWS` | Show dictionary; emitted during initialization |
| `PROJECTS` | Array of project objects with IDs; differs from general `get_projects` dictionary |
| `PROJECT` | Desktop active-project ID |
| `SHOW` | Request data is a show ID; response is loaded show data plus ID |
| `OUT` | Ordinary output includes `{slide, layout, styleRes, show?}`; `slide:null` means no slide |
| `OUT_DATA` | First active output's `out` object, including current layers |
| `SCRIPTURE` | Translation metadata dictionary |

Output store changes push `OUT` and `OUT_DATA`. Project changes push `PROJECTS`; active-project changes push `PROJECT`. Show-cache changes may push the subscribed show's content with throttling. Do not assume all library edits are broadcast immediately: some show-list updates are commented out in the reviewed listener.

Remote `SHOW` also tracks the connection's selected show and can open it on the desktop after an idle period. It is not a side-effect-free preview request. `OUT` is overloaded: null requests state, a number selects a zero-based current-show position, an `{id, layout, index}` object presents a show position, and `"clear"` invokes clearing. Avoid these overloaded mutations for local selection; `get_show` is the cleaner read path.

Temporary scripture output (`id:"temp"`) and other presentation types use different shapes. Multiple-output behavior is not uniform: Remote output reads usually select the first active output, while broad commands can affect active outputs collectively. Explicit output scope and unsupported-type presentation need live validation.

On reconnect, authenticate again and request a complete current snapshot. Track connection generation, discard old replies, and mark old state stale. The reviewed messages provide no revision cursor or reliable delivery replay. No hardware validation or latency guarantees are claimed.

Sources: [Remote initialization and selection][remote-handlers], [store subscriptions][listeners], [browser receiver][remote-receiver], [layout flattening][layout].

## 6. Discovery

Desktop advertises Bonjour **`_freeshow._udp`** in `local`, with names such as `freeshow-REMOTE-<instance-id>`. The advertised port is the application service's port; the `_udp` label does not mean commands should use UDP instead of HTTP/Socket.IO.

The existing mobile remote scans `freeshow`/`udp`, groups advertisements, and derives capabilities from names such as API, REMOTE, STAGE, CONTROLLER, and OUTPUT_STREAM. Desktop TXT data includes `ip` and `ips`; the native macOS advertiser joins `ips` with commas. Do not assume TXT is a JavaScript array or that every address is reachable. Resolve Bonjour endpoints and retain manual host/port entry.

A future native browser can use Apple's Network framework. Add `_freeshow._udp` to Bonjour declarations and a local-network usage description when implementing discovery. Verify discovery across Wi-Fi isolation, multiple adapters, and multiple FreeShow hosts. Do not copy the mobile service's `apiEnabled` inference as proof that the general API is enabled.

Sources: [desktop Bonjour publisher][bonjour], [mobile discovery implementation][discovery].

## 7. Scripture: newly confirmed source capabilities

The original plan left search availability unresolved. Current Remote source has:

- `SCRIPTURE`: translation metadata sent at initialization and on change.
- `GET_SCRIPTURE` with `{id}`: local translations return Bible data in `data.bible`; API translations initially return a book list. API book/chapter requests add `bookKey`, `chapterKey`, `bookIndex`, and `chapterIndex` as needed, returning `bibleUpdate` with chapters or verses.
- `SEARCH_SCRIPTURE` with `{id, searchTerm, searchType, bookFilter?}`. For API-backed translations, `searchType:"reference"` parses a reference; text search requires at least three characters and limits results to 50. Responses include `searchResults`, with separate reference/text shapes.
- Local translations return `searchResults:null`, signaling client-side search of previously obtained data. This is not a server-side full-text endpoint for local Bibles.
- `start_scripture` takes `{reference, id?}`; current source also supports `play:false`, but the app should use pure retrieval for preview. `scripture_next` and `scripture_previous` are presentation actions.

These handlers are Remote channels, not invented REST routes. Translation availability, remote API service credentials, licensing of displayed Bible text, offline behavior, and support in older FreeShow releases remain to be checked. Plan an early scripture increment after a working connection; no scripture implementation is part of this foundation.

Sources: [Remote scripture retrieval/search][remote-handlers], [scripture presentation helper][helpers], [browser handling of scripture data][remote-receiver].

## 8. Mobile reference and remaining checks

The existing React Native app displays FreeShow-hosted interfaces in a WebView and has a separate API hook using the `data` event. Its generic `FreeShowService` also contains calls such as `next`, `goto`, and action-specific response events. These do not match the authoritative general API listener inspected here, so they are not adopted as this app's wire contract.

Before declaring a supported server version, validate: password/no-password/wrong-password behavior, enabled/custom ports, query response wrappers and null/204 cases, actual slide indexes, multiple outputs, clear/restore scope, thumbnail capture, desktop-originated changes, reconnect refresh, and scripture availability. Use a non-live test presentation. Milestone 1 provides evidence and interfaces, not an end-to-end compatibility claim.

Sources: [mobile WebView screen][webview], [mobile API hook][mobile-api], [generic mobile service][mobile-service].

[api-server]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/electron/utils/api.ts
[servers]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/electron/servers.ts
[package]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/package.json
[actions]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/frontend/components/actions/api.ts
[queries]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/frontend/components/actions/apiGet.ts
[helpers]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/frontend/components/actions/apiHelper.ts
[media]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/frontend/components/helpers/media.ts
[clear]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/frontend/components/output/clear.ts
[remote-client]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/server/remote/util/socket.ts
[remote-handlers]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/frontend/utils/remoteTalk.ts
[bridge]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/frontend/utils/sendData.ts
[listeners]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/frontend/utils/listeners.ts
[remote-receiver]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/server/remote/util/receiver.ts
[layout]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/server/remote/util/output.ts
[bonjour]: https://github.com/ChurchApps/FreeShow/blob/ff784eb388c7baef60d67e6d4e7c504f4322bca3/src/electron/data/bonjour.ts
[discovery]: https://github.com/ChurchApps/FreeShowRemote/blob/1c034473fe91444073c8d99ab6c34d3e591b5e55/src/services/AutoDiscoveryService.ts
[webview]: https://github.com/ChurchApps/FreeShowRemote/blob/1c034473fe91444073c8d99ab6c34d3e591b5e55/src/screens/WebViewScreen.tsx
[mobile-api]: https://github.com/ChurchApps/FreeShowRemote/blob/1c034473fe91444073c8d99ab6c34d3e591b5e55/src/hooks/useFreeShowApi.ts
[mobile-service]: https://github.com/ChurchApps/FreeShowRemote/blob/1c034473fe91444073c8d99ab6c34d3e591b5e55/src/services/FreeShowService.ts
