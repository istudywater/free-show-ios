# Xcode simulator review handoff

November 7, 2026

The implementation through Milestones 3–7 is ready for simulator review. The user authorized finishing these milestones together; older per-milestone stop notes are historical. Source, Xcode project, pinned packages, tests, licenses, and technical docs live in this repository. Obsidian contains the planning/review companion notes, with no build dependency on that vault.

1. Transfer or clone the complete current repository, including uncommitted files if transferring this working folder. No push was performed during the build.
2. Open FreeShowRemote.xcodeproj and choose FreeShowRemote plus an installed iPad simulator.
3. Run, then tap Try offline demo. Optional Debug scheme argument: `--demo`.
4. Rotate to landscape and review the three-panel console, or use compact Service/Slides/Live panes in portrait. The command dock stays visible. Check the distinction between preview and output.
5. Try the Scripture demo with `Sample 1:1–3`. These are clearly labeled sample sentences, not Bible content.
6. Follow [operator guide and acceptance checklist](operator-guide.md). Record simulator/device/version and your findings in the development log.

For real integration, enable desktop RemoteShow and use port 5510 (or its configured port) and the Remote password. General REST port 5506 is only relevant to the older prototype. Test on a non-live desktop presentation. Physical-iPad local-network/Keychain/discovery behavior, actual FreeShow compatibility/output effects, accessibility/layout edge cases, and long-duration field acceptance remain pending.

Automated validation: 167 checks across three suites, including 200 sequential navigation operations. Xcode 27.1 simulator builds pass for arm64/x86_64. See README.md for build/test commands and dependency requirements.
