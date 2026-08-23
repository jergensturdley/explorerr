import Foundation

/// Lightweight logic tests runnable via `Explorerr --selftest` (XCTest is unavailable on
/// Command-Line-Tools-only machines). Exits 0 when everything passes.
enum SelfTest {
    @MainActor
    static func run() -> Int32 {
        var failures = 0
        var count = 0

        func expect(_ condition: Bool, _ name: String) {
            count += 1
            if condition {
                print("  ✓ \(name)")
            } else {
                failures += 1
                print("  ✗ \(name)")
            }
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("explorerr-selftest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Unique names
        do {
            let base = tmp.appendingPathComponent("New folder", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
            let unique = FileOps.uniqueURL(for: base)
            expect(unique.lastPathComponent == "New folder (2)", "uniqueURL appends (2)")
            expect(unique.deletingLastPathComponent().path == tmp.path, "uniqueURL stays in folder")
        } catch {
            expect(false, "uniqueURL folder setup")
        }
        do {
            let base = tmp.appendingPathComponent("report.txt")
            FileManager.default.createFile(atPath: base.path, contents: Data())
            FileManager.default.createFile(atPath: tmp.appendingPathComponent("report (2).txt").path, contents: Data())
            let unique = FileOps.uniqueURL(for: base)
            expect(unique.lastPathComponent == "report (3).txt", "uniqueURL increments past (2)")
        }

        // Location
        do {
            let cases: [Location] = [.home, .gallery, .thisPC, .network, .trash,
                                     .folder(URL(fileURLWithPath: "/Users/xyz/Documents"))]
            var ok = true
            for loc in cases {
                if let data = try? JSONEncoder().encode(loc),
                   let back = try? JSONDecoder().decode(Location.self, from: data) {
                    ok = ok && back == loc
                } else { ok = false }
            }
            expect(ok, "Location Codable round-trip")
        }
        expect(Location.home.title == "Home" && Location.thisPC.title == "This PC"
               && Location.trash.title == "Recycle Bin", "Location titles")

        // Breadcrumbs
        do {
            let url = DirectoryLoader.homeURL.appendingPathComponent("Documents/Projects")
            let chain = crumbs(for: url)
            expect(chain.count >= 4, "crumbs include every ancestor")
            expect(chain.last?.name == "Projects", "crumbs end at target")
        }

        // Categories
        expect(FileCategory.of(pathExtension: "png", isDirectory: false) == .image
               && FileCategory.of(pathExtension: "MP4", isDirectory: false) == .video
               && FileCategory.of(pathExtension: "zip", isDirectory: false) == .archive
               && FileCategory.of(pathExtension: nil, isDirectory: true) == .folder
               && FileCategory.of(pathExtension: "xyzq", isDirectory: false) == .other,
               "file categories")

        // Directory loading
        do {
            FileManager.default.createFile(atPath: tmp.appendingPathComponent("a.txt").path, contents: Data())
            try FileManager.default.createDirectory(at: tmp.appendingPathComponent("sub"), withIntermediateDirectories: false)
            let items = try DirectoryLoader.contents(of: tmp, includeHidden: false)
            // tmp already holds "New folder", "report.txt", "report (2).txt" from earlier checks
            expect(items.count == 5, "contents counts every item")
            expect(items.contains { $0.displayName == "sub" && $0.isDirectory }, "subfolder flagged as directory")

            let hidden = try DirectoryLoader.contents(of: tmp, includeHidden: false).filter { $0.displayName == ".DS_Store" }.count
            expect(hidden == 0, "hidden files excluded by default")
        } catch {
            expect(false, "directory contents")
        }

        // Search
        do {
            try FileManager.default.createDirectory(at: tmp.appendingPathComponent("deep/deeper"), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: tmp.appendingPathComponent("deep/deeper/needle.pdf").path, contents: Data())
            FileManager.default.createFile(atPath: tmp.appendingPathComponent("haystack.txt").path, contents: Data())
            let results = DirectoryLoader.search(root: tmp, query: "needle", includeHidden: false)
            expect(results.count == 1 && results.first?.fileName == "needle.pdf", "recursive search by name")
        } catch {
            expect(false, "search setup")
        }

        // Address bar paste/normalize + autocomplete
        do {
            let home = DirectoryLoader.homeURL
            expect(PathBarEngine.normalize("  \"\(home.path)\" ")?.path == home.path, "pasted quoted path normalizes")
            expect(PathBarEngine.normalize("\(home.path)/Documents/")?.lastPathComponent == "Documents", "trailing slash stripped")
            expect(PathBarEngine.normalize("file:///Users")?.path == "/Users", "file:// URL unwrapped")
            expect(PathBarEngine.normalize("   ") == nil, "blank input rejected")
            let sugg = PathBarEngine.suggestions(for: "\(home.path)/Docu")
            expect(sugg.contains { $0.url.lastPathComponent == "Documents" }, "autocomplete suggests Documents")
        }

        // View density zoom ladder
        do {
            expect(ViewMode.details.zoomedIn == .iconsSmall
                   && ViewMode.iconsSmall.zoomedIn == .iconsMedium
                   && ViewMode.iconsLarge.zoomedIn == .tiles
                   && ViewMode.tiles.zoomedIn == .details,
                   "zoom-in ladder cycles")
            expect(ViewMode.iconsSmall.zoomedOut == .details
                   && ViewMode.details.zoomedOut == .tiles,
                   "zoom-out ladder reverses")
        }

        // Terminal emulator
        do {
            let vt = TerminalEmulator(cols: 20, rows: 5)
            vt.feed("hi\u{1B}[31mred\u{1B}[0m!")
            expect(vt.text(inRow: 0).hasPrefix("hired!"), "text renders in order")
            expect(vt.cell(row: 0, col: 3).fg == .indexed(1), "SGR red applied")
            expect(vt.cell(row: 0, col: 7).fg == .default, "SGR reset applied")

            vt.feed("\u{1B}[2;3H") // CUP row 2, col 3
            expect(vt.cursorRow == 1 && vt.cursorCol == 2, "CUP cursor positioning")

            vt.feed("\u{1B}[38;5;196mX\u{1B}[0m\u{1B}[38;2;10;20;30mY")
            expect(vt.cell(row: 1, col: 2).fg == .indexed(196), "256-color SGR")
            expect(vt.cell(row: 1, col: 3).fg == .rgb(0x0A141E), "truecolor SGR")

            vt.feed("\u{1B}[2J")
            expect(vt.text(inRow: 0).trimmingCharacters(in: .whitespaces).isEmpty, "ED clears screen")

            let wide = TerminalEmulator(cols: 5, rows: 3) // cols clamps to the 10-col minimum
            wide.feed("abcdefghijk")
            expect(wide.text(inRow: 0) == "abcdefghij" && wide.text(inRow: 1).hasPrefix("k"), "line wrap on overflow")

            let alt = TerminalEmulator(cols: 10, rows: 3)
            alt.feed("keep")
            alt.feed("\u{1B}[?1049hcleared\u{1B}[?1049l")
            expect(alt.text(inRow: 0).hasPrefix("keep"), "alt-screen restores primary buffer")
        }

        // Formatters
        expect(!Fmt.size(1234).isEmpty && Fmt.size(nil).isEmpty, "byte formatting")
        expect(Fmt.counts(folders: 1, files: 3) == "1 folder; 3 files", "counts string")

        // Navigation history: multi-step jumps (address-bar history menu)
        do {
            let app = AppModel()
            let t = TabState(app: app, location: .home)
            t.navigate(.thisPC)
            t.navigate(.gallery)
            t.navigate(.network)
            t.goBack(steps: 2)
            expect(t.location == .thisPC && t.historyForward.count == 2, "goBack jumps multiple steps")
            t.goForward(steps: 2)
            expect(t.location == .network && t.historyForward.isEmpty, "goForward jumps multiple steps")
            t.goBack()
            expect(t.location == .gallery, "single-step back after jumps")

            // Invert selection
            let a = FSItem(url: URL(fileURLWithPath: "/tmp/a"), fileName: "a", isDirectory: false)
            let b = FSItem(url: URL(fileURLWithPath: "/tmp/b"), fileName: "b", isDirectory: false)
            t.items = [a, b]
            t.selection = [a.id]
            t.invertSelection()
            expect(t.selection == [b.id], "invertSelection flips the set")

            // ⇧+arrow range extension
            let c = FSItem(url: URL(fileURLWithPath: "/tmp/c"), fileName: "c", isDirectory: false)
            t.items = [a, b, c]
            t.selection = [a.id]
            t.anchorIndex = 0
            t.focusIndex = 0
            t.extendSelection(delta: 1)
            t.extendSelection(delta: 1)
            expect(t.selection.count == 3, "extendSelection grows range")
            t.extendSelection(delta: -1)
            expect(t.selection.count == 2 && !t.selection.contains(c.id), "extendSelection shrinks back")
        }

        // Rubber-band selection math
        do {
            let r = BandSelect.rect(from: CGPoint(x: 100, y: 80), to: CGPoint(x: 20, y: 10))
            expect(r == CGRect(x: 20, y: 10, width: 80, height: 70), "band rect normalizes any drag direction")
            let frames: [String: CGRect] = [
                "a": CGRect(x: 0, y: 0, width: 50, height: 20),     // overlaps corner
                "b": CGRect(x: 30, y: 40, width: 40, height: 20),   // fully inside
                "c": CGRect(x: 200, y: 200, width: 40, height: 20), // outside
            ]
            expect(BandSelect.hits(frames: frames, rect: r) == ["a", "b"], "band hits intersecting frames only")
            expect(BandSelect.hits(frames: frames, rect: CGRect(x: 500, y: 500, width: 10, height: 10)).isEmpty, "band misses everything cleanly")
        }

        // Prefs decoding tolerates keys added in later versions
        do {
            let legacy = #"{"showHidden":true,"showExtensions":false}"#
            let p = try? JSONDecoder().decode(Prefs.self, from: Data(legacy.utf8))
            expect(p?.showHidden == true && p?.showExtensions == false, "Prefs keeps stored values")
            expect(p?.syncTerminalCD == true && p?.foldersFirst == true, "Prefs defaults missing keys")
            expect(p?.appearance == .system && p?.singleClickOpen == false && p?.newTabsOpenHome == true
                   && p?.doubleClickEmptyGoesUp == true && p?.sidebarTrash == true && p?.showRecents == true,
                   "Prefs defaults new UX options")
        }

        // Spatial arrow navigation over a 3×2 grid of frames
        do {
            func cell(_ col: Int, _ row: Int) -> CGRect {
                CGRect(x: CGFloat(col) * 110, y: CGFloat(row) * 90, width: 100, height: 80)
            }
            let grid: [String: CGRect] = [
                "a": cell(0, 0), "b": cell(1, 0), "c": cell(2, 0),
                "d": cell(0, 1), "e": cell(1, 1), "f": cell(2, 1),
            ]
            expect(BandSelect.spatialMove(from: "b", frames: grid, direction: .down) == "e", "grid ↓ lands directly below")
            expect(BandSelect.spatialMove(from: "e", frames: grid, direction: .up) == "b", "grid ↑ lands directly above")
            expect(BandSelect.spatialMove(from: "b", frames: grid, direction: .right) == "c", "grid → moves within the row")
            expect(BandSelect.spatialMove(from: "b", frames: grid, direction: .left) == "a", "grid ← moves within the row")
            expect(BandSelect.spatialMove(from: "e", frames: grid, direction: .down) == nil, "grid ↓ stops at the bottom edge")
            expect(BandSelect.spatialMove(from: "c", frames: grid, direction: .right) == nil, "grid → stops at the row edge")
            expect(BandSelect.spatialMove(from: "a", frames: grid, direction: .down) == "d", "grid ↓ prefers same column over diagonal")
            expect(BandSelect.spatialMove(from: "missing", frames: grid, direction: .down) == nil, "unknown item yields nil")

            // Empty-space detection (double-click-to-go-up): clip y 0-500, items end at y 180
            let clip = CGRect(x: 0, y: 0, width: 400, height: 500)
            expect(!BandSelect.isEmptySpace(point: CGPoint(x: 50, y: 40), clip: clip, origin: .zero, frames: grid), "point on an item is not empty space")
            expect(!BandSelect.isEmptySpace(point: CGPoint(x: 105, y: 40), clip: clip, origin: .zero, frames: grid), "gap between items is not empty space")
            expect(BandSelect.isEmptySpace(point: CGPoint(x: 50, y: 300), clip: clip, origin: .zero, frames: grid), "below the last item is empty space")
            expect(!BandSelect.isEmptySpace(point: CGPoint(x: 50, y: 600), clip: clip, origin: .zero, frames: grid), "outside the clip is not empty space")
            expect(BandSelect.isEmptySpace(point: CGPoint(x: 50, y: 100), clip: clip, origin: .zero, frames: [:]), "empty folder: anywhere in the clip counts")
        }

        // Shelf: dedupe, order, remove (restore the user's persisted shelf afterwards —
        // the @Published didSet writes straight through to UserDefaults)
        do {
            let app = AppModel()
            let saved = app.shelf
            app.shelf = []
            let a = tmp.appendingPathComponent("a.txt")
            let b = tmp.appendingPathComponent("report.txt")   // created earlier in this run
            FileManager.default.createFile(atPath: a.path, contents: Data())
            app.addToShelf([a, b])
            app.addToShelf([a])
            expect(app.shelf == [a.path, b.path], "shelf dedupes and keeps order")
            app.removeFromShelf(a.path)
            expect(app.shelf == [b.path], "shelf removes a single entry")
            app.shelf = saved
        }

        // Tab reorder + reopen-closed-tab
        do {
            let app = AppModel()
            let tc = TabController(app: app, locations: [.home, .thisPC, .gallery])
            let ids = tc.tabs.map { $0.id }
            tc.moveTab(ids[0], onto: ids[2])
            expect(tc.tabs.map { $0.location } == [.thisPC, .gallery, .home], "moveTab drags right (after target)")
            tc.moveTab(ids[0], onto: ids[1])
            expect(tc.tabs.first?.location == .home, "moveTab drags left (before target)")
            tc.closeTab(ids[1])
            tc.reopenClosedTab()
            expect(tc.tabs.last?.location == .thisPC && tc.activeID == tc.tabs.last?.id, "reopenClosedTab restores the last closed location")
        }

        print(failures == 0 ? "SELFTEST PASSED (\(count) checks)" : "SELFTEST FAILED: \(failures)/\(count)")
        return failures == 0 ? 0 : 1
    }
}
