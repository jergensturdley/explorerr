# Explorerr: AGENTS.md

Windows-style file explorer for macOS. Explorerr is a native (SwiftUI + AppKit) macOS app
that is visually faithful to Windows 11 File Explorer and functionally modeled on
Windows 10 File Explorer for ease of use, with OneCommander-style multi-pane and an
integrated terminal.

## Toolchain constraints (important)

- This machine has Command Line Tools only (`xcode-select` points at
  `/Library/Developer/CommandLineTools`). There is no full Xcode, so:
  - Do NOT use `xcodebuild`, `xcodegen`, or `.xcodeproj` files; they will fail.
  - Build with Swift Package Manager: `swift build` / `swift run`.
  - The `.app` bundle is assembled by `scripts/make-app.sh` (copies the release binary plus
    `Resources/Info.plist` into `Explorerr.app`, ad-hoc codesigns).
- Swift 6 compiler, package builds in Swift 5 language mode (`swiftLanguageModes: [.v5]`)
  to keep AppKit/NSWindow interop free of strict-concurrency friction.
- Minimum deployment target: macOS 13. Do not use macOS 14+ only APIs without gating.
- XCTest is unavailable with CLT-only installs, so logic checks live in
  `Sources/Explorerr/Core/SelfTest.swift` and run via `Explorerr --selftest` (exits 0 on pass).
- `fork()` is blocked in Swift; the pty uses a small C shim target (`Sources/CSupport`).

## Build / run / test

```sh
swift build                     # debug build (compile check)
swift build -c release          # release build
.build/debug/Explorerr --selftest   # logic checks (30 checks)
./scripts/make-app.sh           # build release + assemble + sign build/Explorerr.app
open build/Explorerr.app        # launch
./scripts/verify.sh             # build, bundle, launch, check process alive, quit
./scripts/gen-icon.swift        # regenerate Resources/AppIcon.icns (then re-run make-app)
```

## Architecture

Two targets: `CSupport` (C shim exposing `fork_shim()`) and the `Explorerr` executable
in `Sources/Explorerr/`. No external dependencies.

| Area | Files | Notes |
|---|---|---|
| App entry / scene | `App/ExplorerrApp.swift` | WindowGroup, menu-bar Commands, Settings, About, `--selftest` |
| Win11 theme | `Theme/Win11Theme.swift` | All colors/spacing/radii live in `Win11` (light + dark palettes). Never hardcode colors elsewhere. |
| Icons | `Icons/…` | Custom-drawn Win11 folder icons (plain + special), file page icons, drive/PC/trash icons, async QL thumbnails with NSCache. |
| Window chrome | `Chrome/…` | Hidden macOS titlebar (`WindowConfigurator`), Windows caption buttons (`WindowControls`), Mica backdrop, per-pane tab strips (`TabStrip.swift`), custom dropdown menu system (`MenuPopup.swift`, anchored in the window coordinate space named "win"). |
| Bars | `Chrome/CommandBar`, `AddressBar`, `StatusBar` | Win11 command bar; breadcrumb address bar with editable path mode (paste normalization + autocomplete in `PathBarEngine`); Win10-style status bar. |
| Navigation pane | `Views/NavigationPane.swift` | Home, Gallery, pins, cloud storage, This PC tree, Network, Recycle Bin; resizable divider. |
| Content | `Views/FolderViews`, `FolderContentView` | Details/list/icons/tiles per tab, selection model, context menus, inline rename, drag and drop. |
| Special views | `Views/SpecialViews.swift`, `Dialogs.swift` | Home, This PC (drive usage), Gallery, Trash, Network; conflict/progress/properties/about/shortcuts dialogs. |
| Core state | `Core/AppModel`, `TabState`, `WindowModel`, `Persistence` | `AppModel` shared (prefs, pins, undo, recents, clipboard-cut); `TabController` per pane; `WindowModel` per window (1-3 panes, weights, sync panes, terminal visibility). Session layouts persist in UserDefaults with legacy migration. |
| File ops | `Core/FileOps.swift` | Copy/cut/paste via NSPasteboard, Replace/Skip/Keep-both conflicts, recycle + restore, rename, new items, undo, cross-volume move fallback, ditto zip. |
| Terminal | `Core/PtyProcess`, `TerminalEmulator`, `TerminalController`, `Views/TerminalPanelView` | posix_openpt + fork + execve spawn the login shell; VT100/xterm-256color emulator (CSI/SGR/OSC, scrollback, alt-screen); key translation is IME-safe. |
| Menus/shortcuts | `App/Commands.swift` + event monitors in `App/MainWindow.swift` | Win-style keys (F2 rename, Cmd-R refresh, Option-arrows, Backspace = Up) and Dolphin keys (F4 terminal, F5/F6 pane transfer). Right-click uses native `.contextMenu`; command-bar dropdowns use the custom Win11 popup. |

## Conventions

- Everything UI is SwiftUI; AppKit only behind `NSViewRepresentable` bridges (window config,
  visual-effect blur, terminal text view, sharing picker).
- Main-actor UI state (`AppModel`, `WindowModel`, `TabController`, `TabState`,
  `TerminalController` are ObservableObject); filesystem enumeration runs off-main via
  `Task`/`Task.detached`, results marshaled back to the main actor.
- Persistence = UserDefaults (JSON payloads): prefs, quick-access pins, per-folder view/sort,
  recents, session layout (panes x tabs x weights x sync x terminal), trash origins.
  Keys are centralized in `Core/Persistence.swift`.
- All user-facing strings in English, Windows terminology ("This PC", "Recycle Bin",
  "Date modified", "New folder").
- Windows date format via short date + time styles, ByteCountFormatter for sizes.
- Do not regress macOS affordances when adding Windows behaviors: Quick Look, Show in Finder,
  drag and drop, fullscreen keys, and standard menus must keep working.

## Visual fidelity reference (Win11)

- Window/mica chrome #F3F3F3 (dark #202020), solid white content card with rounded
  top-left corner (8px), accent #0067C0 (dark #4CC2FF), selection pill #CBE3F8
  (dark #2E4256), 4px control corner radius, 8px menu radius, Windows caption buttons
  (close hovers #C42B1C).
- Folder icons: two-tone yellow Win11 folders; special folders carry emblems.
- Terminal: Windows Terminal Campbell palette on #0C0C0C, always dark.
