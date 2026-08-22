import Foundation
import AppKit

// MARK: - Conflict / progress models

enum ConflictChoice {
    case replace, skip, keepBoth
}

struct ConflictContext: Identifiable {
    let id = UUID()
    let sourceName: String
    let destName: String
    let remaining: Int
}

final class TransferProgress: ObservableObject {
    @Published var done = 0
    @Published var total = 0
    @Published var currentName = ""
    @Published var finished = false
    var cancelled = false
}

// MARK: - FileOps

@MainActor
enum FileOps {
    static var fm: FileManager { FileManager.default }

    // MARK: unique names ("name (2).ext" — Windows style)

    nonisolated static func uniqueURL(for url: URL) -> URL {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = url
        var i = 2
        while fm.fileExists(atPath: candidate.path) {
            let composed = ext.isEmpty ? "\(name) (\(i))" : "\(name) (\(i)).\(ext)"
            candidate = dir.appendingPathComponent(composed, isDirectory: url.hasDirectoryPath)
            i += 1
        }
        return candidate
    }

    // MARK: open

    static func open(_ url: URL, app: AppModel) {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return // folders handled by navigation
        }
        NSWorkspace.shared.open(url)
        app.recordRecent(url)
    }

    /// Double-click behavior: folders navigate in the tab, files open.
    static func openSelection(in tab: TabState, app: AppModel, newTab: Bool = false) {
        let selected = tab.selectedItems
        guard !selected.isEmpty else { return }
        for item in selected {
            if item.isDirectory {
                let loc = Location.folder(item.url)
                if newTab {
                    // navigate via controller if available through notification; caller handles
                    NotificationCenter.default.post(name: .explorerrOpenInNewTab, object: loc)
                } else {
                    tab.navigate(loc)
                }
            } else {
                open(item.url, app: app)
            }
        }
    }

    // MARK: transfer core (copy / move)

    static func transfer(_ sources: [URL], to destDir: URL, move: Bool, app: AppModel, tab: TabState? = nil) async {
        guard !sources.isEmpty else { return }
        let fm = self.fm

        // Resolve conflicts up front (per source that exists at destination).
        var plan: [(src: URL, choice: ConflictChoice?)] = []
        var pendingConflicts: [(src: URL, destName: String)] = []
        for src in sources {
            let dest = destDir.appendingPathComponent(src.lastPathComponent)
            if src.standardizedFileURL.path == dest.standardizedFileURL.path {
                plan.append((src, .skip))
            } else if fm.fileExists(atPath: dest.path) {
                pendingConflicts.append((src, src.lastPathComponent))
            } else {
                plan.append((src, nil))
            }
        }

        // Ask interactively for each conflict (honoring apply-all)
        for (idx, conflict) in pendingConflicts.enumerated() {
            let choice: ConflictChoice
            if let applied = app.applyAllChoice {
                choice = applied
            } else {
                choice = await app.askConflict(
                    sourceName: conflict.src.lastPathComponent,
                    destName: conflict.destName,
                    remaining: pendingConflicts.count - idx - 1
                )
            }
            plan.append((conflict.src, choice))
        }
        app.activeSheet = nil
        if app.applyAllChoice != nil { app.applyAllChoice = nil }

        let actionable = plan.filter { $0.choice != .skip }
        guard !actionable.isEmpty else {
            if move { app.clearCutState() }
            app.foldersChanged([destDir])
            return
        }

        // Run with progress sheet
        let progress = TransferProgress()
        progress.total = actionable.count
        app.activeSheet = .progress(progress)

        var transferred: [URL] = []
        var movedPairs: [(from: URL, to: URL)] = []
        var errors: [String] = []

        for entry in actionable {
            if progress.cancelled { break }
            progress.currentName = entry.src.lastPathComponent
            do {
                if let final = try transferOne(entry.src, into: destDir, move: move, choice: entry.choice) {
                    transferred.append(final)
                    if move { movedPairs.append((entry.src, final)) }
                }
            } catch {
                errors.append("\(entry.src.lastPathComponent): \(error.localizedDescription)")
            }
            progress.done += 1
        }

        progress.finished = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        if case .progress(let p) = app.activeSheet, p === progress { app.activeSheet = nil }

        if !errors.isEmpty {
            app.lastError = errors.prefix(4).joined(separator: "\n") + (errors.count > 4 ? "\n… and \(errors.count - 4) more" : "")
        }

        if move {
            app.clearCutState()
            if !movedPairs.isEmpty {
                // Undo: move everything back
                let pairs = movedPairs
                app.registerUndo(.customInverse(label: "Move", undo: { [weak app] in
                    guard let app else { return }
                    for pair in pairs {
                        try? FileManager.default.moveItem(at: pair.to, to: pair.from)
                    }
                    app.foldersChanged([destDir] + pairs.map { $0.from.deletingLastPathComponent() })
                }))
            }
            app.foldersChanged([destDir] + sources.map { $0.deletingLastPathComponent() })
        } else if !transferred.isEmpty {
            app.registerUndo(.pasted(urls: transferred))
            app.foldersChanged([destDir])
        }
        tab?.reload()
    }

    private static func transferOne(_ src: URL, into destDir: URL, move: Bool, choice: ConflictChoice?) throws -> URL? {
        let fm = self.fm
        var dest = destDir.appendingPathComponent(src.lastPathComponent, isDirectory: src.hasDirectoryPath)
        if fm.fileExists(atPath: dest.path) {
            switch choice {
            case .skip, .none:
                return nil
            case .replace:
                try? fm.removeItem(at: dest)
            case .keepBoth:
                dest = uniqueURL(for: dest)
            }
        }
        do {
            if move {
                try fm.moveItem(at: src, to: dest)
            } else {
                try fm.copyItem(at: src, to: dest)
            }
            return dest
        } catch {
            // Cross-volume move: copy then remove source
            if move {
                try fm.copyItem(at: src, to: dest)
                try? fm.removeItem(at: src)
                return dest
            }
            throw error
        }
    }

    // MARK: paste

    static func paste(into destDir: URL, app: AppModel, tab: TabState? = nil) async {
        guard let urls = app.clipboardURLs() else {
            app.toast("The clipboard doesn't contain files")
            return
        }
        let move = app.isClipboardCut()
        await transfer(urls, to: destDir, move: move, app: app, tab: tab)
    }

    // MARK: delete

    static func deleteItems(_ items: [FSItem], app: AppModel, permanent: Bool = false) async {
        guard !items.isEmpty else { return }
        let urls = items.map { $0.url }
        let run: () async -> Void = { await doDelete(urls, app: app, permanent: permanent) }
        if app.prefs.confirmDelete {
            app.confirm = ConfirmRequest(
                title: permanent ? "Delete Permanently" : "Delete",
                message: "Are you sure you want to move \(items.count == 1 ? "“\(items.first!.displayName)”" : "these \(items.count) items") to the Recycle Bin?",
                confirmLabel: permanent ? "Delete" : "Yes",
                destructive: permanent,
                action: { Task { await run() } }
            )
        } else {
            await run()
        }
    }

    private static func doDelete(_ urls: [URL], app: AppModel, permanent: Bool) async {
        if permanent {
            for u in urls { try? fm.removeItem(at: u) }
            app.foldersChanged(urls.map { $0.deletingLastPathComponent() })
            return
        }
        // Record origins for undo/put-back
        var origins = app.trashOrigins
        for u in urls { origins[u.lastPathComponent] = u.path }
        app.trashOrigins = origins

        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            NSWorkspace.shared.recycle(urls) { _, error in
                cont.resume(returning: error == nil)
            }
        }
        if !ok {
            // Fallback: at least try plain removal to trash dir
            let trash = DirectoryLoader.trashURL
            for u in urls {
                var dst = trash.appendingPathComponent(u.lastPathComponent, isDirectory: u.hasDirectoryPath)
                if fm.fileExists(atPath: dst.path) { dst = uniqueURL(for: dst) }
                try? fm.moveItem(at: u, to: dst)
            }
        }
        app.registerUndo(.trashed(urls: urls))
        app.cutURLs.subtract(urls.map { $0.path })
        app.foldersChanged(urls.map { $0.deletingLastPathComponent() })
        app.toast("Moved \(urls.count) item\(urls.count == 1 ? "" : "s") to the Recycle Bin")
    }

    // MARK: restore from trash

    static func restore(_ urls: [URL], to dest: URL, app: AppModel) async {
        var restored = 0
        let trash = DirectoryLoader.trashURL
        for u in urls {
            var src = u
            if !fm.fileExists(atPath: src.path) {
                // Name may have been mangled in the Trash; try to find by prefix
                if let found = try? fm.contentsOfDirectory(atPath: trash.path)
                    .first(where: { $0 == u.lastPathComponent || $0.hasPrefix(u.lastPathComponent + " ") || $0.hasPrefix(u.lastPathComponent + "~") }) {
                    src = trash.appendingPathComponent(found, isDirectory: u.hasDirectoryPath)
                } else { continue }
            }
            var dst = dest.appendingPathComponent(u.lastPathComponent, isDirectory: u.hasDirectoryPath)
            if fm.fileExists(atPath: dst.path) { dst = uniqueURL(for: dst) }
            if (try? fm.moveItem(at: src, to: dst)) != nil { restored += 1 }
        }
        app.toast("Restored \(restored) item\(restored == 1 ? "" : "s")")
        app.foldersChanged([dest, trash])
    }

    static func originalPath(for trashItem: FSItem, app: AppModel) -> URL? {
        if let p = app.trashOrigins[trashItem.fileName], !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).deletingLastPathComponent)
        }
        return nil
    }

    static func emptyTrash(app: AppModel) async {
        app.activeSheet = .emptyTrash
    }

    static func performEmptyTrash(app: AppModel) async {
        let trash = DirectoryLoader.trashURL
        if let names = try? fm.contentsOfDirectory(atPath: trash.path) {
            for n in names {
                if n == ".DS_Store" { continue }
                try? fm.removeItem(at: trash.appendingPathComponent(n, isDirectory: true))
            }
        }
        app.trashOrigins = [:]
        app.activeSheet = nil
        app.foldersChanged([trash])
        app.toast("Recycle Bin emptied")
    }

    // MARK: rename

    @discardableResult
    static func renameItem(_ item: FSItem, to rawName: String, app: AppModel) -> Bool {
        let newName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, !newName.contains("/") else {
            app.lastError = "“\(newName)” is not a valid file name."
            return false
        }
        let current = item.displayName
        if newName == current { return true }
        let dir = item.url.deletingLastPathComponent()
        let target = dir.appendingPathComponent(newName, isDirectory: item.isDirectory)
        if fm.fileExists(atPath: target.path) {
            app.lastError = "An item named “\(newName)” already exists in this folder."
            return false
        }
        do {
            try fm.moveItem(at: item.url, to: target)
            app.registerUndo(.renamed(from: item.url, to: target))
            app.foldersChanged([dir])
            return true
        } catch {
            app.lastError = "Renaming failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: new items

    @discardableResult
    static func newFolder(in dir: URL, app: AppModel, tab: TabState?) async -> URL? {
        let url = uniqueURL(for: dir.appendingPathComponent("New folder", isDirectory: true))
        do { try fm.createDirectory(at: url, withIntermediateDirectories: false) }
        catch { app.lastError = "Couldn't create folder: \(error.localizedDescription)"; return nil }
        app.registerUndo(.created(urls: [url]))
        app.foldersChanged([dir])
        tab?.reload()
        tab?.pendingRenameID = url.path
        return url
    }

    @discardableResult
    static func newTextDocument(in dir: URL, app: AppModel, tab: TabState?) async -> URL? {
        let url = uniqueURL(for: dir.appendingPathComponent("New Text Document.txt"))
        if !fm.createFile(atPath: url.path, contents: Data("\n".utf8)) {
            app.lastError = "Couldn't create the text document."
            return nil
        }
        app.registerUndo(.created(urls: [url]))
        app.foldersChanged([dir])
        tab?.reload()
        tab?.pendingRenameID = url.path
        return url
    }

    // MARK: compress (Send to ▸ Compressed (zipped) folder)

    @discardableResult
    static func compress(_ items: [FSItem], app: AppModel, tab: TabState?) async -> URL? {
        guard let first = items.first else { return nil }
        let dir = first.url.deletingLastPathComponent()
        let baseName: String
        if items.count == 1 {
            baseName = first.isDirectory ? first.displayName : first.url.deletingPathExtension().lastPathComponent
        } else {
            baseName = tab?.currentFolderURL?.lastPathComponent ?? "Archive"
        }
        let dest = uniqueURL(for: dir.appendingPathComponent("\(baseName).zip"))

        let sources = items.map { $0.url.path }
        let destPath = dest.path
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent"] + sources + [destPath]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                return proc.terminationStatus == 0
            } catch { return false }
        }.value

        if ok {
            app.registerUndo(.created(urls: [dest]))
            app.foldersChanged([dir])
            app.toast("Created \(dest.lastPathComponent)")
            tab?.reload()
            return dest
        } else {
            app.lastError = "Couldn't create the compressed folder."
            return nil
        }
    }

    // MARK: duplicate

    static func duplicate(_ items: [FSItem], app: AppModel) async {
        let urls = items.map { $0.url }
        for u in urls {
            let dir = u.deletingLastPathComponent()
            let base = u.deletingPathExtension().lastPathComponent
            let ext = u.pathExtension
            let name = ext.isEmpty ? "\(base) - Copy" : "\(base) - Copy.\(ext)"
            var dest = dir.appendingPathComponent(name, isDirectory: u.hasDirectoryPath)
            if fm.fileExists(atPath: dest.path) {
                let n = ext.isEmpty ? "\(base) - Copy (2)" : "\(base) - Copy (2).\(ext)"
                dest = dir.appendingPathComponent(n, isDirectory: u.hasDirectoryPath)
                dest = uniqueURL(for: dest)
            }
            try? fm.copyItem(at: u, to: dest)
        }
        if !urls.isEmpty {
            app.foldersChanged([urls[0].deletingLastPathComponent()])
            app.toast("Duplicated \(urls.count) item\(urls.count == 1 ? "" : "s")")
        }
    }
}

extension Notification.Name {
    static let explorerrOpenInNewTab = Notification.Name("explorerr.openInNewTab")
}
