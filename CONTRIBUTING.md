# Contributing to Explorerr

Thanks for wanting to help. This file is the short version of what you need.

## Setup

macOS 13 or newer and Swift 6. Full Xcode is NOT required; Command Line Tools work:

```sh
xcode-select --install        # if you don't have either toolchain
swift build                   # compiles the app
```

## Everyday commands

```sh
swift build                            # compile check
.build/debug/Explorerr --selftest      # logic checks; must pass before you commit
./scripts/make-app.sh                  # build/Explorerr.app (release + ad-hoc signed)
./scripts/verify.sh                    # build, bundle, launch, verify, quit
```

`--selftest` exits non-zero on any failure, so it works in CI too. If you add logic
(paths, naming, parsing, sorting, the VT emulator), add checks to
`Sources/Explorerr/Core/SelfTest.swift`.

## Ground rules

1. **No external dependencies.** Everything is SwiftUI/AppKit plus one tiny C shim
   (`Sources/CSupport`) that exposes `fork()` for the terminal's pty.
2. **Colors live in the theme.** Use `Win11.palette(scheme)` from `Theme/Win11Theme.swift`;
   never hardcode colors in views. Light and dark must both look right.
3. **Windows visuals, Windows terminology.** "This PC", "Recycle Bin", "Date modified",
   "New folder". Measure against real Win11 File Explorer screenshots when in doubt.
4. **Don't regress macOS affordances.** Quick Look, Show in Finder, drag and drop,
   fullscreen keys, and standard menus must keep working when you add Windows behaviors.
5. **Blocking IO stays off the main actor.** Directory loading goes through
   `Task.detached`; UI state updates on the main actor.
6. **Keep it buildable with CLT only.** No xcodeproj, no xcodebuild, no XCTest
   (that's why the selftest exists).

## Where things are

See `AGENTS.md` for the full architecture map. Quick pointers:

- Window chrome and bars: `Sources/Explorerr/Chrome/`
- File operations: `Sources/Explorerr/Core/FileOps.swift`
- Multi-pane layout: `Sources/Explorerr/Core/WindowModel.swift`
- Terminal: `Sources/Explorerr/Core/PtyProcess.swift`, `TerminalEmulator.swift`,
  `TerminalController.swift`, `Views/TerminalPanelView.swift`
- Icons: `Sources/Explorerr/Icons/`

## Pull requests

Small, focused PRs land fastest. Include:

- What you changed and why
- `swift build` and `--selftest` output (both green)
- Screenshots for anything visual, in light and dark mode

## License

By contributing you agree your work is released under the project's MIT license.
