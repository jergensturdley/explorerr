import Foundation

/// Lightweight logic tests runnable via `Explorerr --selftest` (XCTest is unavailable on
/// Command-Line-Tools-only machines). Exits 0 when everything passes.
enum SelfTest {
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

        print(failures == 0 ? "SELFTEST PASSED (\(count) checks)" : "SELFTEST FAILED: \(failures)/\(count)")
        return failures == 0 ? 0 : 1
    }
}
