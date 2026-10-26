# Gates: Explorerr review fixes (Act-on list)

OWNS: Sources/Explorerr/**, GATES.md

Scope: implement the ten verified "Act on" fixes from the 2026-09-03 review (registry fan-out, main-thread transfers, package open, anchor crash, drag semantics, breadcrumb laziness, notification fan-out, rename theming, data-loss defaults, small items) with selftest coverage for every logic-verifiable fix; build clean and selftest green.

- [x] G1: debug build compiles with no errors
  CHECK: swift build 2>&1
  EXPECT: Build complete
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Volumes/M.2 2TB/code/explorerr; path=bf36eb780df5/38 entries; EXPECT=matched; output-sha256=e001c411c162392d1592684741ae4aaa868217f179c9434f7392217f351f8184; output-bytes=119

- [x] G2: selftest passes and includes the new checks for registry fan-out, anchor clamp, redo closure, package-open decision, drop-source resolution, delete-confirm text, trash-origin keys, and filter reset (baseline pass above predates the new checks; this gate re-runs after they exist)
  CHECK: /bin/zsh -c '.build/debug/Explorerr --selftest > /tmp/explorerr-selftest-gates.txt 2>&1 && grep -q "window registry fan-out" /tmp/explorerr-selftest-gates.txt && grep -q "stale anchor" /tmp/explorerr-selftest-gates.txt && grep -q "redo closure" /tmp/explorerr-selftest-gates.txt && grep -q "package open" /tmp/explorerr-selftest-gates.txt && grep -q "drop source" /tmp/explorerr-selftest-gates.txt && grep -q "delete confirm" /tmp/explorerr-selftest-gates.txt && grep -q "trash origins" /tmp/explorerr-selftest-gates.txt && grep -q "filters reset" /tmp/explorerr-selftest-gates.txt && grep "SELFTEST PASSED" /tmp/explorerr-selftest-gates.txt'
  EXPECT: SELFTEST PASSED
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Volumes/M.2 2TB/code/explorerr; path=bf36eb780df5/38 entries; EXPECT=matched; output-sha256=ade2f79e23d10d2565c6e015f65ae942aedded61f0bbeb17bbf2c8f8d870cb4f; output-bytes=28

- [x] G3: inline rename field uses palette colors, no hardcoded white fill or light-mode accent stroke (patterns are unique to that view in this file)
  CHECK: /bin/zsh -c 'f=Sources/Explorerr/Views/FolderContentView.swift; n1=$(grep -c "fill(Color.white)" $f); n2=$(grep -c "Color(red: 0, green: 103/255" $f); n3=$(grep -c "p.contentCard" $f); n4=$(grep -c "p.accent" $f); echo "$n1 $n2 $n3 $n4"'
  EXPECT: 0 0 1 1
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Volumes/M.2 2TB/code/explorerr; path=bf36eb780df5/38 entries; EXPECT=matched; output-sha256=783d7805356f611b21330624c0568b9df7b51ecae255eb190603cf341c1cf9ce; output-bytes=8

- [x] G4: every item view renders the inline rename field, including List view (4 call sites: DetailsRow, IconTile, ListRow, TileView)
  CHECK: /bin/zsh -c 'grep -c "InlineRenameField" Sources/Explorerr/Views/FolderViews.swift'
  EXPECT: 4
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Volumes/M.2 2TB/code/explorerr; path=bf36eb780df5/38 entries; EXPECT=matched; output-sha256=7de1555df0c2700329e815b93b32c571c3ea54dc967b89e81ab73b9972b72d1d; output-bytes=2

- [x] G5: ⇧⌘C keyboard shortcut is bound exactly once in the menu commands (Copy as Path); This PC uses a different shortcut
  CHECK: /bin/zsh -c 'n=$(grep -c "keyboardShortcut(\"c\", modifiers: \[.command, .shift\])" Sources/Explorerr/App/Commands.swift); m=$(grep -A1 "Button(\"This PC\")" Sources/Explorerr/App/Commands.swift | grep -c "keyboardShortcut(\"e\""); echo "$n $m"'
  EXPECT: 1 1
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Volumes/M.2 2TB/code/explorerr; path=bf36eb780df5/38 entries; EXPECT=matched; output-sha256=3f11ad6bbc7ecca0b2416b713dee77f1a635c00aaeaa946e14cde1c2bfae56d5; output-bytes=4

- [x] G6: breadcrumb child-folder menus are built lazily on open, not eagerly in the render body
  CHECK: /bin/zsh -c 'n=$(grep -c "entries: folderChildrenMenu" Sources/Explorerr/Chrome/AddressBar.swift); m=$(grep -c "lazyEntries: { folderChildrenMenu" Sources/Explorerr/Chrome/AddressBar.swift); echo "$n $m"'
  EXPECT: 0 2
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Volumes/M.2 2TB/code/explorerr; path=bf36eb780df5/38 entries; EXPECT=matched; output-sha256=665ae877edd92e755fe8504188724e0438a217c62edad817b262fb85e6289a88; output-bytes=4

- [x] G7: cross-window notifications are guarded by key-window checks in MainWindow (helper definition + 5 receiver guards), and the address bar only enters edit/search mode for the active pane (2 guards)
  CHECK: /bin/zsh -c 'n=$(grep -c "isKeyWindow()" Sources/Explorerr/App/MainWindow.swift); m=$(grep -c "windowModel.activeTab === tab" Sources/Explorerr/Chrome/AddressBar.swift); echo "$n $m"'
  EXPECT: 6 2
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Volumes/M.2 2TB/code/explorerr; path=bf36eb780df5/38 entries; EXPECT=matched; output-sha256=402f6fa4ce4c801e924721619a740155973f253cfc33f8cdb0721518d83fee3d; output-bytes=4

- [x] G8: progress sheet title reflects copy vs move from the transfer operation
  CHECK: /bin/zsh -c 'grep -c "progress.isMove" Sources/Explorerr/Views/Dialogs.swift'
  EXPECT: 1
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Volumes/M.2 2TB/code/explorerr; path=bf36eb780df5/38 entries; EXPECT=matched; output-sha256=4355a46b19d348dc2f57c046f8ef63d4538ebb936000f3c9ee954a27460dd865; output-bytes=2

- [x] G9: Windows "Videos" library entries point at the macOS Movies folder in sidebar, Home, and This PC
  CHECK: /bin/zsh -c 'n=$(grep -c "\"Movies\"" Sources/Explorerr/Views/NavigationPane.swift); m=$(grep -c "\"Movies\"" Sources/Explorerr/Views/SpecialViews.swift); echo "$n $m"'
  EXPECT: 1 2
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Volumes/M.2 2TB/code/explorerr; path=bf36eb780df5/38 entries; EXPECT=matched; output-sha256=f251ddc12234e0da8d3b778bd0f7463fb477f16f47757f5617dc8b4ff4d4f14a; output-bytes=4

