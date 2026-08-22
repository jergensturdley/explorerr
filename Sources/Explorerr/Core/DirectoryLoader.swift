import Foundation
import AppKit

/// Filesystem enumeration. All functions do blocking IO — call from background tasks.
enum DirectoryLoader {
    static var homeURL: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var trashURL: URL { homeURL.appendingPathComponent(".Trash", isDirectory: true) }

    static func resolveHomeRelative(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .fileSizeKey, .isSymbolicLinkKey,
        .contentModificationDateKey, .creationDateKey, .localizedTypeDescriptionKey,
    ]

    private static func item(for url: URL) -> FSItem? {
        guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
        let isRealDir = values.isDirectory ?? false
        let isPackage = values.isPackage ?? false
        let isDir = isRealDir && !isPackage
        return FSItem(
            url: url,
            fileName: url.lastPathComponent,
            isDirectory: isDir,
            isHidden: values.isHidden ?? false,
            isSymbolicLink: values.isSymbolicLink ?? false,
            sizeBytes: isDir ? nil : Int64(values.fileSize ?? 0),
            created: values.creationDate,
            modified: values.contentModificationDate,
            kind: values.localizedTypeDescription ?? ""
        )
    }

    /// Directory contents (unsorted). Throws on unreadable folders.
    static func contents(of url: URL, includeHidden: Bool) throws -> [FSItem] {
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: url.path)
        var result: [FSItem] = []
        result.reserveCapacity(names.count)
        for name in names {
            if !includeHidden && name.hasPrefix(".") { continue }
            let child = url.appendingPathComponent(name, isDirectory: true)
            if let item = item(for: child) { result.append(item) }
        }
        return result
    }

    /// Immediate subfolders (navigation pane + breadcrumb dropdowns).
    static func childFolders(of url: URL, includeHidden: Bool) -> [FSItem] {
        guard let all = try? contents(of: url, includeHidden: includeHidden) else { return [] }
        return all.filter { $0.isDirectory && !$0.isHidden }
    }

    /// Recursive filename search, Windows-style. Caps total work so typing stays responsive.
    static func search(root: URL, query: String, includeHidden: Bool, cap: Int = 4000) -> [FSItem] {
        let q = query.lowercased()
        var result: [FSItem] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: includeHidden ? [] : [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return result }

        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            if !includeHidden && url.lastPathComponent.hasPrefix(".") {
                enumerator.skipDescendants()
                continue
            }
            let name = url.lastPathComponent
            if name.lowercased().contains(q) || url.pathExtension.lowercased().contains(q) {
                if let it = item(for: url) { result.append(it) }
            }
            if result.count >= cap { break }
        }
        return result
    }

    /// All mounted volumes, boot volume first.
    static func volumes() -> [DriveInfo] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsRemovableKey,
            .volumeIsBrowsableKey, .isVolumeKey,
        ]
        let mounted = fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var drives: [DriveInfo] = []
        for vol in mounted {
            guard let v = try? vol.resourceValues(forKeys: Set(keys)),
                  v.isVolume == true,
                  v.volumeIsBrowsable ?? true else { continue }
            let d = DriveInfo(
                url: vol,
                name: v.volumeName ?? vol.lastPathComponent,
                totalBytes: Int64(v.volumeTotalCapacity ?? 0),
                freeBytes: Int64(v.volumeAvailableCapacity ?? 0),
                isInternal: v.volumeIsInternal ?? false,
                isNetwork: !(v.volumeIsLocal ?? true),
                isRemovable: v.volumeIsRemovable ?? false,
                isBoot: vol.path == "/"
            )
            drives.append(d)
        }
        // Boot volume first, then local internals, externals, then network.
        drives.sort { a, b in
            func rank(_ d: DriveInfo) -> Int {
                if d.isBoot { return 0 }
                if d.isNetwork { return 3 }
                if d.isRemovable { return 2 }
                return 1
            }
            let (ra, rb) = (rank(a), rank(b))
            if ra != rb { return ra < rb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return drives
    }

    /// Cloud storage mounts (OneDrive/Dropbox/Google Drive/iCloud).
    static func cloudStorageFolders() -> [URL] {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: "/Library/CloudStorage", isDirectory: true)
        var result: [URL] = []
        if let names = try? fm.contentsOfDirectory(atPath: base.path) {
            for n in names where !n.hasPrefix(".") {
                result.append(base.appendingPathComponent(n, isDirectory: true))
            }
        }
        return result.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Recent images under a root (Gallery), newest first.
    static func images(root: URL, cap: Int = 600) -> [FSItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys + [.contentModificationDateKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }
        var result: [FSItem] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            if url.lastPathComponent.hasPrefix(".") { enumerator.skipDescendants(); continue }
            if FileCategory.of(pathExtension: url.pathExtension, isDirectory: false) == .image,
               let it = item(for: url) {
                result.append(it)
                if result.count >= cap { break }
            }
        }
        result.sort { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        return result
    }

    /// Directory stats for Properties: total bytes + file/folder counts (deep).
    static func directoryStats(_ url: URL) -> (bytes: Int64, files: Int, folders: Int) {
        var bytes: Int64 = 0, files = 0, folders = 0
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .isPackageKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return (0, 0, 0) }
        for case let u as URL in en {
            if Task.isCancelled { break }
            guard let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isPackageKey]) else { continue }
            let isDir = (v.isDirectory ?? false) && !(v.isPackage ?? false)
            if isDir { folders += 1 } else { files += 1; bytes += Int64(v.fileSize ?? 0) }
        }
        return (bytes, files, folders)
    }
}
