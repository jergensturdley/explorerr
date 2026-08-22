# Changelog

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
  (F2 rename, F4 terminal, F5 refresh/copy, F6 move — previously mapped to the
  wrong keycodes)

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
