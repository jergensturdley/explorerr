import SwiftUI
import AppKit

struct ExplorerCommands: Commands {
    @FocusedValue(\.explorerWindow) var windowModel
    @Environment(\.openWindow) private var openWindow

    private var tab: TabState? { windowModel?.activeTab }
    private var paneController: TabController? { windowModel?.activePane.controller }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Group {
                Button("New Window") {
                    openWindow(value: WindowSeed())
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Tab") {
                    paneController?.addTab(.home)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    if let tc = paneController, let active = tc.tabs.first(where: { $0.id == tc.activeID }) {
                        tc.closeTab(active.id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Reopen Closed Tab") { paneController?.reopenClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Next Tab") { paneController?.activateAdjacent(1) }
                    .keyboardShortcut(.tab, modifiers: .control)

                Button("Previous Tab") { paneController?.activateAdjacent(-1) }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])

                Divider()

                Button("Open…") {
                    openPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("New Folder") {
                    if let tab = tab, let dir = tab.currentFolderURL, let app = appModel {
                        Task { await FileOps.newFolder(in: dir, app: app, tab: tab) }
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(tab?.currentFolderURL == nil)

                Button("New Text Document") {
                    if let tab = tab, let dir = tab.currentFolderURL, let app = appModel {
                        Task { await FileOps.newTextDocument(in: dir, app: app, tab: tab) }
                    }
                }
                .disabled(tab?.currentFolderURL == nil)

                Divider()

                Button("Copy to Other Pane (F5)") {
                    if let window = windowModel, let app = appModel, let tab = tab,
                       let other = window.otherFolderPane,
                       let dest = other.active.currentFolderURL {
                        let items = tab.selectedItems
                        guard !items.isEmpty else { return }
                        Task { await FileOps.transfer(items.map { $0.url }, to: dest, move: false, app: app, tab: tab) }
                    }
                }
                .disabled(windowModel?.panes.count != 2 && windowModel?.panes.count != 3)

                Button("Move to Other Pane (F6)") {
                    if let window = windowModel, let app = appModel, let tab = tab,
                       let other = window.otherFolderPane,
                       let dest = other.active.currentFolderURL {
                        let items = tab.selectedItems
                        guard !items.isEmpty else { return }
                        Task { await FileOps.transfer(items.map { $0.url }, to: dest, move: true, app: app, tab: tab) }
                    }
                }
                .disabled(windowModel?.panes.count != 2 && windowModel?.panes.count != 3)

                Divider()

                Button("Properties") {
                    if let tab = tab, let app = appModel {
                        if let sel = tab.selectedItems.first {
                            app.activeSheet = .properties(sel.url)
                        } else if let dir = tab.currentFolderURL {
                            app.activeSheet = .properties(dir)
                        }
                    }
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Quick Look") {
                    if let tab = tab {
                        QuickLook.toggle(items: tab.selectedItems)
                    }
                }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(tab?.selectedItems.contains { !$0.isDirectory } != true)

                Divider()

                Button("Empty Recycle Bin…") { appModel?.activeSheet = .emptyTrash }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
        }

        // Real Edit-menu wiring: the advertised ⌘X/⌘C/⌘V/⌘A/⌘Z shortcuts act on files,
        // falling through to the focused text editor while renaming or editing the path.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                if let tv = focusedTextView() { tv.undoManager?.undo() }
                else { appModel?.undo() }
            }
            .keyboardShortcut("z", modifiers: .command)

            Button("Redo") {
                if let tv = focusedTextView() { tv.undoManager?.redo() }
                else { appModel?.redo() }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                if let tv = focusedTextView() { tv.cut(nil) }
                else if let tab = tab, let app = appModel { app.cutItems(tab.selectedItems) }
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Copy") {
                if let tv = focusedTextView() { tv.copy(nil) }
                else if let tab = tab, let app = appModel { app.copyItems(tab.selectedItems) }
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                if let tv = focusedTextView() { tv.paste(nil) }
                else if let tab = tab, let app = appModel, let dir = tab.currentFolderURL {
                    Task { await FileOps.paste(into: dir, app: app, tab: tab) }
                }
            }
            .keyboardShortcut("v", modifiers: .command)

            Button("Copy as Path") {
                if let tab = tab, !tab.selectedItems.isEmpty {
                    let paths = tab.selectedItems.map { $0.url.path }.joined(separator: "\n")
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(paths, forType: .string)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Duplicate") {
                if let tab = tab, let app = appModel, !tab.selectedItems.isEmpty {
                    Task { await FileOps.duplicate(tab.selectedItems, app: app) }
                }
            }
            .keyboardShortcut("d", modifiers: .command)

            Divider()

            Button("Select All") {
                if let tv = focusedTextView() { tv.selectAll(nil) }
                else { tab?.selectAll() }
            }
            .keyboardShortcut("a", modifiers: .command)

            Button("Invert Selection") { tab?.invertSelection() }
                .keyboardShortcut("a", modifiers: [.command, .shift])

            Divider()

            Button("Rename (F2)") {
                if let tab = tab, tab.selection.count == 1 {
                    tab.renamingID = tab.selection.first
                }
            }

            Button("Move to Recycle Bin") {
                if let tab = tab, let app = appModel, !tab.selectedItems.isEmpty {
                    Task { await FileOps.deleteItems(tab.selectedItems, app: app) }
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }

        CommandMenu("View") {
            Group {
                Button("as Icons") { tab?.setViewMode(.iconsMedium) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("as List") { tab?.setViewMode(.list) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("as Details") { tab?.setViewMode(.details) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("as Tiles") { tab?.setViewMode(.tiles) }
                    .keyboardShortcut("4", modifiers: .command)

                Divider()

                Button("Zoom In") { tab?.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { tab?.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Reset View (Details)") { tab?.setViewMode(.details) }
                    .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button(windowModel != nil && windowModel!.panes.count > 1
                       ? "✓ Dual Pane" : "Dual Pane") {
                    windowModel?.toggleDualPane()
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Add Pane (up to 3)") {
                    windowModel?.addPane()
                }
                .disabled(windowModel == nil || windowModel!.panes.count >= WindowModel.maxPanes)

                Button("Close Active Pane") {
                    windowModel?.closeActivePane()
                }
                .disabled(windowModel == nil || windowModel!.panes.count < 2)

                Button("Focus Next Pane") {
                    windowModel?.focusPane(advance: 1)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Focus Previous Pane") {
                    windowModel?.focusPane(advance: -1)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Divider()

                Button(appModel?.prefs.showDetailsPane == true ? "✓ Details Pane" : "Details Pane") {
                    appModel?.prefs.showDetailsPane.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button(windowModel?.syncPanes == true ? "✓ Navigate Panes Together" : "Navigate Panes Together") {
                    if let window = windowModel { window.syncPanes.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.option, .command])
                .disabled(windowModel == nil || windowModel!.panes.count < 2)

                Button(windowModel?.terminalVisible == true ? "✓ Terminal" : "Terminal (F4)") {
                    windowModel?.terminalVisible.toggle()
                }
                .keyboardShortcut("t", modifiers: [.command, .option])

                Button("Find (search this folder)") {
                    NotificationCenter.default.post(name: .explorerrFocusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button(appModel?.prefs.showHidden == true ? "✓ Show Hidden Items" : "Show Hidden Items") {
                    if let app = appModel {
                        app.prefs.showHidden.toggle()
                        app.reloadAllTabs()
                    }
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])

                Button(appModel?.prefs.showExtensions == true ? "✓ File Name Extensions" : "File Name Extensions") {
                    appModel?.prefs.showExtensions.toggle()
                }

                Button(appModel?.prefs.statusVisible == true ? "✓ Status Bar" : "Status Bar") {
                    appModel?.prefs.statusVisible.toggle()
                }

                Divider()

                Button("Refresh") { tab?.reload() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        CommandMenu("Go") {
            Group {
                Button("Back") { tab?.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Forward") { tab?.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Up to parent folder") { tab?.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Open Selection") {
                    if let tab = tab, let app = appModel { FileOps.openSelection(in: tab, app: app) }
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                Divider()

                Button("Home") { tab?.navigate(.home) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Documents") {
                    tab?.navigate(.folder(DirectoryLoader.homeURL.appendingPathComponent("Documents")))
                }
                Button("Downloads") {
                    tab?.navigate(.folder(DirectoryLoader.homeURL.appendingPathComponent("Downloads")))
                }
                Button("Pictures") {
                    tab?.navigate(.folder(DirectoryLoader.homeURL.appendingPathComponent("Pictures")))
                }
                Button("Music") {
                    tab?.navigate(.folder(DirectoryLoader.homeURL.appendingPathComponent("Music")))
                }
                Button("Videos") {
                    tab?.navigate(.folder(DirectoryLoader.homeURL.appendingPathComponent("Movies")))
                }
                Button("This PC") { tab?.navigate(.thisPC) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Recycle Bin") { tab?.navigate(.trash) }
                Button("Network") { tab?.navigate(.network) }

                Divider()

                Button("Go to Folder…") {
                    NotificationCenter.default.post(name: .explorerrBeginPathEdit, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Edit Address Bar") {
                    NotificationCenter.default.post(name: .explorerrBeginPathEdit, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }

        CommandGroup(replacing: .help) {
            Button("Explorerr Keyboard Shortcuts") {
                appModel?.activeSheet = .shortcuts
            }
        }
    }

    private var appModel: AppModel? {
        // AppModel is shared app-wide; grab it from the focused window's controller
        windowModel?.app
    }

    /// The focused text editor (rename field, path editor, search), if any — Edit-menu
    /// shortcuts forward to it instead of acting on files.
    private func focusedTextView() -> NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder to open in Explorerr"
        if panel.runModal() == .OK, let url = panel.url {
            tab?.navigate(.folder(url))
        }
    }
}
