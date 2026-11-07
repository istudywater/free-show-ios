# Mac Mini handoff

## Transfer

Copy the full local repository at `~/Documents/GitHub/free-show-ios` to the Mac Mini, including the Xcode project, Swift sources, scripts, and docs. Alternatively, commit and push these files before cloning on the Mac Mini. This milestone does not publish or push changes; the remote alone may still be empty.

The build has no dependency on the Obsidian vault or absolute paths from this Mac. Product planning remains in Obsidian; the operational instructions are all in this repository.

## Build and launch

1. Open Xcode and ensure iOS platform support and an iPad simulator runtime are installed.
2. Open `FreeShowRemote.xcodeproj` and select the shared `FreeShowRemote` scheme.
3. Select an iPad simulator, then Build and Run. The minimum app OS is iPadOS 17.
4. Confirm the app remains open with the FreeShow Remote title, welcome message, and Not connected status.
5. Rotate to landscape. Check portrait, light/dark appearance, larger accessibility text, and a smaller window if supported. Text should remain readable/scrollable. No live controls are present yet.
6. Record the Xcode version, simulator device/runtime, build result, and visual result in `docs/development-log.md`.

Optional command-line build from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-ipad.sh
```

Set `DEVELOPER_DIR` to the actual Xcode location if different. The build helper does not install or launch the app. Use Xcode Run for the acceptance check. `./scripts/check-foundation.sh` only typechecks using the host SDK and validates project references; it cannot establish iPad launch success.

## Resume development

Before Milestone 2, record which FreeShow desktop version will be used for integration tests and whether API/Remote services are enabled. Review `docs/freeshow-api.md`, especially authentication, one-based versus zero-based indexes, and the distinction between request success and observed output state.

Finish the Milestone 1 iPad build/launch checks, review the foundation, then proceed with the connection prototype. Scripture search is planned immediately after that prototype, subject to a separate review and capability checks. Do not run experimental presentation commands against a live service.
