import SwiftUI
import AppKit

/// One explorer tab: location, listing, selection, sorting, search, history.
@MainActor
final class TabState: ObservableObject, Identifiable {
    let id = UUID()
    let app: AppModel

    @Published var location: Location = .home
    @Published var items: [FSItem] = []
    @Published var loading = false
    @Published var loadError: String?

    @Published var selection: Set<String> = []
    var anchorIndex: Int? = nil
    /// Keyboard focus row for ⇧-arrow range extension (Explorer-style).
    var focusIndex: Int? = nil
    /// True while a rubber-band drag is updating the selection (suppresses auto-scroll).
    var isBandSelecting = false

    @Published var sortKey: SortKey = .name
    @Published var sortAscending = true
    @Published var viewMode: ViewMode = .details

    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    @Published var isSearching = false
    @Published var searchRoot: Location? = nil
    @Published var filters: Set<FileCategory> = []

    @Published var renamingID: String? = nil
    var pendingRenameID: String? = nil
    var pendingRevealID: String? = nil

    @Published var historyBack: [Location] = []
    @Published var historyForward: [Location] = []

    @Published var columnWidths: [String: CGFloat] = ["name": 300, "modified": 150, "type": 150, "size": 96]

    private var loadTask: Task<Void, Never>?
    private var searchDebounce: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(app: AppModel, location: Location = .home) {
        self.app = app
        navigate(location, addHistory: false)
    }

    var title: String {
        if isSearching, searchRoot != nil { return "\(location.title)—\"\(searchText)\"" }
        return location.title
    }

    var currentFolderURL: URL? {
        if case .folder(let u) = location { return u }
        return nil
    }

    // MARK: - Navigation

    func navigate(_ to: Location, addHistory: Bool = true) {
        guard to != location || addHistory == false else {
            reload()
            return
        }
        if addHistory {
            if location != to || historyBack.last != location {
                if location != to { historyBack.append(location) }
            }
            historyForward.removeAll()
        }
        location = to
        selection = []
        anchorIndex = nil
        focusIndex = nil
        renamingID = nil
        loadTask?.cancel()
        searchTask?.cancel()
        isSearching = false
        searchRoot = nil
        applyFolderPrefs()
        load()
        app.tabsChanged()
        NotificationCenter.default.post(name: .explorerrNavigated, object: self)
    }

    func reload() {
        loadTask?.cancel()
        if isSearching {
            rerunSearch()
        } else {
            load()
        }
    }

    /// Go back `steps` history entries (address-bar history menu can jump several at once).
    func goBack(steps: Int = 1) {
        var dest: Location? = nil
        for _ in 0..<max(1, steps) {
            guard let prev = historyBack.popLast() else { break }
            historyForward.append(dest ?? location)
            dest = prev
        }
        if let dest { navigateInternal(dest) }
    }

    func goForward(steps: Int = 1) {
        var dest: Location? = nil
        for _ in 0..<max(1, steps) {
            guard let next = historyForward.popLast() else { break }
            historyBack.append(dest ?? location)
            dest = next
        }
        if let dest { navigateInternal(dest) }
    }

    func goUp() {
        guard let folder = currentFolderURL else { return }
        let parent = folder.deletingLastPathComponent()
        if folder.path == "/" { navigate(.thisPC) } 
        else { navigate(.folder(parent)) }
    }

    private func navigateInternal(_ to: Location) {
        location = to
        selection = []
        renamingID = nil
        loadTask?.cancel()
        searchTask?.cancel()
        isSearching = false
        searchRoot = nil
        applyFolderPrefs()
        load()
        app.tabsChanged()
        NotificationCenter.default.post(name: .explorerrNavigated, object: self)
    }


    private func applyFolderPrefs() {
        let fp = app.folderPrefsFor(location)
        viewMode = fp.view ?? .details
        sortKey = fp.sort ?? .name
        sortAscending = fp.ascending ?? true
    }

    private func load() {
        let target: URL?
        switch location {
        case .folder(let u): target = u
        case .trash: target = DirectoryLoader.trashURL
        default: target = nil
        }
        guard let folder = target else {
            items = []
            loadError = nil
            loading = false
            return
        }
        loading = true
        loadError = nil
        let includeHidden = app.prefs.showHidden
        loadTask = Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) {
                try? DirectoryLoader.contents(of: folder, includeHidden: includeHidden)
            }.value
            guard !Task.isCancelled else { return }
            if let result {
                self.items = result
                self.loading = false
                self.loadError = nil
                self.consumePending()
            } else {
                self.items = []
                self.loading = false
                self.loadError = "You don't have permission to access this folder, or it no longer exists."
            }
        }
    }

    private func consumePending() {
        if let reveal = pendingRevealID {
            selection = [reveal]
            pendingRevealID = nil
        }
        if let rename = pendingRenameID {
            renamingID = rename
            pendingRenameID = nil
        }
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchDebounce?.cancel()
        let text = searchText
        let root = location
        let recursive = app.prefs.searchAllSubfolders
        if text.isEmpty {
            searchTask?.cancel()
            if isSearching {
                isSearching = false
                searchRoot = nil
                load()
            }
            return
        }
        searchDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard let self, !Task.isCancelled else { return }
            self.runSearch(text: text, root: root, recursive: recursive)
        }
    }

    func beginSearch(_ text: String = "") {
        if !text.isEmpty { searchText = text }
    }

    private func rerunSearch() {
        let text = searchText
        let root = location
        let recursive = app.prefs.searchAllSubfolders
        if !text.isEmpty { runSearch(text: text, root: root, recursive: recursive) }
    }

    private func runSearch(text: String, root: Location, recursive: Bool) {
        guard let folder = root.folderURL ?? (root == .home ? DirectoryLoader.homeURL : nil) else {
            // Special pages: search falls back to the home directory
            runSearch(text: text, root: .folder(DirectoryLoader.homeURL), recursive: recursive)
            return
        }
        isSearching = true
        searchRoot = root
        loading = true
        selection = []
        searchTask?.cancel()
        let includeHidden = app.prefs.showHidden
        searchTask = Task { [weak self] in
            guard let self else { return }
            if recursive {
                let results = await Task.detached(priority: .userInitiated) {
                    DirectoryLoader.search(root: folder, query: text, includeHidden: includeHidden)
                }.value
                guard !Task.isCancelled else { return }
                self.items = results
                self.loading = false
            } else {
                let results = await Task.detached(priority: .userInitiated) {
                    (try? DirectoryLoader.contents(of: folder, includeHidden: includeHidden))?
                        .filter { $0.fileName.lowercased().contains(text.lowercased()) } ?? []
                }.value
                guard !Task.isCancelled else { return }
                self.items = results
                self.loading = false
            }
        }
    }

    func clearSearch() {
        searchText = ""
        searchTask?.cancel()
        isSearching = false
        searchRoot = nil
        load()
    }

    // MARK: - Displayed items

    var displayedItems: [FSItem] {
        var list = items
        if !filters.isEmpty {
            list = list.filter { filters.contains($0.category) }
        }
        return list
    }

    var sortedItems: [FSItem] {
        let ascending = sortAscending
        let foldersFirst = app.prefs.foldersFirst
        let list = displayedItems
        return list.sorted { a, b in
            if foldersFirst && a.isDirectory != b.isDirectory { return a.isDirectory }
            let result = compare(a, b)
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private func compare(_ a: FSItem, _ b: FSItem) -> ComparisonResult {
        switch sortKey {
        case .name:
            return a.displayName.localizedStandardCompare(b.displayName)
        case .modified:
            switch (a.modified ?? .distantPast, b.modified ?? .distantPast) {
            case let (x, y) where x == y: return .orderedSame
            case let (x, y): return x < y ? .orderedAscending : .orderedDescending
            }
        case .type:
            if a.kind != b.kind { return a.kind.localizedStandardCompare(b.kind) }
            return a.displayName.localizedStandardCompare(b.displayName)
        case .size:
            let x = a.sizeBytes ?? -1, y = b.sizeBytes ?? -1
            if x == y { return a.displayName.localizedStandardCompare(b.displayName) }
            return x < y ? .orderedAscending : .orderedDescending
        }
    }

    var selectedItems: [FSItem] {
        sortedItems.filter { selection.contains($0.id) }
    }

    var statusSummary: String {
        if isSearching { return "\(sortedItems.count) item\(sortedItems.count == 1 ? "" : "s") found" }
        var s = "\(sortedItems.count) item\(sortedItems.count == 1 ? "" : "s")"
        if selection.count > 0 {
            s += "  |  \(selection.count) selected"
            let bytes = selectedItems.compactMap { $0.sizeBytes }.reduce(0, +)
            if bytes > 0 { s += " \(Fmt.size(bytes))" }
        }
        return s
    }

    // MARK: - Selection

    func clickSelect(index: Int, item: FSItem, shift: Bool = false, command: Bool = false) {
        if shift, let anchor = anchorIndex {
            let range = min(anchor, index)...max(anchor, index)
            let ids = sortedItems.enumerated().filter { range.contains($0.offset) }.map { $0.element.id }
            selection = Set(ids)
        } else if command {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            anchorIndex = index
        } else {
            selection = [item.id]
            anchorIndex = index
        }
        if !shift { anchorIndex = index }
        focusIndex = index
        renamingID = nil
    }

    /// ⇧+arrow: grow/shrink the selection from the anchor toward `delta`.
    func extendSelection(delta: Int) {
        let items = sortedItems
        guard !items.isEmpty else { return }
        let anchor = anchorIndex ?? focusIndex ?? 0
        let next = max(0, min(items.count - 1, (focusIndex ?? anchor) + delta))
        anchorIndex = anchor
        focusIndex = next
        let range = min(anchor, next)...max(anchor, next)
        selection = Set(items[range].map { $0.id })
    }

    func selectAll() { selection = Set(sortedItems.map { $0.id }) }

    /// Dolphin/Explorer "Invert selection".
    func invertSelection() {
        selection = Set(sortedItems.map { $0.id }).subtracting(selection)
        anchorIndex = nil
    }

    func clearSelection() {
        selection = []
        anchorIndex = nil
        focusIndex = nil
    }

    func toggleSort(_ key: SortKey) {
        if sortKey == key { sortAscending.toggle() } else { sortKey = key; sortAscending = true }
        app.rememberFolder(location) { $0.sort = sortKey; $0.ascending = sortAscending }
    }

    func setViewMode(_ mode: ViewMode) {
        viewMode = mode
        app.rememberFolder(location) { $0.view = mode }
    }

    func zoomIn() { setViewMode(viewMode.zoomedIn) }
    func zoomOut() { setViewMode(viewMode.zoomedOut) }
}

// MARK: - TabController (one window)

@MainActor
final class TabController: ObservableObject {
    @Published var tabs: [TabState]
    @Published var activeID: UUID
    let app: AppModel
    /// Locations of recently closed tabs (⌘⇧T reopens, browser-style).
    private var recentlyClosed: [Location] = []

    convenience init(app: AppModel, location: Location) {
        self.init(app: app, locations: [location], activeIndex: 0)
    }

    init(app: AppModel, locations: [Location], activeIndex: Int = 0) {
        self.app = app
        let created = locations.map { TabState(app: app, location: $0) }
        tabs = created
        activeID = created[min(max(0, activeIndex), created.count - 1)].id
        app.tabsChanged()
    }

    var active: TabState { tabs.first { $0.id == activeID } ?? tabs[0] }

    func addTab(_ location: Location? = nil, activate: Bool = true) {
        let tab = TabState(app: app, location: location ?? .home)
        tabs.append(tab)
        if activate { activeID = tab.id }
        app.tabsChanged()
    }

    func closeTab(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        rememberClosed(tabs[idx].location)
        tabs.remove(at: idx)
        if tabs.isEmpty {
            tabs = [TabState(app: app, location: .home)]
        }
        if activeID == id {
            activeID = tabs[min(idx, tabs.count - 1)].id
        }
        app.tabsChanged()
    }

    func closeOthers(_ id: UUID) {
        guard let keep = tabs.first(where: { $0.id == id }) else { return }
        for tab in tabs where tab.id != id { rememberClosed(tab.location) }
        tabs = [keep]
        activeID = keep.id
        app.tabsChanged()
    }

    func closeRight(of id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }), idx < tabs.count - 1 else { return }
        for tab in tabs[(idx + 1)...] { rememberClosed(tab.location) }
        tabs.removeSubrange((idx + 1)...)
        if !tabs.contains(where: { $0.id == activeID }) { activeID = tabs[idx].id }
        app.tabsChanged()
    }

    private func rememberClosed(_ location: Location) {
        recentlyClosed.append(location)
        if recentlyClosed.count > 10 { recentlyClosed.removeFirst() }
    }

    func reopenClosedTab() {
        guard let loc = recentlyClosed.popLast() else { return }
        addTab(loc)
    }

    /// Drag-reorder: drop tab `id` onto `targetID` (after it when dragging right, before when left).
    func moveTab(_ id: UUID, onto targetID: UUID) {
        guard id != targetID,
              let from = tabs.firstIndex(where: { $0.id == id }),
              let to = tabs.firstIndex(where: { $0.id == targetID }) else { return }
        let moving = tabs.remove(at: from)
        tabs.insert(moving, at: to)
        app.tabsChanged()
    }

    func duplicateTab(_ id: UUID) {
        guard let src = tabs.first(where: { $0.id == id }) else { return }
        let tab = TabState(app: app, location: src.location)
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs.insert(tab, at: idx + 1)
        } else {
            tabs.append(tab)
        }
        activeID = tab.id
        app.tabsChanged()
    }

    func activate(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
        app.tabsChanged()
    }

    /// Ctrl+Tab-style cycling.
    func activateAdjacent(_ advance: Int) {
        guard tabs.count > 1, let idx = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        activeID = tabs[(idx + advance + tabs.count) % tabs.count].id
        app.tabsChanged()
    }
}
