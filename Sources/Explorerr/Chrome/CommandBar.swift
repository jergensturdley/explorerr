import SwiftUI

struct CommandBar: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @State private var optionsOpener: (() -> Void)?

    private var selection: [FSItem] { tab.selectedItems }
    private var hasSelection: Bool { !selection.isEmpty }
    private var inFolder: Bool { tab.currentFolderURL != nil }

    var body: some View {
        let p = Win11.palette(theme.scheme)
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    // New ▾
                    WinMenuButton(width: 224, enabled: inFolder, entries: newMenu) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                            Text("New")
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                        }
                    }
                    .buttonStyle(WinStandardButtonStyle(enabled: inFolder))
                    .help("Create a new item")

                    barDivider(p)

                    commandIcon("scissors", help: "Cut (⌘X)") { app.cutItems(selection) }
                        .disabled(!hasSelection)

                    commandIcon("doc.on.doc", help: "Copy (⌘C)") { app.copyItems(selection) }
                        .disabled(!hasSelection)

                    Button {
                        if let dest = tab.currentFolderURL {
                            Task { await FileOps.paste(into: dest, app: app, tab: tab) }
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 14))
                    }
                    .buttonStyle(WinIconButtonStyle(enabled: inFolder))
                    .disabled(!inFolder)
                    .help("Paste (⌘V)")
                    .accessibilityLabel("Paste")

                    commandIcon("character.cursor.ibeam", help: "Rename (F2)") {
                        if let first = selection.first { tab.renamingID = first.id }
                    }
                    .disabled(selection.count != 1)

                    if hasSelection, !selection.filter({ !$0.isDirectory }).isEmpty {
                        ShareLink(items: selection.filter { !$0.isDirectory }.map { $0.url }) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                        }
                        .buttonStyle(WinIconButtonStyle())
                        .help("Share")
                        .accessibilityLabel("Share")
                    } else {
                        ShareLink(items: [tab.currentFolderURL ?? DirectoryLoader.homeURL]) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                        }
                        .buttonStyle(WinIconButtonStyle())
                        .help("Share")
                        .accessibilityLabel("Share")
                    }

                    commandIcon("trash", help: "Delete (⌫)") {
                        Task { await FileOps.deleteItems(selection, app: app) }
                    }
                    .disabled(!hasSelection)

                    barDivider(p)

                    WinMenuButton(width: 218, enabled: true, entries: sortMenu) {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 13.5))
                    }
                    .buttonStyle(WinIconButtonStyle())
                    .help("Sort")
                    .accessibilityLabel("Sort")

                    WinMenuButton(width: 252, enabled: true, entries: viewMenu) {
                        Image(systemName: "square.grid.2x2").font(.system(size: 13.5))
                    }
                    .buttonStyle(WinIconButtonStyle())
                    .help("View")
                    .accessibilityLabel("View")

                    WinMenuButton(width: 216, enabled: true, entries: filterMenu) {
                        Image(systemName: "line.3.horizontal.decrease").font(.system(size: 13.5))
                    }
                    .buttonStyle(WinIconButtonStyle())
                    .help("Filter")
                    .accessibilityLabel("Filter")

                    barDivider(p)

                    WinMenuButton(width: 240, enabled: true, entries: moreMenu) {
                        Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(WinIconButtonStyle())
                    .help("See more options")
                    .accessibilityLabel("See more options")
                }
                .padding(.horizontal, 10)
                .frame(height: Win11.Metrics.commandBarHeight)
            }

            Spacer(minLength: 4)

            commandIcon("gearshape", help: "Options (⌘,)") { openOptions() }
                .padding(.trailing, 10)
        }
        .frame(height: Win11.Metrics.commandBarHeight)
        .background {
            OptionsOpenerBridge { optionsOpener = $0 }
        }
    }

    /// Opens the SwiftUI Settings scene ("Options"). macOS 14+ goes through the native
    /// `openSettings` action; macOS 13 falls back to the AppKit Preferences action.
    private func openOptions() {
        if let optionsOpener {
            optionsOpener()
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    // MARK: pieces

    private func barDivider(_ p: Win11.Palette) -> some View {
        Rectangle()
            .fill(p.divider)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 5)
    }

    private func commandIcon(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14))
        }
        .buttonStyle(WinIconButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private var newMenu: [WinMenuEntry] {
        [
            .row(.init(label: "New folder", icon: "folder.badge.plus", shortcut: "⇧⌘N") {
                if let dir = tab.currentFolderURL {
                    Task { await FileOps.newFolder(in: dir, app: app, tab: tab) }
                }
            }),
            .row(.init(label: "New text document", icon: "doc.badge.plus") {
                if let dir = tab.currentFolderURL {
                    Task { await FileOps.newTextDocument(in: dir, app: app, tab: tab) }
                }
            }),
        ]
    }

    private var sortMenu: [WinMenuEntry] {
        var items: [WinMenuEntry] = SortKey.allCases.map { key in
            .row(.init(label: key.title, checked: tab.sortKey == key) {
                tab.toggleSort(key)
            })
        }
        items.append(.separator())
        items.append(.row(.init(label: "Ascending", icon: "arrow.up", checked: tab.sortAscending) {
            tab.sortAscending = true
            app.rememberFolder(tab.location) { $0.ascending = true }
        }))
        items.append(.row(.init(label: "Descending", icon: "arrow.down", checked: !tab.sortAscending) {
            tab.sortAscending = false
            app.rememberFolder(tab.location) { $0.ascending = false }
        }))
        return items
    }

    private var viewMenu: [WinMenuEntry] {
        var items: [WinMenuEntry] = [
            .header("Layout"),
            .row(.init(label: "Large icons", icon: "square.grid.3x3", checked: tab.viewMode == .iconsLarge) { tab.setViewMode(.iconsLarge) }),
            .row(.init(label: "Medium icons", icon: "square.grid.2x2", checked: tab.viewMode == .iconsMedium) { tab.setViewMode(.iconsMedium) }),
            .row(.init(label: "Small icons", icon: "square.grid.3x3.fill", checked: tab.viewMode == .iconsSmall) { tab.setViewMode(.iconsSmall) }),
            .row(.init(label: "List", icon: "list.bullet", checked: tab.viewMode == .list) { tab.setViewMode(.list) }),
            .row(.init(label: "Details", icon: "text.justify", checked: tab.viewMode == .details) { tab.setViewMode(.details) }),
            .row(.init(label: "Tiles", icon: "rectangle.grid.1x2", checked: tab.viewMode == .tiles) { tab.setViewMode(.tiles) }),
        ]
        items.append(.separator())
        items.append(.row(.init(label: "Show", children: [
            .row(.init(label: "Hidden items", checked: app.prefs.showHidden) {
                app.prefs.showHidden.toggle()
                app.reloadAllTabs()
            }),
            .row(.init(label: "File name extensions", checked: app.prefs.showExtensions) {
                app.prefs.showExtensions.toggle()
            }),
        ])))
        return items
    }

    private var filterMenu: [WinMenuEntry] {
        var items: [WinMenuEntry] = FileCategory.allCases.map { cat in
            .row(.init(label: cat.title, checked: tab.filters.contains(cat)) {
                if tab.filters.contains(cat) { tab.filters.remove(cat) } else { tab.filters.insert(cat) }
            })
        }
        items.append(.separator())
        items.append(.row(.init(label: "Clear filters", icon: "xmark.circle") {
            tab.filters = []
        }))
        return items
    }

    private var moreMenu: [WinMenuEntry] {
        [
            .row(.init(label: "Undo", icon: "arrow.uturn.backward", shortcut: "⌘Z", disabled: !app.canUndo) {
                app.undo()
            }),
            .row(.init(label: "Redo", icon: "arrow.uturn.forward", shortcut: "⇧⌘Z", disabled: !app.canRedo) {
                app.redo()
            }),
            .separator(),
            .row(.init(label: "Refresh", icon: "arrow.clockwise", shortcut: "F5") {
                tab.reload()
            }),
            .row(.init(label: "Select all", icon: "checkmark.circle", shortcut: "⌘A") {
                tab.selectAll()
            }),
            .separator(),
            .row(.init(label: "Details pane", icon: "sidebar.trailing", checked: app.prefs.showDetailsPane) {
                app.prefs.showDetailsPane.toggle()
            }),
            .row(.init(label: "Properties", icon: "info.circle", shortcut: "⌘I", disabled: propertiesTarget == nil) {
                if let target = propertiesTarget { app.activeSheet = .properties(target) }
            }),
            .row(.init(label: "Options", icon: "gearshape", shortcut: "⌘,") {
                openOptions()
            }),
        ]
    }

    private var propertiesTarget: URL? {
        if let first = selection.first { return first.url }
        return tab.currentFolderURL
    }
}

// MARK: - Options opener bridge

/// Captures SwiftUI's native `openSettings` action (macOS 14+) so the command bar can
/// invoke it from plain closures (the gear button and the "..." → Options row). On
/// macOS 13 the bridge is inert and the call site falls back to the AppKit action.
private struct OptionsOpenerBridge: View {
    let onReady: (@escaping () -> Void) -> Void

    var body: some View {
        if #available(macOS 14.0, *) {
            ModernOpenSettings(onReady: onReady)
        }
    }
}

@available(macOS 14.0, *)
private struct ModernOpenSettings: View {
    let onReady: (@escaping () -> Void) -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.onAppear { onReady({ openSettings() }) }
    }
}
