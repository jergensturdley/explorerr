import Foundation

/// UserDefaults-backed persistence. Keys are centralized here.
enum Store {
    private static let d = UserDefaults.standard

    private static func set<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { d.set(data, forKey: key) }
    }

    private static func get<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: keys

    private enum K {
        static let prefs = "explorerr.prefs"
        static let pins = "explorerr.quickAccessPins"
        static let folderPrefs = "explorerr.folderPrefs"
        static let recents = "explorerr.recents"
        static let sessionTabs = "explorerr.session.tabs"
        static let sessionActive = "explorerr.session.active"
        static let navExpanded = "explorerr.navExpanded"
        static let navWidth = "explorerr.navWidth"
        static let trashOrigins = "explorerr.trashOrigins"
    }

    // MARK: accessors

    static func loadPrefs() -> Prefs { get(Prefs.self, forKey: K.prefs) ?? Prefs() }
    static func savePrefs(_ p: Prefs) { set(p, forKey: K.prefs) }

    static func loadPins() -> [String] { get([String].self, forKey: K.pins) ?? [] }
    static func savePins(_ p: [String]) { set(p, forKey: K.pins) }

    static func loadFolderPrefs() -> [String: FolderPrefs] { get([String: FolderPrefs].self, forKey: K.folderPrefs) ?? [:] }
    static func saveFolderPrefs(_ p: [String: FolderPrefs]) { set(p, forKey: K.folderPrefs) }

    static func loadRecents() -> [RecentItem] { get([RecentItem].self, forKey: K.recents) ?? [] }
    static func saveRecents(_ r: [RecentItem]) { set(r, forKey: K.recents) }

    static func saveSessionLayout(_ layout: SessionLayout) {
        set(layout, forKey: K.sessionTabs)
    }

    /// Loads the saved multi-pane layout; migrates the legacy single-pane format.
    static func loadSessionLayout() -> SessionLayout? {
        if let layout = get(SessionLayout.self, forKey: K.sessionTabs), !layout.panes.isEmpty {
            return layout
        }
        if let legacy = get([Location].self, forKey: K.sessionTabs), !legacy.isEmpty {
            let active = d.integer(forKey: K.sessionActive)
            return SessionLayout(
                panes: [PaneLayout(locations: legacy, activeTab: min(active, legacy.count - 1))],
                activePane: 0,
                weights: nil
            )
        }
        return nil
    }

    static func loadNavExpanded() -> Set<String> { Set(get([String].self, forKey: K.navExpanded) ?? []) }
    static func saveNavExpanded(_ s: Set<String>) { set(Array(s), forKey: K.navExpanded) }

    static func loadNavWidth() -> CGFloat { CGFloat(d.double(forKey: K.navWidth)) }

    static func loadTrashOrigins() -> [String: String] { get([String: String].self, forKey: K.trashOrigins) ?? [:] }
    static func saveTrashOrigins(_ m: [String: String]) { set(m, forKey: K.trashOrigins) }
}
