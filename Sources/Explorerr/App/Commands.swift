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
            }
        }

        CommandGroup(after: .newItem) {
            Divider()
            Menu("Edit items") {
                Button("Cut") {
                    if let tab = tab, let app = appModel { app.cutItems(tab.selectedItems) }
                }
                Button("Copy") {
                    if let tab = tab, let app = appModel { app.copyItems(tab.selectedItems) }
                }
                Button("Paste") {
                    if let tab = tab, let app = appModel, let dir = tab.currentFolderURL {
                        Task { await FileOps.paste(into: dir, app: app, tab: tab) }
                    }
                }
                Button("Copy as path") {
                    if let tab = tab {
                        let paths = tab.selectedItems.map { $0.url.path }.joined(separator: "\n")
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(paths, forType: .string)
                    }
                }
                Divider()
                Button("Undo") { appModel?.undo() }
                Button("Redo") { appModel?.redo() }
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
            }
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
                .keyboardShortcut("t", modifiers: [.command, .shift])

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
                Button("Forward") { tab?.goForward() }
                Button("Up to parent folder") { tab?.goUp() }

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
