# Explorerr

[![CI](https://github.com/jergensturdley/explorerr/actions/workflows/ci.yml/badge.svg)](https://github.com/jergensturdley/explorerr/actions/workflows/ci.yml)

A Windows 11-style File Explorer for macOS. Native (SwiftUI + AppKit), zero dependencies,
and it does not need Xcode: Command Line Tools are enough to build it.

Windows 11 looks. Windows 10 ease. OneCommander-style multi-pane. A real terminal.

## Why

If you bounce between Windows and macOS, the muscle memory never transfers. Explorerr
brings the File Explorer you know to the Mac: the same tab strip, the same command bar,
the same breadcrumbs, the same F2 / Alt+Enter / Backspace habits. Under the hood it is a
fully native macOS app with no Electron, no web views, and no external packages.

## Feature tour

**Windows 11 visual fidelity**
- Mica-style translucent window backdrop, rounded corners, light and dark themes that follow your system
- Tab strip in the titlebar with Windows caption buttons (minimize, maximize/restore, close with its red hover)
- The full Win11 command bar: New, Cut, Copy, Paste, Rename, Share, Delete, Sort, View, Filter, See more
- Breadcrumb address bar with per-segment folder dropdowns and a recent-locations dropdown
- Navigation pane: Home, Gallery, quick access pins, cloud storage (iCloud Drive, OneDrive, Dropbox), This PC, Network, Recycle Bin
- Win11-style acrylic dropdown menus and vector-drawn two-tone yellow folder icons with special-folder emblems

**Windows 10 ease of use**
- Copy / cut / paste with Replace / Skip / Keep-both conflicts, apply-to-all, progress, and cancel
- Delete to Recycle Bin, restore, empty, plus an undo/redo stack for rename, delete, copy, and move
- Inline rename (F2), New Folder, New Text Document, duplicate, zip via Send to
- Details / List / Icons / Tiles views with resizable columns and double-click column auto-fit
- Per-folder view and sort memory (each folder remembers how you like to see it)
- Recursive search with "all subfolders" or "current folder" scopes, plus category filters
- Home page with quick access cards and recent files; This PC with drive usage bars; Gallery; Trash
- Editable address bar: click it, paste any path (quotes, file:// URLs, ~, trailing slashes all handled),
  with live folder autocomplete, arrow-key selection, and Option-Return to open in a new tab
- Properties dialogs, sharing, Show in Finder, Open in Terminal, pin to quick access, drag and drop in every direction
- Windows keyboard muscle memory: F2 rename, F5 refresh, Alt+arrows for navigation, Backspace for up,
  Cmd+Delete to trash, Alt+Enter for Properties, Ctrl-style shortcuts on the Command key

**Navigability (Explorer / KDE Dolphin habits, added in 1.1)**
- Rubber-band (marquee) selection in every view, with live updates, Cmd/Shift-band to add,
  and autoscroll when the band reaches the viewport edge
- Instant single-click selection, Shift/Cmd-click, Shift+arrows to extend, Invert Selection
- Grid-aware arrow keys: Up/Down/Left/Right move by what is actually on screen in every view,
  plus Home/End/PageUp/PageDown and type-ahead (just start typing; repeat a letter to cycle)
- Tabs like a browser: drag to reorder, middle-click to close, Ctrl+Tab / Ctrl+Shift+Tab to
  cycle, Shift-Cmd-T reopens the last closed tab
- Middle-click a folder, a breadcrumb segment, or a sidebar folder to open it in a background
  tab; mouse buttons 4/5 go back/forward
- Drop files onto sidebar folders or onto folder rows and tiles without entering them first
- The address-bar history menu jumps straight to any entry; Esc clears the search, then the
  selection; the status bar shows the total size of the selection
- Dolphin extras: double-click empty space to go up, F4 terminal, and the terminal can follow
  your navigation with an automatic cd whenever the shell is idle (Options toggle)

**OneCommander-style multi-pane**
- Up to three side-by-side panes, each with its own tabs, command bar, and address bar
- Per-pane tab strips in the titlebar, draggable splitters, active-pane highlighting
- Commander keys in multi-pane mode: F5 copies and F6 moves the selection to the other pane
- Navigate Panes Together (Option-Command-S): Dolphin-style locked panels that mirror navigation
- The whole layout (panes, tabs, active pane, widths) is saved and restored between launches

**An integrated terminal (F4 or Shift-Command-T)**
- A real pseudo-TTY running your login shell: colors, job control, vim, less, everything works
- Hand-written VT100/xterm-256color emulator: 16/256/truecolor, scrollback, alt-screen, block cursor
- Windows Terminal's Campbell palette on the classic #0C0C0C background
- Terminal conventions: Command-C copies when you have a selection and sends Ctrl-C when you don't,
  Command-V pastes, Esc reaches the shell, arrows and Ctrl-A through Ctrl-Z translate correctly
- "cd to the active folder" sync button, shell restart, follow-output scrolling, drag to resize,
  and the panel remembers its visibility and height

**The best of macOS, kept intact**
- Real Quick Look on Space or Command-Y
- Open With submenu with default app, alternates, and a picker
- Details pane with image dimensions and folder statistics
- Zoomable view density on Command-= / Command-minus / Command-0 (same idea as Finder)
- Show in Finder, drag out to other apps, fullscreen keys, and standard Mac menus

## Download

Grab the latest DMG from [Releases](https://github.com/jergensturdley/explorerr/releases),
drag Explorerr to Applications, and open it. The app is ad-hoc signed (no Apple Developer
ID), so the first launch needs a right-click, Open on newer macOS, or
System Settings, Privacy & Security, Open Anyway. Requires macOS 13 or newer.

## Build and run

Requires macOS 13 or newer and Swift 6 (Xcode Command Line Tools are sufficient).

```sh
git clone https://github.com/jergensturdley/explorerr
cd explorerr

swift build                     # debug compile check
./scripts/make-app.sh           # release build + app bundle + ad-hoc signature
open build/Explorerr.app        # launch it
```

Extra tools:

```sh
.build/debug/Explorerr --selftest    # headless logic checks (52 checks, no XCTest needed)
./scripts/verify.sh                  # build, bundle, launch, verify the process, quit
./scripts/make-dmg.sh                # package build/Explorerr.app into a drag-to-Applications DMG
./scripts/gen-icon.swift             # regenerate the app icon (writes Resources/AppIcon.icns)
```

The app is not sandboxed; it browses the filesystem with your user's permissions.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New window / new tab / close tab | Cmd-N / Cmd-T / Cmd-W |
| Reopen closed tab | Shift-Cmd-T |
| Next / previous tab | Ctrl-Tab / Ctrl-Shift-Tab |
| New folder | Shift-Cmd-N |
| Copy / Cut / Paste / Select all | Cmd-C / Cmd-X / Cmd-V / Cmd-A |
| Copy as path / Duplicate | Shift-Cmd-C / Cmd-D |
| Invert selection | Shift-Cmd-A |
| Undo / Redo | Cmd-Z / Shift-Cmd-Z |
| Rename | F2 |
| Move to Recycle Bin | Cmd-Delete (or fn-Delete) |
| Empty Recycle Bin | Shift-Cmd-Delete |
| Go up (parent folder) | Backspace, Option-Up, or Cmd-Up |
| Back / Forward | Option-Left / Option-Right, Cmd-[ / Cmd-], or mouse buttons 4/5 |
| Open selection | Return or Cmd-Down |
| Navigate items (grid-aware) | Arrow keys; Shift+arrows extend; Home / End / PgUp / PgDn |
| Type to select | Just start typing (repeat a letter to cycle matches) |
| Clear search, then selection | Esc |
| Refresh | Cmd-R (F5 in single-pane mode) |
| Views | Cmd-1 icons, Cmd-2 list, Cmd-3 details, Cmd-4 tiles |
| Zoom in / out / reset view | Cmd-= / Cmd-minus / Cmd-0 |
| Show hidden items | Cmd-Shift-. |
| Edit address bar (paste a path) | Cmd-L or Shift-Cmd-G, or click the empty breadcrumb area |
| Address bar: open typed path in new tab | Option-Return (while editing) |
| Properties of selection | Cmd-I, Option-Return, or Option-double-click |
| Quick Look | Space or Cmd-Y |
| Details pane | Shift-Cmd-I |
| Find (focus the search box) | Cmd-F |
| Middle-click a tab | Close it |
| Middle-click a folder / crumb / sidebar entry | Open in a background tab |
| Toggle dual pane | Cmd-\ |
| Focus next / previous pane | Shift-Cmd-] / Shift-Cmd-[ |
| Copy / move to other pane (multi-pane) | F5 / F6 |
| Navigate panes together | Option-Cmd-S |
| Toggle integrated terminal | F4 or Option-Cmd-T |

The same list ships in the app under Help, Explorerr Keyboard Shortcuts.

## Project layout

```
Sources/
├── CSupport/        C shim exposing fork() for the pty (Swift blocks it)
├── Explorerr/
│   ├── App/         entry point, MainWindow (multi-pane layout), menu commands, settings
│   ├── Chrome/      window chrome: pane tab strips, caption buttons, command bar,
│   │                address bar, status bar, dropdown menu system, Quick Look
│   ├── Core/        models, directory loading/search/volumes, AppModel, TabState,
│   │                WindowModel (multi-pane), FileOps, terminal (pty, VT emulator),
│   │                persistence, selftest
│   ├── Icons/       vector Win11 folder/file/drive icons, QuickLook thumbnails
│   ├── Theme/       Win11 design tokens (light + dark palettes, metrics, fonts)
│   └── Views/       folder content views, rubber-band selection + spatial navigation,
│                    navigation pane, Home, This PC, Gallery, Trash, Network,
│                    terminal panel, dialogs
scripts/             make-app.sh, make-dmg.sh, verify.sh, gen-icon.swift
Resources/           Info.plist, AppIcon.icns
```

See `AGENTS.md` for build constraints and architecture notes, `CONTRIBUTING.md` for how to
hack on it, and `CHANGELOG.md` for what shipped when.

## License

MIT. See `LICENSE`.
