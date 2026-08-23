# Changelog

## 1.1.10 (2026-08-23)

### Smooth Scrolling & Autoscroll
- Fixed jerky terminal scrolling by forcing synchronous layout manager geometry
  calculation (`layoutManager.ensureLayout(for:)`) before calculating document
  scroll bounds, eliminating 1-frame position lag.
- Implemented smart autoscroll: output automatically sticks to the bottom when
  new text arrives or when user types input. If the user manually scrolls up to
  review scrollback history, auto-scrolling pauses so text does not jump, and
  smoothly resumes when scrolling back to the bottom.

## 1.1.9 (2026-08-23)

### Terminal Rendering & Legibility Fixes
- Fixed diagonal stair-stepping output (e.g. `ls` output scattering across the
  screen) by ensuring newline characters (`\n`) automatically reset the cursor
  column to 0.
- Brightened the standard dark blue palette color to vibrant Campbell Powershell
  blue (`#3B78FF`) and added bright `LSCOLORS` to the clean profile, dramatically
  improving folder name readability on dark backgrounds.

## 1.1.8 (2026-08-23)

### Header & Command Bar Layout
- Fixed the cramped titlebar in single-pane mode: removed the blank sidebar spacer
  from the titlebar so the tab strip spans the entire header across to the caption buttons.
- Removed the unsightly horizontal scrollbar indicator that ran across the command bar.
- Fixed command bar item spacing and margins, anchoring the gear Options button cleanly
  on the trailing edge with proper breathing room.

## 1.1.7 (2026-08-23)

### Options & UI Fixes
- Fixed vertical positioning and bottom-edge clipping of nested submenus (such
  as the View menu's "Show" submenu). Submenus now clamp within the window
  boundaries and no longer extend off the bottom of the screen.
- Fixed "Restore Defaults" in Settings to reset per-folder view preferences and
  reset active open tabs to default view mode (.details) and sort order.
- Fixed runaway drag-resizing in `PaneSplitter` and `NavResizeDivider` by
  tracking incremental translation deltas rather than cumulative offsets.
- Added the custom Windows 11-styled "About Explorerr" dialog to the application menu.

### Integrated Terminal Experience
- Auto-focus terminal on reveal: toggling the terminal with `F4` or `⌥⌘T`
  automatically makes the terminal text view active so you can start typing immediately.
- Automatic CWD synchronization on reveal: opening the terminal now auto-CDs to
  the active folder if navigation occurred while the terminal was closed.
- Added `⌘K` shortcut to clear the terminal screen and scrollback buffer.
- Added `⇧⇥` (Shift-Tab) translation to standard ANSI backtab (`\e[Z`) for reverse
  autocompletion navigation in zsh and CLI tools like fzf.
- Dynamic font zoom with `⌘+` / `⌘=` (zoom in), `⌘-` (zoom out), and `⌘0` (reset).
- Right-click context menu in the terminal with Copy, Paste, Select All, Clear
  Terminal, cd to Active Folder, and Restart Shell.
- Drag-and-drop support: dragging files or folders into the terminal inserts
  their shell-escaped paths directly at the prompt.
- ANSI `CSI 3 J` support to clear the scrollback buffer via standard `clear` command.
- Added support for colon-delimited 24-bit SGR color sequences (`\e[38:2::r:g:bm` /
  `\e[38:2:r:g:bm`) used by modern CLI tools (`bat`, `delta`, `exa`, `rustc`).
- Protected against terminal hangs on invalid/binary output by bounding split UTF-8
  recovery and falling back to lossy UTF-8 decoding.

## 1.1.6 (2026-08-23)

### Options / dropdown menus
- Fixed the gear button so it actually opens the Settings scene. It previously
  dispatched `NSApp` selectors that nothing in the responder chain could ever
  resolve; it now uses the native SwiftUI `openSettings` action on macOS 14+,
  with an AppKit fallback on macOS 13.
- Fixed a layout bug that had every Win11 dropdown appearing shifted left by
  half its width and up by half its height (`.position()` centers a view, but
  the anchor's top-left corner was being passed). Menus now open directly
  under their button and are clamped on-screen; submenus flip left near the
  window edge.
- The command bar now scrolls horizontally when a pane is too narrow (e.g.
  three-pane layout), so the "…" and gear buttons can no longer be clipped
  out of reach.
- Restored the custom menu-bar menu by renaming it from "View" to "Layout".
  The previous name collided with macOS's own View menu, which silently
  dropped the app's items.

### Terminal
- The terminal header was redesigned as a proper Windows Terminal-style bar
  (always dark): a live green/red status dot, the real shell name instead of a
  hardcoded "zsh" badge, and a clearer restart button when the session exits.
- Fixed a possible crash when a fast terminal restart raced the pty's teardown
  (the process would abort on a "pty already started" precondition).

### Fixes
- Undoing a delete now restores items to their original folder instead of
  dumping them in the home directory.
- Added accessibility labels to the command-bar controls.

## 1.1.5 (2026-08-23)

### Terminal
- The integrated terminal now uses a clean minimal prompt by default instead
  of loading your shell profile, so fastfetch, powerlevel10k and similar
  startup output no longer mangle the built-in emulator. Homebrew paths stay
  on PATH, and TERM_PROGRAM is set to Explorerr. Turn on "Load my shell
  profile and startup files" in Options to get your own zshrc back.
- Fixed a bug present since 1.0: the shell prompt was often invisible. The
  emulator pushed the top rows (with the prompt) into scrollback during the
  window's layout-settling resizes, leaving a blank screen pinned into view.
  Blank rows are now trimmed first.
- The terminal no longer swallows every Cmd shortcut while focused: Cmd-,
  Cmd-T, Cmd-W and the rest reach the menu bar again (Cmd-C/Cmd-V keep
  their terminal behavior).

### Options
- A gear button on the command bar opens Options directly, in addition to
  Cmd-, and the "..." menu.

Self-test: 67 checks, including a real pty spawn-and-echo test.

## 1.1.4 (2026-08-22)

### The Shelf
- New staging strip docked at the bottom of the window: park files there
  while you browse, then place them in the active folder with "Copy here"
  or "Move here" (move clears the Shelf, copy keeps it for re-placing).
- Add via drag and drop, right-click "Add to Shelf", or Shift-Cmd-S. The
  strip appears whenever it has content, and during a drag so an empty
  Shelf can catch the drop. Chips drag back out as real files, double-click
  reveals the file, missing files dim and get pruned. Shared across windows
  and persisted across launches.

### Rich Options (Cmd-,)
- General: open new windows and new tabs to Home or the home folder;
  Windows-style "single-click to open" mode (modifiers still select);
  toggle for double-click-empty-space-goes-up; terminal follow; Full Disk
  Access status and grant shortcut.
- Appearance: theme System / Light / Dark (applies to the Win11 palettes
  and native menus alike); compact rows for Details and List; status bar
  and details pane toggles; sidebar section toggles (Gallery, cloud
  storage, Network, Recycle Bin).
- Files: existing file toggles plus privacy controls: disable recent-file
  tracking entirely and clear the list.

### Fixes
- A cancelled drag no longer leaves internal drag state stale.
- Restore Defaults keeps the one-time permission-prompt flag.

Self-test: 60 checks.

## 1.1.3 (2026-08-22)

- Fix: double-clicking an item navigated up a directory (entering a folder
  bounced straight back out). The "double-click empty space goes up" feature
  used a parent gesture recognizer that also fired over items; it now lives
  in the window's event monitor with precise item-frame hit-testing, and
  "empty" means below the last item, so the details header and gaps between
  tiles no longer count. Verified both ways with synthesized double-clicks.
- File access: the app now asks for Desktop/Documents/Downloads permission
  once at first launch (with proper usage descriptions, including removable
  and network volumes), shows Full Disk Access status in Options with a
  button that opens the right System Settings pane, and the Recycle Bin
  explains that macOS needs Full Disk Access to show trash contents instead
  of appearing empty.
- Self-test: 57 checks.

## 1.1.2 (2026-08-22)

- Fix: navigating did not update the content area. The location router lived
  in the window body, which never observes the tab, so clicking a sidebar
  entry (or any navigation that changes the view type, like Home to a folder)
  left the old content on screen until something else redrew the window.
  Switching tabs and the sidebar's active-tab highlight had the same stale
  reference problem. The pane column is now built from views that observe the
  tab controller and the active tab, so navigation, tab switches, and the
  sidebar all update immediately. Present since 1.0.0; verified interactively
  (Home to This PC and back) after the fix.

## 1.1.1 (2026-08-22)

- Fix: the titlebar row claimed half the window height (tab strips and window
  controls floated mid-air, content squeezed into the bottom half). The
  flexible nav-width placeholder introduced with the strip-alignment fix made
  the row vertically greedy; it is now pinned to the 36pt strip height.
- CI: actions/checkout and actions/upload-artifact bumped to v5 (clears the
  Node 20 deprecation warnings).

## 1.1.0 (2026-08-22)

Navigability release: Explorer/Dolphin muscle memory everywhere, plus fixes
for every UI regression found in 1.0.

### Selection
- Rubber-band (marquee) selection in Details, Icons, Tiles, List, and Gallery,
  with live updates, ⌘/⇧-band add, Win11-accent band, and autoscroll at the
  viewport edge
- Instant single-click selection (removed the ~250ms double-click-recognizer lag);
  reliable ⇧/⌘-click
- ⇧+arrows extend the selection; Invert Selection (⇧⌘A); status bar shows the
  selected total size

### Keyboard
- Grid-aware arrow navigation: ↑↓←→ move by on-screen geometry in every view,
  ←/→ wrap rows in icon views, Home/End/PgUp/PgDn, type-ahead ("type to select",
  repeated letter cycles)
- Esc clears the search, then the selection
- Real Edit-menu wiring: ⌘X/⌘C/⌘V/⌘A/⌘Z/⇧⌘Z now act on files (with text-field
  fallback while renaming or editing the path), Copy as Path (⇧⌘C), Duplicate (⌘D)
- Go shortcuts: Back ⌘[, Forward ⌘], Up ⌘↑, Open Selection ⌘↓; Windows keys fixed
  (F2 rename, F4 terminal, F5 refresh/copy, F6 move; these were previously
  mapped to the wrong keycodes)

### Tabs
- Drag tabs to reorder; middle-click a tab to close it
- Ctrl+Tab / Ctrl+Shift+Tab cycling; Reopen Closed Tab (⇧⌘T); terminal toggle
  moved to ⌥⌘T (F4 still works)
- Middle-click a folder item, breadcrumb segment, or sidebar folder to open it
  in a background tab; mouse buttons 4/5 go back/forward

### Navigation & panes
- Drop files onto sidebar folders and onto folder rows/tiles (no need to enter
  the folder first)
- Address-bar history entries jump the exact number of steps; Forward list is
  ordered nearest-first
- Alt+double-click opens Properties; double-click empty space goes up (Dolphin)
- Dolphin-style terminal follow: navigating cd's the integrated terminal when
  the shell is idle and unfocused (toggle in Options)
- Clicking a pane's tab strip activates that pane; pane hit-testing fixed near
  the window bottom; multi-window keyboard/mouse events no longer cross windows

### Fixes
- Titlebar tab strips no longer overflow the window (caption buttons were
  clipped off-screen)
- Details header columns align exactly with rows; column resize no longer
  accelerates or drags inverted; clicking a row no longer re-centers the list
- Released DMGs now stamp the real version into the app's Info.plist; version
  strings are sanitized; CI builds and verifies a DMG on every push/PR
- Preferences survive app updates that add new settings keys

### Engineering
- Self-test grown from 30 to 52 checks (band math, spatial navigation, history
  jumps, tab reorder/reopen, prefs decoding)

## 1.0.0 (2026-08-22)

First public release.

### Windows 11 File Explorer experience
- Win11 chrome: mica backdrop, tab strip in the titlebar, Windows caption buttons
- Command bar (New, Cut, Copy, Paste, Rename, Share, Delete, Sort, View, Filter, See more)
- Breadcrumb address bar with per-segment dropdowns and recent locations
- Navigation pane: Home, Gallery, quick access pins, cloud storage, This PC, Network, Recycle Bin
- Acrylic Win11-style dropdown menus, vector Win11 folder icons, light and dark themes

### Windows 10 file management
- Copy/cut/paste with Replace/Skip/Keep-both conflicts, apply-to-all, progress, cancel
- Recycle Bin delete/restore/empty with undo and redo for rename, delete, copy, and move
- Details/List/Icons/Tiles views, resizable and auto-fit columns, per-folder view memory
- Recursive search with scope options and category filters
- Home (quick access + recents), This PC (drive usage), Gallery, Trash, Network
- Properties dialogs, sharing, Send to (including zip), pinning, drag and drop

### OneCommander-style multi-pane
- Up to 3 panes, each with independent tabs, command bar, and address bar
- Draggable splitters, active-pane highlighting, click-to-activate
- F5/F6 copy/move to the other pane; Navigate Panes Together (Option-Cmd-S)
- Full layout persistence and restore

### Integrated terminal
- Real pty (posix_openpt + fork + execve) running the user's login shell
- Hand-written VT100/xterm-256color emulator: 16/256/truecolor SGR, scrollback,
  alt-screen, line wrap, OSC title
- Campbell palette on #0C0C0C, block cursor, follow-output scrolling
- cd-to-active-folder sync, restart, clear, resize; F4 or Shift-Cmd-T toggles

### Editable address bar
- Paste paths with quotes, file:// URLs, ~ expansion, trailing slashes
- Live folder autocomplete with arrow keys, Option-Return opens in a new tab
- Esc cancels, inline "can't find" errors keep the editor open

### macOS integration (nothing sacrificed)
- Quick Look (Space / Cmd-Y), Open With submenu, Details pane with image dimensions
- Zoomable view density (Cmd-= / Cmd- / Cmd-0), Show in Finder, standard menus

### Engineering
- Zero dependencies; builds with Command Line Tools only (no Xcode)
- `Explorerr --selftest`: 30 headless logic checks (path engine, VT emulator, naming, search)
- `scripts/make-app.sh` bundles and signs; `scripts/verify.sh` launch-verifies
