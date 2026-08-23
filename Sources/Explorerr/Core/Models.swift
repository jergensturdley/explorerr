import Foundation
import AppKit

// MARK: - Location

enum Location: Hashable, Codable {
    case folder(URL)
    case home
    case gallery
    case thisPC
    case network
    case trash

    var folderURL: URL? { if case .folder(let u) = self { return u } else { return nil } }
    var isFolder: Bool { folderURL != nil }

    var title: String {
        switch self {
        case .folder(let u): return u.lastPathComponent.isEmpty ? "/" : u.lastPathComponent
        case .home: return "Home"
        case .gallery: return "Gallery"
        case .thisPC: return "This PC"
        case .network: return "Network"
        case .trash: return "Recycle Bin"
        }
    }

    /// Stable key for per-folder preference storage.
    var prefsKey: String {
        switch self {
        case .folder(let u): return "p:" + u.standardizedFileURL.path
        case .home: return "l:home"
        case .gallery: return "l:gallery"
        case .thisPC: return "l:thisPC"
        case .network: return "l:network"
        case .trash: return "l:trash"
        }
    }

    private enum CodingKeys: String, CodingKey { case v }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let v = try c.decode(String.self, forKey: .v)
        if v == "home" { self = .home }
        else if v == "gallery" { self = .gallery }
        else if v == "thisPC" { self = .thisPC }
        else if v == "network" { self = .network }
        else if v == "trash" { self = .trash }
        else if v.hasPrefix("folder:") { self = .folder(URL(fileURLWithPath: String(v.dropFirst("folder:".count)))) }
        else { self = .home }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .home: try c.encode("home", forKey: .v)
        case .gallery: try c.encode("gallery", forKey: .v)
        case .thisPC: try c.encode("thisPC", forKey: .v)
        case .network: try c.encode("network", forKey: .v)
        case .trash: try c.encode("trash", forKey: .v)
        case .folder(let u): try c.encode("folder:" + u.path, forKey: .v)
        }
    }
}

// MARK: - View modes / sorting

enum ViewMode: String, Codable, CaseIterable {
    case details, list, tiles, iconsSmall, iconsMedium, iconsLarge

    var title: String {
        switch self {
        case .details: return "Details"
        case .list: return "List"
        case .tiles: return "Tiles"
        case .iconsSmall: return "Small icons"
        case .iconsMedium: return "Medium icons"
        case .iconsLarge: return "Large icons"
        }
    }

    /// Icon point size for grid modes; nil for textual modes.
    var iconSize: CGFloat? {
        switch self {
        case .details, .list: return nil
        case .tiles: return 48
        case .iconsSmall: return 32
        case .iconsMedium: return 64
        case .iconsLarge: return 96
        }
    }

    var isGrid: Bool { iconSize != nil }

    /// Dolphin/Finder-style zoom ladder for view density.
    static let zoomLadder: [ViewMode] = [.details, .iconsSmall, .iconsMedium, .iconsLarge, .tiles]

    var zoomedIn: ViewMode {
        let idx = Self.zoomLadder.firstIndex(of: self) ?? 0
        return Self.zoomLadder[(idx + 1) % Self.zoomLadder.count]
    }

    var zoomedOut: ViewMode {
        let idx = Self.zoomLadder.firstIndex(of: self) ?? 0
        return Self.zoomLadder[(idx - 1 + Self.zoomLadder.count) % Self.zoomLadder.count]
    }
}

enum SortKey: String, Codable, CaseIterable {
    case name, modified, type, size

    var title: String {
        switch self {
        case .name: return "Name"
        case .modified: return "Date modified"
        case .type: return "Type"
        case .size: return "Size"
        }
    }
}

// MARK: - Folder / app preferences

struct FolderPrefs: Codable {
    var view: ViewMode?
    var sort: SortKey?
    var ascending: Bool?
    var hidden: Bool?
}

/// Forced appearance for the whole app (System follows macOS).
enum AppearanceMode: String, Codable, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

struct Prefs: Codable {
    var showHidden: Bool = false
    var showExtensions: Bool = true
    var foldersFirst: Bool = true
    var confirmDelete: Bool = false
    var searchAllSubfolders: Bool = true
    var startupHome: Bool = true
    var statusVisible: Bool = true
    var showDetailsPane: Bool = false
    /// Dolphin-style: navigating the view cd's the integrated terminal when the shell is idle.
    var syncTerminalCD: Bool = true
    /// Integrated terminal loads the user's shell startup files (off: clean minimal prompt).
    var terminalUsesProfile: Bool = false
    /// One-time: the Desktop/Documents/Downloads permission prompts were triggered at launch.
    var didPrimeFolderAccess: Bool = false
    /// Appearance override (Win11 theme is drawn from our palettes, so this is app-wide).
    var appearance: AppearanceMode = .system
    /// Denser Details/List rows (Explorer 11 "compact view").
    var compactRows: Bool = false
    /// Windows Folder Options classic: single click opens items, modifiers still select.
    var singleClickOpen: Bool = false
    /// New tabs open Home (the quick-access page) or the home folder (~).
    var newTabsOpenHome: Bool = true
    /// Dolphin nicety: double-clicking empty content space goes up one folder.
    var doubleClickEmptyGoesUp: Bool = true
    /// Track and show recent files on the Home page.
    var showRecents: Bool = true
    /// Sidebar sections.
    var sidebarGallery: Bool = true
    var sidebarCloud: Bool = true
    var sidebarNetwork: Bool = true
    var sidebarTrash: Bool = true

    init() {}

    // Tolerant decoding: adding a field must not reset every stored preference.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showHidden = try c.decodeIfPresent(Bool.self, forKey: .showHidden) ?? false
        showExtensions = try c.decodeIfPresent(Bool.self, forKey: .showExtensions) ?? true
        foldersFirst = try c.decodeIfPresent(Bool.self, forKey: .foldersFirst) ?? true
        confirmDelete = try c.decodeIfPresent(Bool.self, forKey: .confirmDelete) ?? false
        searchAllSubfolders = try c.decodeIfPresent(Bool.self, forKey: .searchAllSubfolders) ?? true
        startupHome = try c.decodeIfPresent(Bool.self, forKey: .startupHome) ?? true
        statusVisible = try c.decodeIfPresent(Bool.self, forKey: .statusVisible) ?? true
        showDetailsPane = try c.decodeIfPresent(Bool.self, forKey: .showDetailsPane) ?? false
        syncTerminalCD = try c.decodeIfPresent(Bool.self, forKey: .syncTerminalCD) ?? true
        terminalUsesProfile = try c.decodeIfPresent(Bool.self, forKey: .terminalUsesProfile) ?? false
        didPrimeFolderAccess = try c.decodeIfPresent(Bool.self, forKey: .didPrimeFolderAccess) ?? false
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system
        compactRows = try c.decodeIfPresent(Bool.self, forKey: .compactRows) ?? false
        singleClickOpen = try c.decodeIfPresent(Bool.self, forKey: .singleClickOpen) ?? false
        newTabsOpenHome = try c.decodeIfPresent(Bool.self, forKey: .newTabsOpenHome) ?? true
        doubleClickEmptyGoesUp = try c.decodeIfPresent(Bool.self, forKey: .doubleClickEmptyGoesUp) ?? true
        showRecents = try c.decodeIfPresent(Bool.self, forKey: .showRecents) ?? true
        sidebarGallery = try c.decodeIfPresent(Bool.self, forKey: .sidebarGallery) ?? true
        sidebarCloud = try c.decodeIfPresent(Bool.self, forKey: .sidebarCloud) ?? true
        sidebarNetwork = try c.decodeIfPresent(Bool.self, forKey: .sidebarNetwork) ?? true
        sidebarTrash = try c.decodeIfPresent(Bool.self, forKey: .sidebarTrash) ?? true
    }
}

struct RecentItem: Codable, Hashable {
    var path: String
    var name: String
    var date: Date
}

// MARK: - File categories (for filters / icon tinting)

enum FileCategory: String, CaseIterable, Identifiable {
    case folder, image, video, audio, document, archive, application, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .folder: return "Folders"
        case .image: return "Pictures"
        case .video: return "Videos"
        case .audio: return "Music"
        case .document: return "Documents"
        case .archive: return "Archives"
        case .application: return "Apps"
        case .other: return "Other"
        }
    }

    static func of(pathExtension: String?, isDirectory: Bool) -> FileCategory {
        if isDirectory { return .folder }
        switch (pathExtension ?? "").lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp", "webp", "svg", "ico", "avif", "raw", "cr2", "nef": return .image
        case "mp4", "mov", "avi", "mkv", "m4v", "wmv", "webm": return .video
        case "mp3", "wav", "aiff", "m4a", "flac", "aac", "ogg": return .audio
        case "txt", "md", "rtf", "pdf", "doc", "docx", "pages", "xls", "xlsx", "ppt", "pptx", "key", "numbers", "csv", "json", "xml", "plist", "log", "yaml", "yml": return .document
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso", "pkg": return .archive
        case "app", "exe", "deb", "apk", "jar": return .application
        default: return .other
        }
    }
}

// MARK: - FSItem

struct FSItem: Identifiable, Hashable {
    let url: URL
    let fileName: String          // real name on disk
    let isDirectory: Bool         // true dirs only (packages count as files)
    let isHidden: Bool
    let isSymbolicLink: Bool
    let sizeBytes: Int64?         // nil for folders
    let created: Date?
    let modified: Date?
    let kind: String
    let category: FileCategory

    var id: String { url.path }
    var displayName: String { fileName }

    init(url: URL, fileName: String, isDirectory: Bool, isHidden: Bool = false,
         isSymbolicLink: Bool = false, sizeBytes: Int64? = nil,
         created: Date? = nil, modified: Date? = nil, kind: String = "", category: FileCategory? = nil) {
        self.url = url
        self.fileName = fileName
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.isSymbolicLink = isSymbolicLink
        self.sizeBytes = sizeBytes
        self.created = created
        self.modified = modified
        self.kind = kind.isEmpty ? (isDirectory ? "File folder" : "File") : kind
        self.category = category ?? FileCategory.of(pathExtension: url.pathExtension, isDirectory: isDirectory)
    }

    /// Placeholder item the UI can create for virtual entries (Home cards etc.).
    static func virtual(_ url: URL, name: String, kind: String, isDirectory: Bool = true) -> FSItem {
        FSItem(url: url, fileName: name, isDirectory: isDirectory, kind: kind)
    }

    var nameWithoutExtension: String {
        isDirectory ? fileName : url.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Drive

struct DriveInfo: Identifiable, Hashable {
    let url: URL
    let name: String
    let totalBytes: Int64
    let freeBytes: Int64
    let isInternal: Bool
    let isNetwork: Bool
    let isRemovable: Bool
    let isBoot: Bool

    var id: String { url.path }
    var usedBytes: Int64 { max(0, totalBytes - freeBytes) }
    var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
    var isReadable: Bool { totalBytes > 0 }   // unreadable/unmounted have 0 capacity
}

// MARK: - Undo

enum UndoOperation {
    case renamed(from: URL, to: URL)
    case movedBack(from: URL, to: URL)        // inverse of a move: item at `to` moves back to `from`
    case trashed(urls: [URL])
    case created(urls: [URL])                 // inverse: trash these
    case pasted(urls: [URL])                  // inverse: trash these
    case customInverse(label: String, undo: @MainActor () -> Void)

    var title: String {
        switch self {
        case .renamed: return "Rename"
        case .movedBack: return "Move"
        case .trashed: return "Delete"
        case .created: return "New"
        case .pasted: return "Paste"
        case .customInverse(let label, _): return label
        }
    }
}

// MARK: - Formatters

enum Fmt {
    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    static func size(_ bytes: Int64?) -> String {
        guard let b = bytes else { return "" }
        return b.string
    }

    /// "3 folders; 12 files" style status / property strings.
    static func counts(folders: Int, files: Int) -> String {
        var parts: [String] = []
        if folders > 0 || files == 0 { parts.append("\(folders) folder\(folders == 1 ? "" : "s")") }
        if files > 0 { parts.append("\(files) file\(files == 1 ? "" : "s")") }
        return parts.joined(separator: "; ")
    }
}

extension Int64 {
    var string: String { Fmt.bytes.string(fromByteCount: self) }
}
