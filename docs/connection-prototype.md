# Milestone 2 — Manual connection prototype

> November 7 integration update: this note records an earlier increment. The normal app now shares one RemoteShow connection for presentation and scripture, with discovery/reconnection and the integrated operator console. The user authorized all remaining milestones without intermediate stops. Use [operator guide](operator-guide.md) for current setup and simulator review.


## What is implemented

Enter a computer's hostname/IP, REST port (default 5506), and optional **General API** password. Enable the General API in FreeShow desktop settings first. RemoteShow's password and port are different services.

Connect sends a read-only `get_cleared` request. The app enables controls only after HTTP success and a correctly shaped response with the matching action and all six boolean fields. Empty/204 query responses, unrelated HTML/JSON, wrong passwords, network failures, and HTTP errors leave controls disabled.

Previous, Next, Clear all, and Restore send the documented POST action at `/`. Clear all requires confirmation because it clears audio, backgrounds, overlays, and timers as well as slides. These commands can affect active outputs collectively and respect desktop output locks. Restore needs FreeShow's cached state. The prototype does not select an output.

After a command is sent, the app reads `get_cleared` again. A command's HTTP success does not establish that the desktop changed output. The UI states this explicitly. Output status is a timestamped snapshot, and does not identify the live slide. Refresh status performs another read. There is no background polling, discovery, Socket.IO session, or automatic reconnection in this milestone.

Only one operation is allowed at a time. Disconnect cancels the UI task and invalidates the session generation; replies from old requests cannot restore readiness. Backgrounding disconnects and clears the password field. Returning requires an explicit connection. Merely becoming inactive (such as while the local-network permission alert appears) does not disconnect.

Passwords stay in memory, and the ephemeral URLSession stores no cache or cookies. HTTP redirects are rejected. OSLog records action names and HTTP status codes, never credentials, hosts, response bodies, or arbitrary server errors. LAN HTTP is not encrypted. Password persistence/Keychain is deferred to Milestone 3.

## Build and automated checks

```sh
./scripts/check-foundation.sh
./scripts/test-connection.sh
./scripts/build-ipad.sh
```

The first script validates project membership/settings and typechecks core, service, and app-state code using the host SDK. The UI requires the iPad build. Connection tests compile a standalone Swift executable with an injected mock HTTP transport; they do not require a live server, simulator runtime, or XCTest target. They check authentication, wire payloads, query validation, index conversion, failures, command serialization, and stale replies. The Xcode scheme still has no XCTest target.

The app includes a local-network purpose string and `NSAllowsLocalNetworking` for local HTTP. Bonjour discovery is not implemented and no Bonjour service declaration is needed yet. Validate the actual local-network permission flow on a physical iPad.

## Live acceptance checklist — device/server checks pending

Use a non-live desktop presentation and record the desktop version, Xcode/iPadOS versions, configured ports, and results in `development-log.md`.

1. Simulator build/launch and the initial portrait screen were verified on iPad Pro 11-inch (M5), iOS 27.0. Still check physical-device launch, landscape, light/dark appearance, and large text. Verify all controls remain accessible.
2. Confirm the General API is enabled. Connect with no password where none is configured; then with the correct and wrong API passwords. Check the local-network permission prompt and denied-permission behavior on a physical iPad.
3. Try a bad hostname, unreachable IP, disabled API, wrong port, and incompatible/older desktop version. Errors must be readable and controls disabled.
4. Run Previous and Next on a test presentation. Confirm the intended output changes on the desktop. The app must not claim that command acceptance proves a slide change.
5. Cancel Clear all's confirmation, then confirm it. Verify audio/background/overlay/timer scope and output-lock behavior. Restore with and without a usable cached output.
6. Disconnect or interrupt Wi-Fi during a command. Check the desktop before reconnecting: an uncertain command may have executed and must not be replayed automatically. Repeat with rapid taps.
7. Background/foreground the app during a request. Confirm stale responses cannot re-enable controls and reconnection is explicit.
8. Change the desktop directly and use Refresh status. The label must remain a snapshot; desktop pushes and current-slide synchronization are later work.

The pinned research baseline is FreeShow `1.6.8-beta.3`. The earlier handoff reported `1.5.2` on its source machine; this is not evidence of compatibility or the version on the test machine. No supported desktop release is declared until these live checks pass.

Milestone 2 is ready for review after automated validation; live acceptance remains outstanding. The next planned increment is scripture search, with its own capability checks and review.
