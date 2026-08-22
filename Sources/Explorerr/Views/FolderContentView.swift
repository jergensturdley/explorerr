import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Content router for one tab + shared item interaction logic.
struct FolderContentView: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme

    @State private var dropHover = false

    var body: some View {
        let p = Win11.palette(theme.scheme)
        ZStack {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(dropHover ? p.selectionBG.opacity(0.6) : Color.clear)

            VStack(spacing: 0) {
                if tab.isSearching && !tab.searchText.isEmpty {
                    searchBanner(p)
                }

                if let err = tab.loadError {
                    errorView(p, err)
                } else if tab.loading && tab.items.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.regular)
                        Text("Working on it…").font(Win11.Fonts.bodySecondary).foregroundStyle(p.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tab.sortedItems.isEmpty {
                    emptyState(p)
                } else {
                    contentBody
                }
            }
        }
        .contentShape(Rectangle())
        .background(
            // Visible content region in window space (clips middle-click hit-testing).
            GeometryReader { g -> Color in
                let frame = g.frame(in: .named("win"))
                if tab.contentClipInWin != frame {
                    DispatchQueue.main.async { tab.contentClipInWin = frame }
                }
                return Color.clear
            }
        )
        // Double-click on empty space goes up one folder (Dolphin); handled by the
        // window's mouse monitor via BandSelect.isEmptySpace, NOT a count:2 recognizer
        // here: a parent recognizer also fires over items (they detect double-clicks
        // manually), which made every double-click navigate up.
        .onTapGesture { tab.clearSelection() }
        .contextMenu { emptyAreaContextMenu }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropHover) { providers in
            guard let dest = tab.currentFolderURL else { return false }
            return handleDrop(providers, into: dest)
        }
    }

    // MARK: content per mode

    @ViewBuilder
    private var contentBody: some View {
        switch tab.viewMode {
        case .details: DetailsView(tab: tab, app: app)
        case .list: ListView(tab: tab, app: app)
        case .iconsSmall, .iconsMedium, .iconsLarge: IconsGridView(tab: tab, app: app)
        case .tiles: TilesView(tab: tab, app: app)
        }
    }

    // MARK: banner / states

    private func searchBanner(_ p: Win11.Palette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(p.textSecondary)
            Text("Search results for “\(tab.searchText)”")
                .font(Win11.Fonts.body)
                .foregroundStyle(p.textPrimary)
            if let root = tab.searchRoot {
                Text("in \(root.title)")
                    .font(Win11.Fonts.bodySecondary)
                    .foregroundStyle(p.textSecondary)
            }
            Spacer()
            Button {
                tab.clearSearch()
            } label: {
                Text("Clear")
                    .font(Win11.Fonts.bodySecondary)
            }
            .buttonStyle(WinIconButtonStyle(padding: 5))
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(p.selectionBG.opacity(0.45))
        .overlay(alignment: .bottom) { Rectangle().fill(p.divider).frame(height: 1) }
    }

    private func emptyState(_ p: Win11.Palette) -> some View {
        VStack(spacing: 14) {
            if tab.isSearching {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(p.textSecondary.opacity(0.7))
                Text("No items match your search.")
                    .font(Win11.Fonts.body)
                    .foregroundStyle(p.textSecondary)
            } else {
                FolderIconView(variant: FolderVariant.forFolderURL(tab.currentFolderURL ?? DirectoryLoader.homeURL), size: 72)
                    .opacity(0.75)
                Text("This folder is empty.")
                    .font(Win11.Fonts.body)
                    .foregroundStyle(p.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ p: Win11.Palette, _ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(p.caution)
            Text(message)
                .font(Win11.Fonts.body)
                .foregroundStyle(p.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button("Try again") { tab.reload() }
                .buttonStyle(WinStandardButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: drop

    func handleDrop(_ providers: [NSItemProvider], into dest: URL) -> Bool {
        let tab = self.tab
        let app = self.app
        Task {
            let urls = await Self.loadURLs(from: providers)
            guard !urls.isEmpty else { return }
            let internalDrag = urls.contains { app.draggingURLs.contains($0.path) }
            await FileOps.transfer(urls, to: dest, move: internalDrag, app: app, tab: tab)
            app.draggingURLs = []
        }
        return true
    }

    static func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let url: URL? = await withCheckedContinuation { cont in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    if let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        cont.resume(returning: url)
                    } else if let url = data as? URL {
                        cont.resume(returning: url)
                    } else {
                        cont.resume(returning: nil)
                    }
                }
            }
            if let url { urls.append(url) }
        }
        return urls
    }

    // MARK: context menus

    @ViewBuilder
    private var emptyAreaContextMenu: some View {
        if tab.currentFolderURL != nil {
            Button("New folder") { Task { await FileOps.newFolder(in: tab.currentFolderURL!, app: app, tab: tab) } }
            Button("New text document") { Task { await FileOps.newTextDocument(in: tab.currentFolderURL!, app: app, tab: tab) } }
            Divider()
            Button("Paste") {
                if let dest = tab.currentFolderURL {
                    Task { await FileOps.paste(into: dest, app: app, tab: tab) }
                }
            }
            .disabled(app.clipboardURLs() == nil)
            Divider()
            Menu("Sort by") {
                ForEach(SortKey.allCases, id: \.self) { key in
                    Button("\(tab.sortKey == key ? "✓ " : "")\(key.title)") { tab.toggleSort(key) }
                }
            }
            Menu("View") {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Button("\(tab.viewMode == mode ? "✓ " : "")\(mode.title)") { tab.setViewMode(mode) }
                }
            }
            Divider()
            Button("Refresh") { tab.reload() }
            Button("Open in Terminal") { Self.openInTerminal(tab.currentFolderURL!) }
            Divider()
            Button("Properties") { app.activeSheet = .properties(tab.currentFolderURL!) }
        } else if tab.location == .trash {
            Button("Empty Recycle Bin") { app.activeSheet = .emptyTrash }
            Button("Refresh") { tab.reload() }
        } else {
            Button("Refresh") { tab.reload() }
        }
    }

    static func openInTerminal(_ url: URL) {
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

// MARK: - Shared item interaction modifier

struct ItemInteractions: ViewModifier {
    let item: FSItem
    let index: Int
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @State private var dropTargeted = false
    @State private var lastClickAt = Date.distantPast

    @ViewBuilder
    func body(content: Content) -> some View {
        let base = content
            .contentShape(Rectangle())
            // One immediate tap recognizer with manual double-click detection: the first
            // click selects instantly (no double-tap-failure delay), the second click
            // within the system interval opens. Modifiers are read live from NSEvent.
            .onTapGesture {
                let mods = NSEvent.modifierFlags
                let now = Date()
                let isDouble = now.timeIntervalSince(lastClickAt) < NSEvent.doubleClickInterval
                lastClickAt = now
                if mods.contains(.shift) {
                    tab.clickSelect(index: index, item: item, shift: true)
                } else if mods.contains(.command) {
                    tab.clickSelect(index: index, item: item, command: true)
                } else if isDouble {
                    lastClickAt = .distantPast // a triple click shouldn't re-open
                    if mods.contains(.option) {
                        // Windows Alt+double-click → Properties
                        app.activeSheet = .properties(item.url)
                    } else if item.isDirectory {
                        tab.navigate(.folder(item.url))
                    } else {
                        FileOps.open(item.url, app: app)
                    }
                } else {
                    tab.clickSelect(index: index, item: item)
                }
            }
            .contextMenu { itemContextMenu }
            .onDrag {
                app.draggingURLs = Set(tab.selectedItems.contains(where: { $0.id == item.id }) ? tab.selectedItems.map { $0.url.path } : [item.url.path])
                return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
            }

        if item.isDirectory {
            // Folders are drop targets: drop straight into a subfolder without entering it.
            base
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(dropTargeted ? dropAccent : Color.clear, lineWidth: 1.5)
                        .allowsHitTesting(false)
                )
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
                    let dest = item.url
                    Task {
                        let urls = await FolderContentView.loadURLs(from: providers)
                            .filter { $0.standardizedFileURL.path != dest.standardizedFileURL.path }
                        guard !urls.isEmpty else { return }
                        let internalDrag = urls.contains { app.draggingURLs.contains($0.path) }
                        await FileOps.transfer(urls, to: dest, move: internalDrag, app: app, tab: tab)
                        app.draggingURLs = []
                    }
                    return true
                }
        } else {
            base
        }
    }

    private var dropAccent: Color { Win11.palette(theme.scheme).selectionBorder }

    @ViewBuilder
    private var itemContextMenu: some View {
        let selection = tab.selectedItems.contains(where: { $0.id == item.id }) ? tab.selectedItems : [item]
        let allFolders = !selection.isEmpty && selection.allSatisfy(\.isDirectory)

        if item.isDirectory && selection.count == 1 {
            Button("Open") { tab.navigate(.folder(item.url)) }
            Button("Open in new tab") {
                NotificationCenter.default.post(name: .explorerrOpenInNewTab, object: Location.folder(item.url))
            }
            Divider()
        } else if !item.isDirectory {
            Button("Open") { FileOps.open(item.url, app: app) }
            Menu("Open With") {
                let candidates = OpenWith.candidates(for: item.url)
                if let defaultApp = candidates.defaultApp {
                    Button("\(defaultApp.name) (default)") {
                        OpenWith.open(item.url, with: defaultApp.url, app: app)
                    }
                }
                if !candidates.others.isEmpty { Divider() }
                ForEach(candidates.others) { candidate in
                    Button(candidate.name) {
                        OpenWith.open(item.url, with: candidate.url, app: app)
                    }
                }
                Divider()
                Button("Choose Application…") {
                    OpenWith.showPicker(for: item.url, app: app)
                }
            }
            Divider()
        }

        Button("Cut") { app.cutItems(selection) }
        Button("Copy") { app.copyItems(selection) }
        if item.isDirectory && selection.count == 1 {
            Button("Paste into") {
                Task { await FileOps.paste(into: item.url, app: app, tab: tab) }
            }
            .disabled(app.clipboardURLs() == nil)
        }
        Button("Copy as path") {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(selection.map { $0.url.path }.joined(separator: "\n"), forType: .string)
        }
        Button("Duplicate") { Task { await FileOps.duplicate(selection, app: app) } }

        Menu("Send to") {
            Button("Compressed (zipped) folder") {
                Task { await FileOps.compress(selection, app: app, tab: tab) }
            }
            Divider()
            Button("Desktop (copy)") {
                let dest = DirectoryLoader.homeURL.appendingPathComponent("Desktop", isDirectory: true)
                Task { await FileOps.transfer(selection.map { $0.url }, to: dest, move: false, app: app, tab: tab) }
            }
            Button("Documents (copy)") {
                let dest = DirectoryLoader.homeURL.appendingPathComponent("Documents", isDirectory: true)
                Task { await FileOps.transfer(selection.map { $0.url }, to: dest, move: false, app: app, tab: tab) }
            }
            Button("Downloads (copy)") {
                let dest = DirectoryLoader.homeURL.appendingPathComponent("Downloads", isDirectory: true)
                Task { await FileOps.transfer(selection.map { $0.url }, to: dest, move: false, app: app, tab: tab) }
            }
        }

        Divider()

        if selection.count == 1 {
            Button("Rename") { tab.renamingID = item.id }
        }
        Button("Move to Recycle Bin") {
            Task { await FileOps.deleteItems(selection, app: app) }
        }
        if tab.location == .trash {
            Button("Delete permanently") {
                Task { await FileOps.deleteItems(selection, app: app, permanent: true) }
            }
        }
        Divider()

        if allFolders {
            if app.isPinned(item.url.standardizedFileURL.path) {
                Button("Unpin from Quick access") { app.togglePin(item.url) }
            } else {
                Button("Pin to Quick access") { app.togglePin(item.url) }
            }
        }
        if tab.isSearching && !item.isDirectory {
            Button("Open file location") {
                tab.pendingRevealID = item.id
                tab.navigate(.folder(item.url.deletingLastPathComponent()))
            }
        }
        if tab.location == .trash {
            Button("Restore") {
                Task {
                    let dest = FileOps.originalPath(for: item, app: app) ?? DirectoryLoader.homeURL
                    await FileOps.restore(selection.map { $0.url }, to: dest, app: app)
                }
            }
        }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(selection.map { $0.url }) }
        Divider()
        Button("Properties") { app.activeSheet = .properties(item.url) }
    }
}

// MARK: - Inline rename field (Enter commits, Esc cancels)

struct InlineRenameField: View {
    let initialName: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool
    @State private var monitor: Any?
    @State private var done = false

    init(initialName: String, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialName = initialName
        self.onCommit = onCommit
        self.onCancel = onCancel
        _text = State(initialValue: initialName)
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(Win11.Fonts.body)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color(red: 0, green: 103/255, blue: 192/255), lineWidth: 1.5)
            )
            .focused($focused)
            .onSubmit { commit() }
            .onAppear {
                focused = true
                DispatchQueue.main.async {
                    if let tv = NSApp.keyWindow?.firstResponder as? NSTextView {
                        let name = (text as NSString).deletingPathExtension
                        if let range = tv.string.range(of: name) {
                            let r = NSRange(range, in: tv.string)
                            if range.isEmpty { tv.selectAll(nil) }
                            else { tv.setSelectedRange(r) }
                        } else {
                            tv.selectAll(nil)
                        }
                    }
                }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 53 { // Escape
                        cancel()
                        return nil
                    }
                    return event
                }
            }
            .onDisappear {
                if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
                commit() // treat focus loss / teardown as commit
            }
            .onChange(of: focused) { f in
                if !f { commit() }
            }
    }

    private func commit() {
        guard !done else { return }
        done = true
        onCommit(text)
    }

    private func cancel() {
        guard !done else { return }
        done = true
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        onCancel()
    }
}
