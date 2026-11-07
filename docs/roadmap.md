# Roadmap

The seven milestones from the Obsidian **Codex Build Sequence Prompt** are the canonical implementation sequence. The five milestones in the earlier MVP summary are a high-level grouping, not a competing schedule.

| Milestone | Scope | Status |
| --- | --- | --- |
| 1 | Research, minimal Xcode project, app shell, initial interfaces, documentation | Implemented; iPad build/launch verification pending on Mac Mini |
| 2 | Manual connection, verified authentication, next/previous/clear/restore prototype | Not started |
| Early scripture increment | Translation selection, reference/text search, preview, explicit Present, scripture navigation | Planned after Milestone 2; agreed direction November 6, 2026 |
| 3 | Discovery, remembered connection, reconnection, local-network permissions, credential storage | Not started |
| 4 | Service projects, ordered items, desktop synchronization | Not started |
| 5 | Slides, thumbnails, direct selection, synchronization | Not started |
| 6 | Integrated landscape iPad operator interface | Not started |
| 7 | Network/lifecycle/concurrent-operator reliability and live-service testing | Not started |

The early scripture increment changes the original post-V1 deferral. It remains a distinct increment after a usable connection, and does not authorize implementing everything during Milestone 1. Verify the selected desktop version's Remote search/retrieval handlers before committing to its UI or transport. Local translations and API-backed translations require different search behavior.

At each milestone, document results and remaining verification, then stop for review before proceeding. No Milestone 2 networking, automatic discovery, presentation controls, or scripture search has been implemented in the foundation.

## Open decisions

- Supported FreeShow release: research baseline is 1.6.8-beta.3; local app is 1.5.2.
- Socket.IO client dependency and supported Engine.IO/Socket.IO versions.
- Operator-visible output scope when desktop outputs differ.
- Explicit preview/present interaction and clear/restore labeling.
- License, final bundle identifier, app icon, and release/distribution setup.

The foundation uses iPadOS 17+ and Swift 6. Revisit the deployment target only if actual device requirements demand it.
