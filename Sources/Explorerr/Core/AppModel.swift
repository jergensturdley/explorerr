import SwiftUI
import AppKit

// MARK: - Menu system model (custom Win11-style dropdowns)

struct WinMenuEntry: Identifiable {
    let id = UUID()

    struct Row {
        var label: String
        var icon: String? = nil            // SF symbol name
        var shortcut: String? = nil        // right-aligned hint, e.g. "⇧⌘N"
        var checked: Bool = false
        var disabled: Bool = false
        var danger: Bool = false
        var children: [WinMenuEntry]? = nil
        var action: (() -> Void)? = nil
    }

    enum Kind {
        case row(Row)
        case separator
        case header(String)
    }

    let kind: Kind

    static func row(_ r: Row) -> WinMenuEntry { WinMenuEntry(kind: .row(r)) }
    static func separator() -> WinMenuEntry { WinMenuEntry(kind: .separator) }
    static func header(_ t: String) -> WinMenuEntry { WinMenuEntry(kind: .header(t)) }
}

struct MenuRequest: Identifiable, Equatable {
    let id = UUID()
    let anchor: CGRect        // frame in the window coordinate space named "win"
    let entries: [WinMenuEntry]
    let width: CGFloat

    static func == (lhs: MenuRequest, rhs: MenuRequest) -> Bool { lhs.id == rhs.id }
}

final class MenuCoordinator: ObservableObject {
    @Published var request: MenuRequest?
    var windowSize: CGSize = CGSize(width: 1100, height: 700)

    func toggle(anchor: CGRect, width: CGFloat = 232, entries: [WinMenuEntry]) {
        if let r = request, r.anchor == anchor, r.width == width {
            request = nil
        } else {
            request = MenuRequest(anchor: anchor, entries: entries, width: width)
        }
    }

    func show(anchor: CGRect, width: CGFloat = 232, entries: [WinMenuEntry]) {
        request = MenuRequest(anchor: anchor, entries: entries, width: width)
    }

    func dismiss() { request = nil }
}

// MARK: - Confirmation request

struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmLabel: String
    let cancelLabel: String
    let destructive: Bool
    let action: () -> Void

    init(title: String, message: String, confirmLabel: String = "Yes",
         cancelLabel: String = "Cancel", destructive: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
        self.destructive = destructive
        self.action = action
    }
}

// MARK: - Active sheet

enum ActiveSheet: Identifiable {
    case conflict(ConflictContext)
    case progress(TransferProgress)
    case properties(URL)
    case about
    case shortcuts
    case emptyTrash
    case restorePick([URL])

    var id: String {
        switch self {
        case .conflict(let c): return "conflict-\(c.id.uuidString)"
        case .progress: return "progress"
        case .properties(let u): return "props-\(u.path)"
        case .about: return "about"
        case .shortcuts: return "shortcuts"
        case .emptyTrash: return "emptyTrash"
        case .restorePick: return "restorePick"
        }
    }
}

// MARK: - AppModel (shared across all windows)

@MainActor
final class AppModel: ObservableObject {
    /// True once the first window has consumed the saved session.
    static var sessionRestoreDone = false

    @Published var prefs: Prefs {
        didSet { Store.savePrefs(prefs) }
    }
    @Published var pins: [String] {
        didSet { Store.savePins(pins) }
    }
    @Published var folderPrefs: [String: FolderPrefs] {
        didSet { Store.saveFolderPrefs(folderPrefs) }
    }
    @Published var recents: [RecentItem] {
        didSet { Store.saveRecents(recents) }
    }
    @Published var navExpanded: Set<String> {
        didSet { Store.saveNavExpanded(navExpanded) }
    }
    @Published var trashOrigins: [String: String] {
        didSet { Store.saveTrashOrigins(trashOrigins) }
    }
    /// The Shelf: file paths staged in limbo while browsing, later copied or moved
    /// into a destination. Shared across windows, persists across launches.
    @Published var shelf: [String] {
        didSet { Store.saveShelf(shelf) }
    }
    @Published var navWidth: CGFloat = Win11.Metrics.navPaneDefaultWidth {
        didSet { UserDefaults.standard.set(Double(navWidth), forKey: "explorerr.navWidth") }
    }

    @Published var cutURLs: Set<String> = []
    @Published var draggingURLs: Set<String> = []     // internal drag sources (move semantics)
    @Published var undoStack: [UndoOperation] = []
    @Published var redoStack: [UndoOperation] = []
    @Published var activeSheet: ActiveSheet?
    @Published var lastError: String?
    @Published var confirm: ConfirmRequest?
    @Published var statusMessage: String?             // transient toast in status bar

    let menuCoordinator = MenuCoordinator()

    /// Weak registry of live windows (for cross-refresh + session save).
    static let windowRegistry = NSHashTable<WindowModel>.weakObjects()

    // Conflict continuation plumbing
    var conflictResume: CheckedContinuation<ConflictChoice, Never>?
    var applyAllChoice: ConflictChoice?

    private var sessionTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init() {
        prefs = Store.loadPrefs()
        pins = Store.loadPins()
        folderPrefs = Store.loadFolderPrefs()
        recents = Store.loadRecents()
        navExpanded = Store.loadNavExpanded()
        trashOrigins = Store.loadTrashOrigins()
        shelf = Store.loadShelf()
        let w = Store.loadNavWidth()
        navWidth = (w == 0) ? Win11.Metrics.navPaneDefaultWidth : w
        if navExpanded.isEmpty { navExpanded = ["thisPC", "cloud"] }  // sensible defaults

        // First launch: fire the Desktop/Documents/Downloads permission prompts up front
        // so the file manager asks once instead of surprising the user mid-navigation.
        if !prefs.didPrimeFolderAccess {
            prefs.didPrimeFolderAccess = true
            DiskAccess.primeFolderPermissions()
        }
    }

    // MARK: quick access pins

    func isPinned(_ path: String) -> Bool { pins.contains(path) }

    func togglePin(_ url: URL) {
        let path = url.standardizedFileURL.path
        if let i = pins.firstIndex(of: path) { pins.remove(at: i) } else { pins.append(path) }
    }

    // MARK: per-folder view memory

    func folderPrefsFor(_ location: Location) -> FolderPrefs {
        folderPrefs[location.prefsKey] ?? FolderPrefs()
    }

    func rememberFolder(_ location: Location, update: (inout FolderPrefs) -> Void) {
        guard location.isFolder else { return }
        var fp = folderPrefs[location.prefsKey] ?? FolderPrefs()
        update(&fp)
        folderPrefs[location.prefsKey] = fp
    }

    // MARK: shelf

    /// Add files to the Shelf (deduped, keeps order, prunes vanished entries).
    func addToShelf(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var updated = shelf.filter { FileManager.default.fileExists(atPath: $0) }
        for url in urls {
            let path = url.standardizedFileURL.path
            if !updated.contains(path) { updated.append(path) }
        }
        shelf = updated
        toast("Shelved \(urls.count) item\(urls.count == 1 ? "" : "s")")
    }

    func removeFromShelf(_ path: String) {
        shelf.removeAll { $0 == path }
    }

    // MARK: recents

    func recordRecent(_ url: URL) {
        guard prefs.showRecents else { return }
        var r = recents.filter { $0.path != url.path }
        r.insert(RecentItem(path: url.path, name: url.lastPathComponent, date: Date()), at: 0)
        if r.count > 40 { r = Array(r.prefix(40)) }
        recents = r
    }

    // MARK: undo / redo

    func registerUndo(_ op: UndoOperation) {
        undoStack.append(op)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let op = undoStack.popLast() else { return }
        performInverse(op)
        redoStack.append(op)
    }

    func redo() {
        guard let op = redoStack.popLast() else { return }
        var reRegister: UndoOperation?
        switch op {
        case .renamed(let from, let to):
            // Redo: apply the rename again
            if FileManager.default.fileExists(atPath: to.path) == false,
               FileManager.default.fileExists(atPath: from.path),
               (try? FileManager.default.moveItem(at: from, to: to)) != nil {
                foldersChanged([from.deletingLastPathComponent()])
                reRegister = op
            } else {
                toast("Redo is not available for this operation")
            }
        case .customInverse(_, let undo):
            undo()
            reRegister = op
        default:
            toast("Redo is not available for this operation")
        }
        if let r = reRegister {
            undoStack.append(r)
        }
    }

    private func performInverse(_ op: UndoOperation) {
        let fm = FileManager.default
        switch op {
        case .renamed(let from, let to):
            if fm.fileExists(atPath: to.path) {
                try? fm.moveItem(at: to, to: from)
                foldersChanged([from.deletingLastPathComponent()])
            }
        case .movedBack(let from, let to):
            if fm.fileExists(atPath: to.path) {
                try? fm.moveItem(at: to, to: from)
                foldersChanged([from.deletingLastPathComponent(), to.deletingLastPathComponent()])
            }
        case .trashed(let urls):
            Task { await FileOps.restore(urls, to: DirectoryLoader.homeURL, app: self) }
        case .created(let urls), .pasted(let urls):
            NSWorkspace.shared.recycle(urls) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.foldersChanged(urls.map { $0.deletingLastPathComponent() })
                }
            }
        case .customInverse(_, let undo):
            undo()
        }
        toast("Undid \(op.title)")
    }

    func toast(_ message: String) {
        statusMessage = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if let self, !Task.isCancelled { self.statusMessage = nil }
        }
    }

    // MARK: session persistence

    func tabsChanged() {
        layoutChanged()
    }

    /// Called whenever pane layouts change so windows persist their sessions.
    func layoutChanged() {
        sessionTask?.cancel()
        sessionTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            for window in Self.windowRegistry.allObjects {
                window.saveSession()
            }
        }
    }

    /// Reload every tab in every window (used when global prefs change).
    func reloadAllTabs() {
        for window in Self.windowRegistry.allObjects {
            for pane in window.panes {
                for tab in pane.controller.tabs { tab.reload() }
            }
        }
    }

    /// Reload any tab currently displaying one of these folders.
    func foldersChanged(_ urls: [URL]) {
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        for window in Self.windowRegistry.allObjects {
            for pane in window.panes {
                for tab in pane.controller.tabs {
                    if let folder = tab.location.folderURL, paths.contains(folder.standardizedFileURL.path) {
                        tab.reload()
                    } else if tab.location == .trash {
                        tab.reload()
                    }
                }
            }
        }
    }

    // MARK: clipboard

    private static let cutMarker = NSPasteboard.PasteboardType("com.explorerr.cut")

    func copyItems(_ items: [FSItem]) {
        guard !items.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { $0.url as NSURL })
        cutURLs = []
        toast("Copied \(items.count) item\(items.count == 1 ? "" : "s")")
    }

    func cutItems(_ items: [FSItem]) {
        guard !items.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { $0.url as NSURL })
        pb.setData(Data("cut".utf8), forType: Self.cutMarker)
        cutURLs = Set(items.map { $0.url.path })
        toast("Cut \(items.count) item\(items.count == 1 ? "" : "s")")
    }

    func clipboardURLs() -> [URL]? {
        let pb = NSPasteboard.general
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL], !urls.isEmpty else { return nil }
        return urls
    }

    func isClipboardCut() -> Bool {
        NSPasteboard.general.data(forType: Self.cutMarker) != nil
    }

    func clearCutState() {
        cutURLs = []
        let pb = NSPasteboard.general
        pb.clearContents()
    }

    // MARK: conflicts (continuation-based question)

    func askConflict(sourceName: String, destName: String, remaining: Int) async -> ConflictChoice {
        applyAllChoice = nil
        return await withCheckedContinuation { cont in
            conflictResume = cont
            activeSheet = .conflict(ConflictContext(sourceName: sourceName, destName: destName, remaining: remaining))
        }
    }

    func resolveConflict(_ choice: ConflictChoice, applyAll: Bool) {
        if applyAll { applyAllChoice = choice }
        activeSheet = nil
        conflictResume?.resume(returning: choice)
        conflictResume = nil
    }

    func cancelConflict() {
        applyAllChoice = .skip
        activeSheet = nil
        conflictResume?.resume(returning: .skip)
        conflictResume = nil
    }
}
