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

        // The fixed window registry makes selftest windows persist their session;
        // snapshot the real one and restore it at the end.
        let savedSessionTabs = UserDefaults.standard.object(forKey: "explorerr.session.tabs")

        // Spins the main runloop so detached loads/reloads can deliver while a
        // condition is awaited (with a timeout).
        func drain(until condition: @autoclosure () -> Bool, timeout: TimeInterval = 2) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { return true }
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            return condition()
        }

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

            vt.feed("abc\ndef")
            expect(vt.text(inRow: 1).hasPrefix("def"), "newline resets cursorCol to 0 (no stair-stepping)")
            expect(vt.cursorRow == 1 && vt.cursorCol == 3, "cursor position after newline and text")
            vt.feed("\u{1B}[2;3H") // CUP row 2, col 3
            expect(vt.cursorRow == 1 && vt.cursorCol == 2, "CUP cursor positioning")

            vt.feed("\u{1B}[38;5;196mX\u{1B}[0m\u{1B}[38;2;10;20;30mY\u{1B}[0m\u{1B}[38:2::40:50:60mZ")
            expect(vt.cell(row: 1, col: 2).fg == .indexed(196), "256-color SGR")
            expect(vt.cell(row: 1, col: 3).fg == .rgb(0x0A141E), "truecolor SGR")
            expect(vt.cell(row: 1, col: 4).fg == .rgb(0x28323C), "colon-syntax truecolor SGR")

            // ED 2 vs ED 3 (scrollback clear)
            for _ in 0..<10 { vt.feed("line\n") }
            expect(!vt.scrollback.isEmpty, "scrollback populated")
            vt.feed("\u{1B}[3J")
            expect(vt.scrollback.isEmpty, "ED 3 clears scrollback")

            vt.feed("\u{1B}[2J")
            expect(vt.text(inRow: 0).trimmingCharacters(in: .whitespaces).isEmpty, "ED clears screen")
            let wide = TerminalEmulator(cols: 5, rows: 3) // cols clamps to the 10-col minimum
            wide.feed("abcdefghijk")
            expect(wide.text(inRow: 0) == "abcdefghij" && wide.text(inRow: 1).hasPrefix("k"), "line wrap on overflow")

            let alt = TerminalEmulator(cols: 10, rows: 3)
            alt.feed("keep")
            alt.feed("\u{1B}[?1049hcleared\u{1B}[?1049l")
            expect(alt.text(inRow: 0).hasPrefix("keep"), "alt-screen restores primary buffer")

            // Shrinking must not shove the prompt into scrollback (blank rows go first)
            let shrink = TerminalEmulator(cols: 20, rows: 10)
            shrink.feed("hello")
            shrink.resize(cols: 20, rows: 5)
            expect(shrink.text(inRow: 0).hasPrefix("hello"), "shrink keeps content on screen")
            expect(shrink.scrollback.isEmpty, "shrink trims blank rows before using scrollback")
        }

        // TerminalController font zoom
        do {
            let tc = TerminalController()
            let initialSize = tc.fontSize
            tc.zoomIn()
            expect(tc.fontSize > initialSize, "terminal zoomIn increases font size")
            tc.resetZoom()
            expect(tc.fontSize == initialSize, "terminal resetZoom restores initial size")
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

        // PTY end-to-end: a clean-profile shell must emit a prompt and echo commands
        do {
            let pty = PtyProcess()
            var got = Data()
            let lock = NSLock()
            let sem = DispatchSemaphore(value: 0)
            pty.onOutput = { d in
                lock.lock(); got.append(d); let n = got.count; lock.unlock()
                if n >= 4 { sem.signal() }
            }
            pty.start(cwd: nil, cols: 60, rows: 12, usesProfile: false)
            _ = sem.wait(timeout: .now() + 4)
            pty.write(Data("echo SELFTEST-$((6*7))\n".utf8))
            let echoDeadline = Date().addingTimeInterval(4)
            var sawEcho = false
            while Date() < echoDeadline {
                lock.lock(); let text = String(data: got, encoding: .utf8) ?? ""; lock.unlock()
                if text.contains("SELFTEST-42") { sawEcho = true; break }
                usleep(100_000)
            }
            pty.terminate()
            lock.lock(); let promptBytes = got.count; lock.unlock()
            expect(promptBytes > 0, "pty shell emits output")
            expect(sawEcho, "pty shell executes a command (clean profile)")
        }

        // Terminal environment (clean profile vs user profile)
        do {
            let clean = PtyProcess.shellEnvironment(usesProfile: false, shellName: "zsh", zdotDir: "/tmp/zdot")
            expect(clean["ZDOTDIR"] == "/tmp/zdot" && clean["TERM_PROGRAM"] == "Explorerr", "clean shell env redirects ZDOTDIR")
            expect(clean["PATH"]?.contains("/opt/homebrew/bin") == true, "clean shell env includes Homebrew PATH")
            let full = PtyProcess.shellEnvironment(usesProfile: true, shellName: "zsh", zdotDir: "/tmp/zdot")
            expect(full["ZDOTDIR"] == ProcessInfo.processInfo.environment["ZDOTDIR"], "profile shell env leaves ZDOTDIR alone")
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

        // Reset all tabs to defaults
        do {
            let app = AppModel()
            let tc = TabController(app: app, locations: [.home])
            tc.active.viewMode = .iconsLarge
            tc.active.sortKey = .size
            tc.active.sortAscending = false
            app.resetAllTabsToDefaults()
            expect(app.folderPrefs.isEmpty, "resetAllTabsToDefaults clears folderPrefs")
        }

        // Window registry fan-out (the 1.0–1.1.7 "nothing refreshes, nothing saves" bug)
        do {
            let app = AppModel()
            let model = WindowModel(app: app)
            expect(AppModel.windowRegistry.allObjects.contains { $0 === model },
                   "window registry fan-out registers windows")

            let dir = tmp.appendingPathComponent("registry-check", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("gone.txt")
            FileManager.default.createFile(atPath: file.path, contents: Data())
            let tab = model.activeTab
            tab.navigate(.folder(dir))
            expect(drain(until: !tab.loading && !tab.items.isEmpty), "window registry fan-out loads the folder")

            try? FileManager.default.removeItem(at: file)
            app.foldersChanged([dir])
            expect(drain(until: tab.items.isEmpty), "window registry fan-out refreshes tabs after delete")
        }

        // Stale selection anchors must never index out of bounds (back/forward crash)
        do {
            let app = AppModel()
            let t = TabState(app: app, location: .home)
            t.navigate(.thisPC)
            let a = FSItem(url: URL(fileURLWithPath: "/tmp/a"), fileName: "a", isDirectory: false)
            let b = FSItem(url: URL(fileURLWithPath: "/tmp/b"), fileName: "b", isDirectory: false)
            t.items = [a, b]
            t.selection = [a.id]
            t.anchorIndex = 5000
            t.focusIndex = 5000
            t.extendSelection(to: 1)
            expect(t.selection == [b.id], "stale anchor clamped instead of crashing")
            t.anchorIndex = 4242
            t.goBack() // returns via navigateInternal, which must clear the anchor
            expect(t.anchorIndex == nil && t.focusIndex == nil, "stale anchor cleared by history navigation")

            t.filters = [.image]
            t.navigate(.thisPC)
            expect(t.filters.isEmpty, "filters reset on navigation")
        }

        // Redo must run the forward closure, not the undo closure again
        do {
            let app = AppModel()
            final class Box { var value = 0 }
            let box = Box()
            app.registerUndo(.customInverse(label: "Move", undo: { box.value -= 1 }, redo: { box.value += 1 }))
            app.undo()
            expect(box.value == -1, "undo closure runs")
            app.redo()
            expect(box.value == 0, "redo closure runs forward operation")
        }

        // Packages open; plain folders still navigate
        do {
            let dir = tmp.appendingPathComponent("plaindir", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = tmp.appendingPathComponent("note.txt")
            FileManager.default.createFile(atPath: file.path, contents: Data())
            let calc = URL(fileURLWithPath: "/System/Applications/Calculator.app")
            expect(FileOps.opensByNavigation(dir), "package open decision: plain folder navigates")
            expect(!FileOps.opensByNavigation(file), "package open decision: file opens")
            expect(!FileOps.opensByNavigation(calc), "package open decision: app bundle opens")
        }

        // Drop semantics: whole internal selection, external drags copy
        do {
            let f1 = tmp.appendingPathComponent("drop1.txt")
            let f2 = tmp.appendingPathComponent("drop2.txt")
            FileManager.default.createFile(atPath: f1.path, contents: Data())
            FileManager.default.createFile(atPath: f2.path, contents: Data())
            let (internalSrc, internalMove) = FileOps.resolveDrop(
                providerURLs: [f1], draggingPaths: [f1.path, f2.path], destination: tmp)
            expect(internalSrc.count == 2 && internalMove, "drop source uses whole internal drag selection")
            let (externalSrc, externalMove) = FileOps.resolveDrop(
                providerURLs: [f1, f2], draggingPaths: [], destination: tmp)
            expect(externalSrc.count == 2 && !externalMove, "drop source external drags copy")
        }

        // Permanent-delete wording must not mention the Recycle Bin
        do {
            let item = FSItem(url: tmp.appendingPathComponent("x.txt"), fileName: "x.txt", isDirectory: false)
            let permanentMsg = FileOps.confirmMessage(items: [item], permanent: true)
            expect(permanentMsg.contains("permanently delete") && !permanentMsg.contains("Recycle Bin"),
                   "delete confirm text matches the operation")
            expect(FileOps.confirmMessage(items: [item], permanent: false).contains("Recycle Bin"),
                   "delete confirm keeps Recycle Bin wording for soft delete")
        }

        // Trash origin keys survive same-name deletes via trash-name matching
        do {
            let update = FileOps.trashOriginUpdate(
                deleted: [URL(fileURLWithPath: "/d1/a.txt"), URL(fileURLWithPath: "/d2/a.txt")],
                before: [],
                after: ["a.txt", "a 2.txt"])
            expect(update["a.txt"] == "/d1/a.txt" && update["a 2.txt"] == "/d2/a.txt",
                   "trash origins keyed by trash names survive same-name deletes")
        }

        // Let debounced session saves from these tests fire, then restore the real session.
        _ = drain(until: true, timeout: 0.7)
        if let saved = savedSessionTabs {
            UserDefaults.standard.set(saved, forKey: "explorerr.session.tabs")
        } else {
            UserDefaults.standard.removeObject(forKey: "explorerr.session.tabs")
        }

        print(failures == 0 ? "SELFTEST PASSED (\(count) checks)" : "SELFTEST FAILED: \(failures)/\(count)")
        return failures == 0 ? 0 : 1
    }
}
