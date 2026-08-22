# Changelog

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
