# Roadmap

**November 7, 2026:** The user authorized building all remaining milestones without intermediate approval pauses, followed by one Xcode simulator review. This supersedes the earlier per-milestone stop instructions for this build. The seven-milestone sequence remains the implementation roadmap; scripture was added between Milestones 2 and 3.

| Milestone | Scope | Current status |
| --- | --- | --- |
| 1 | Research, Xcode project, models/interfaces, shell, documentation | Implemented; simulator build/launch verified |
| 2 | Manual connection/authentication and prototype controls | Implemented; 52 connection checks pass |
| Early scripture increment | Translation selection, search, preview, explicit Present/navigation | Implemented; 56 scripture checks pass; now shares operator connection |
| 3 | Discovery, remembered connection, credential storage, reconnect and refresh | Implemented; Bonjour/Keychain code compiled, injected reconnect/persistence checks pass; device/network acceptance pending |
| 4 | Ordered service projects/items and desktop synchronization | Implemented; local preview vs desktop project/live indicators are explicit |
| 5 | Flattened slides, lazy thumbnails/text fallback, direct presentation | Implemented; layout/child/repeat/index and pre-Present validation checks pass |
| 6 | Adaptive iPad operator interface and persistent live controls | Implemented; offline demo available; user simulator review is next |
| 7 | Failure handling, lifecycle/concurrent update behavior, duplicate protection, testing | Implemented with 59 operator checks and 200-operation navigation stress; real desktop/device/long-duration field acceptance remains pending |

All three automated suites pass **167 checks**. Simulator builds pass on Xcode 27.1 for arm64 and x86_64. See [operator guide](operator-guide.md) for review instructions and the outstanding acceptance checklist. No more implementation approval gates remain in this authorized build; user review follows completion.

## Current boundaries

Native shows, scripture, and uniquely named existing media/PDF/audio/overlay/player items in the active desktop project are supported. Ambiguous, unnamed and unsupported items remain desktop-operated. Read scope is the first active output, while broad commands may affect active outputs collectively. Duplicate occurrences have distinct local preview identities; an ON OUTPUT badge identifies the presentation on output, not a guaranteed occurrence index.

The source baseline is FreeShow 1.6.8-beta.3. A supported desktop release still needs live validation. Scripture collections, cross-chapter selections, arbitrary nonnumeric verse identifiers, editing/uploads, cloud sync, app artwork/distribution setup, and the repository license remain outside this MVP build.
