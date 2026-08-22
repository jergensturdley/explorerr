import SwiftUI
import AppKit

/// One autocomplete suggestion for the editable address bar.
struct PathSuggestion: Identifiable {
    let url: URL          // destination folder
    let completion: String // full path to place in the field
    var id: String { completion }
}

struct AddressBar: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme

    @State private var editingPath = false
    @State private var pathText = ""
    @State private var pathWasCommitted = false
    @FocusState private var pathFocused: Bool
    @FocusState private var searchFocused: Bool

    // Autocomplete state
    @State private var suggestions: [PathSuggestion] = []
    @State private var selectedSuggestion: Int? = nil
    @State private var editorError: String? = nil
    @State private var suggestTask: Task<Void, Never>?
    @State private var editorMonitor: Any?

    var body: some View {
        let p = Win11.palette(theme.scheme)
        HStack(spacing: 6) {
            navButton("arrow.left", help: "Back (⌥←)", enabled: !tab.historyBack.isEmpty) { tab.goBack() }
            navButton("arrow.right", help: "Forward (⌥→)", enabled: !tab.historyForward.isEmpty) { tab.goForward() }
            navButton("arrow.up", help: "Up (⌥↑)", enabled: tab.currentFolderURL != nil) { tab.goUp() }

            if editingPath {
                editor(p)
            } else {
                breadcrumbs(p)
            }

            searchField(p)
        }
        .padding(.horizontal, 8)
        .frame(height: Win11.Metrics.addressBarHeight)
        .onReceive(NotificationCenter.default.publisher(for: .explorerrBeginPathEdit)) { _ in
            beginEditing()
        }
        .onReceive(NotificationCenter.default.publisher(for: .explorerrFocusSearch)) { _ in
            searchFocused = true
        }
        .onDisappear { removeEditorMonitor() }
    }

    // MARK: nav buttons

    private func navButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(WinIconButtonStyle(enabled: enabled))
        .disabled(!enabled)
        .help(help)
    }

    // MARK: breadcrumb bar

    private func breadcrumbs(_ p: Win11.Palette) -> some View {
        HStack(spacing: 3) {
            leadingIcon
                .padding(.leading, 8)

            if case .folder(let url) = tab.location {
                let chain = crumbs(for: url)
                ForEach(Array(chain.enumerated()), id: \.element.url.path) { idx, crumb in
                    if idx > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(p.textSecondary)
                            .frame(width: 10)
                    }
                    crumbSegment(crumb, p, isLast: idx == chain.count - 1)
                }
            } else {
                Text(specialTitle)
                    .font(Win11.Fonts.breadcrumb)
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            // History dropdown (Win11 address-bar chevron)
            WinMenuButton(width: 300, entries: historyMenu) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(WinIconButtonStyle(padding: 4))
            .padding(.trailing, 2)
            .help("Recent locations")
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusControl, style: .continuous)
                .fill(p.addressBarBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusControl, style: .continuous)
                .strokeBorder(p.addressBarStroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Click on empty breadcrumb area switches to path editing (Windows behavior)
            beginEditing()
        }
    }

    private var specialTitle: String {
        switch tab.location {
        case .home: return "Home"
        case .gallery: return "Gallery"
        case .thisPC: return "This PC"
        case .network: return "Network"
        case .trash: return "Recycle Bin"
        case .folder: return ""
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch tab.location {
        case .folder(let url): FolderIconView(variant: FolderVariant.forFolderURL(url), size: 16)
        case .home: NavIcon(symbol: "house.fill", size: 16)
        case .gallery: NavIcon(symbol: "photo.on.rectangle.angled", size: 16)
        case .thisPC: PCIconView(size: 16)
        case .network: NavIcon(symbol: "point.3.connected.trianglepath.dotted", size: 16)
        case .trash: TrashIconView(size: 16)
        }
    }

    private func crumbSegment(_ crumb: AddressCrumb, _ p: Win11.Palette, isLast: Bool) -> some View {
        HStack(spacing: 2) {
            if isLast {
                Text(crumb.name)
                    .font(Win11.Fonts.breadcrumb)
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 3)

                WinMenuButton(width: 240, entries: folderChildrenMenu(crumb.url)) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(p.textSecondary)
                }
                .buttonStyle(WinIconButtonStyle(padding: 3))
            } else {
                Button {
                    tab.navigate(.folder(crumb.url))
                } label: {
                    Text(crumb.name)
                        .font(Win11.Fonts.breadcrumb)
                        .foregroundStyle(p.textPrimary)
                        .lineLimit(1)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                WinMenuButton(width: 240, entries: folderChildrenMenu(crumb.url)) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(p.textSecondary)
                }
                .buttonStyle(WinIconButtonStyle(padding: 2))
            }
        }
    }

    private var historyMenu: [WinMenuEntry] {
        var items: [WinMenuEntry] = []
        // Most recent history first; each row jumps the exact number of steps to reach it.
        let back = Array(tab.historyBack.suffix(6).reversed())
        if !back.isEmpty {
            items.append(.header("Back"))
            for (idx, loc) in back.enumerated() {
                items.append(.row(.init(label: loc.title, icon: nil) {
                    tab.goBack(steps: idx + 1)
                }))
            }
        }
        let forward = Array(tab.historyForward.suffix(6).reversed())
        if !forward.isEmpty {
            if !items.isEmpty { items.append(.separator()) }
            items.append(.header("Forward"))
            for (idx, loc) in forward.enumerated() {
                items.append(.row(.init(label: loc.title, icon: nil) {
                    tab.goForward(steps: idx + 1)
                }))
            }
        }
        if items.isEmpty {
            items = [.row(.init(label: "No recent locations", disabled: true))]
        }
        return items
    }

    private func folderChildrenMenu(_ folder: URL) -> [WinMenuEntry] {
        let children = DirectoryLoader.childFolders(of: folder, includeHidden: app.prefs.showHidden)
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        guard !children.isEmpty else {
            return [.row(.init(label: "(empty)", disabled: true))]
        }
        return children.prefix(25).map { child in
            .row(.init(label: child.displayName, icon: nil) {
                tab.navigate(.folder(child.url))
            })
        }
    }

    // MARK: editable path editor (Windows Ctrl+L style)

    private func editor(_ p: Win11.Palette) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(p.textSecondary)

            TextField("Type or paste a path, e.g. ~/Downloads", text: $pathText)
                .textFieldStyle(.plain)
                .font(Win11.Fonts.breadcrumb)
                .focused($pathFocused)
                .onSubmit { commitPath(newTab: false, fromBlur: false) }
                .onChange(of: pathText) { _ in
                    editorError = nil
                    selectedSuggestion = nil
                    scheduleSuggestions()
                }
                .onChange(of: pathFocused) { focused in
                    if !focused, editingPath, !pathWasCommitted {
                        // Focus lost: navigate if valid, otherwise silently cancel (Windows behavior)
                        commitPath(newTab: false, fromBlur: true)
                    }
                }

            if !pathText.isEmpty {
                Button {
                    pathText = ""
                    pathFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(p.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusControl, style: .continuous)
                .fill(p.contentBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusControl, style: .continuous)
                .strokeBorder(editorError != nil ? p.danger : p.addressBarFocused, lineWidth: 1.6)
        )
        .overlay(alignment: .bottom) {
            suggestionDropdown(p)
        }
        .zIndex(50)
    }

    // MARK: autocomplete dropdown

    @ViewBuilder
    private func suggestionDropdown(_ p: Win11.Palette) -> some View {
        if editingPath && (!suggestions.isEmpty || editorError != nil) {
            VStack(alignment: .leading, spacing: 0) {
                if let err = editorError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(p.danger)
                        Text(err)
                            .font(.system(size: 11.5))
                            .foregroundStyle(p.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                } else {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { idx, suggestion in
                        Button {
                            acceptSuggestion(idx)
                        } label: {
                            HStack(spacing: 7) {
                                FolderIconView(variant: FolderVariant.forFolderURL(suggestion.url), size: 16)
                                Text(suggestion.url.lastPathComponent)
                                    .font(Win11.Fonts.breadcrumb)
                                    .foregroundStyle(p.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(suggestion.completion)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(p.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(idx == selectedSuggestion ? p.selectionBG : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering { selectedSuggestion = idx }
                        }
                    }
                }

                Rectangle().fill(p.menuSeparator).frame(height: 1)

                HStack(spacing: 10) {
                    Text("↩ open").font(.system(size: 10.5)).foregroundStyle(p.textSecondary)
                    Text("⌥↩ new tab").font(.system(size: 10.5)).foregroundStyle(p.textSecondary)
                    Text("↑↓ choose").font(.system(size: 10.5)).foregroundStyle(p.textSecondary)
                    Text("esc cancel").font(.system(size: 10.5)).foregroundStyle(p.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
            }
            .frame(width: 430, alignment: .leading)
            .background(p.menuBG)
            .clipShape(RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusMenu, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusMenu, style: .continuous)
                    .strokeBorder(p.menuBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(theme.scheme == .dark ? 0.45 : 0.16), radius: 14, x: 0, y: 8)
            .offset(y: 42)
            .allowsHitTesting(true)
        }
    }

    // MARK: editing lifecycle

    private func beginEditing() {
        guard !editingPath else { return }
        if case .folder(let url) = tab.location {
            pathText = url.path
        } else {
            pathText = ""
        }
        pathWasCommitted = false
        editorError = nil
        suggestions = []
        selectedSuggestion = nil
        editingPath = true
        pathFocused = true
        installEditorMonitor()
        // Select the whole path so a pasted path replaces it (Windows behavior)
        DispatchQueue.main.async {
            if let tv = NSApp.keyWindow?.firstResponder as? NSTextView {
                tv.selectAll(nil)
            }
        }
        scheduleSuggestions()
    }

    private func finishEditing() {
        removeEditorMonitor()
        editingPath = false
        suggestions = []
        selectedSuggestion = nil
        editorError = nil
        pathFocused = false
    }

    private func commitPath(newTab: Bool, fromBlur: Bool) {
        guard editingPath, !pathWasCommitted else { return }
        guard let url = PathBarEngine.normalize(pathText) else {
            if fromBlur { finishEditing() } else { editorError = "Type a path, e.g. ~/Downloads or /Volumes/…" }
            return
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                pathWasCommitted = true
                if newTab {
                    NotificationCenter.default.post(name: .explorerrOpenInNewTab, object: Location.folder(url))
                } else {
                    tab.navigate(.folder(url))
                }
                finishEditing()
            } else {
                // A file path: open the file, like Windows
                pathWasCommitted = true
                FileOps.open(url, app: app)
                finishEditing()
            }
        } else {
            if fromBlur {
                finishEditing()
            } else {
                editorError = "Windows can’t find “\(url.path)”. Check the spelling and try again."
            }
        }
    }

    private func acceptSuggestion(_ idx: Int) {
        guard suggestions.indices.contains(idx) else { return }
        pathText = suggestions[idx].completion
        pathWasCommitted = true
        tab.navigate(.folder(suggestions[idx].url))
        finishEditing()
    }

    // MARK: suggestions engine

    private func scheduleSuggestions() {
        suggestTask?.cancel()
        let raw = pathText
        guard !raw.isEmpty else { suggestions = []; editorError = nil; return }
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                PathBarEngine.suggestions(for: raw)
            }.value
            guard !Task.isCancelled else { return }
            suggestions = result
            if result.isEmpty { selectedSuggestion = nil }
        }
    }

    // MARK: editor key handling (arrows / enter / esc / tab)

    private func installEditorMonitor() {
        guard editorMonitor == nil else { return }
        editorMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard editingPath, pathFocused else { return event }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 53: // Escape
                pathWasCommitted = true
                finishEditing()
                return nil
            case 125: // Arrow down
                if !suggestions.isEmpty {
                    let next = ((selectedSuggestion ?? -1) + 1) % suggestions.count
                    selectedSuggestion = next
                    return nil
                }
                return event
            case 126: // Arrow up
                if !suggestions.isEmpty {
                    let current = selectedSuggestion ?? 0
                    let prev = (current - 1 + suggestions.count) % suggestions.count
                    selectedSuggestion = prev
                    return nil
                }
                return event
            case 48: // Tab → complete the highlighted suggestion into the field
                if suggestions.indices.contains(selectedSuggestion ?? -1) {
                    pathText = suggestions[selectedSuggestion!].completion
                    return nil
                }
                return event
            case 36, 76: // Return
                if mods.contains(.option) {
                    commitPath(newTab: true, fromBlur: false)
                } else if let sel = selectedSuggestion, suggestions.indices.contains(sel) {
                    acceptSuggestion(sel)
                } else {
                    commitPath(newTab: false, fromBlur: false)
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeEditorMonitor() {
        if let m = editorMonitor {
            NSEvent.removeMonitor(m)
            editorMonitor = nil
        }
    }

    // MARK: search box

    private func searchField(_ p: Win11.Palette) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5))
                .foregroundStyle(p.textSecondary)

            TextField(searchPlaceholder, text: $tab.searchText)
                .textFieldStyle(.plain)
                .font(Win11.Fonts.breadcrumb)
                .focused($searchFocused)

            if !tab.searchText.isEmpty {
                Button {
                    tab.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(p.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }

            WinMenuButton(width: 210, entries: searchOptionsMenu) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(p.textSecondary)
            }
            .buttonStyle(WinIconButtonStyle(padding: 3))
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .frame(width: 230, height: 34)
        .background(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusControl, style: .continuous)
                .fill(p.addressBarBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusControl, style: .continuous)
                .strokeBorder(
                    tab.isSearching ? p.addressBarFocused : p.addressBarStroke,
                    lineWidth: tab.isSearching ? 1.6 : 1
                )
        )
    }

    private var searchPlaceholder: String {
        switch tab.location {
        case .folder(let url): return "Search \(url.lastPathComponent)"
        case .home: return "Search Home"
        default: return "Search"
        }
    }

    private var searchOptionsMenu: [WinMenuEntry] {
        [
            .row(.init(label: "All subfolders", checked: app.prefs.searchAllSubfolders) {
                app.prefs.searchAllSubfolders = true
                tab.clearSearch()
            }),
            .row(.init(label: "Current folder", checked: !app.prefs.searchAllSubfolders) {
                app.prefs.searchAllSubfolders = false
                tab.clearSearch()
            }),
            .separator(),
            .row(.init(label: "Clear search", icon: "xmark") {
                tab.clearSearch()
            }),
        ]
    }
}

struct AddressCrumb: Hashable {
    let url: URL
    let name: String
}

/// Builds the breadcrumb chain, using volume names for roots.
func crumbs(for url: URL) -> [AddressCrumb] {
    var result: [AddressCrumb] = []
    let path = url.standardizedFileURL.path
    let volumeRootName: String = {
        if path == "/" {
            let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey])
            return v?.volumeName ?? "Macintosh HD"
        }
        return ""
    }()

    if path == "/" {
        return [AddressCrumb(url: URL(fileURLWithPath: "/"), name: volumeRootName)]
    }

    var acc = URL(fileURLWithPath: "/")
    result.append(AddressCrumb(url: acc, name: volumeRootName.isEmpty ? "/" : volumeRootName))

    // Under /Volumes/<vol> the first component is the volume
    let comps = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
    var idx = 0
    if comps.first == "Volumes", comps.count >= 2 {
        acc = acc.appendingPathComponent("Volumes", isDirectory: true).appendingPathComponent(comps[1], isDirectory: true)
        result.append(AddressCrumb(url: acc, name: comps[1]))
        idx = 2
    }

    let home = DirectoryLoader.homeURL.standardizedFileURL
    for i in idx..<comps.count {
        acc = acc.appendingPathComponent(comps[i], isDirectory: true)
        var name = comps[i]
        if acc.standardizedFileURL.path == home.path {
            name = NSUserName()
        }
        result.append(AddressCrumb(url: acc, name: name))
    }
    return result
}


/// Nonisolated helpers for the editable address bar (pure path logic; safe off-main).
enum PathBarEngine {
    /// Normalizes whatever the user typed/pasted: trims, strips quotes, resolves ~,
    /// unwraps file:// URLs, drops trailing slashes.
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return nil }
        if text.hasPrefix("file://") {
            if let url = URL(string: text) {
                return url.standardizedFileURL
            }
            if let encoded = text.replacingOccurrences(of: " ", with: "%20") as String?,
               let url = URL(string: encoded) {
                return url.standardizedFileURL
            }
        }
        while text.count > 1 && text.hasSuffix("/") { text = String(text.dropLast()) }
        var url = DirectoryLoader.resolveHomeRelative(text)
        if url.path.isEmpty { url = URL(fileURLWithPath: "/") }
        return url.standardizedFileURL
    }

    /// Finds the deepest existing ancestor of the typed path, then suggests its
    /// subfolders matching the partial last component.
    static func suggestions(for raw: String, limit: Int = 8) -> [PathSuggestion] {
        guard let url = normalize(raw) else { return [] }
        let fm = FileManager.default

        // Walk down to the deepest existing directory ancestor
        var base = url
        var remainder: [String] = []
        var isDir: ObjCBool = false
        while !(fm.fileExists(atPath: base.path, isDirectory: &isDir) && isDir.boolValue) {
            remainder.insert(base.lastPathComponent, at: 0)
            let parent = base.deletingLastPathComponent()
            if parent.path == base.path { return [] }
            base = parent
        }

        let prefix: String
        if remainder.isEmpty {
            prefix = ""
        } else if remainder.count == 1 {
            prefix = remainder[0].lowercased()
        } else {
            return []
        }

        let children = DirectoryLoader.childFolders(of: base, includeHidden: false)
            .filter { prefix.isEmpty || $0.displayName.lowercased().hasPrefix(prefix) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        return children.prefix(limit).map { child in
            PathSuggestion(url: child.url, completion: child.url.path)
        }
    }
}

extension Notification.Name {
    static let explorerrBeginPathEdit = Notification.Name("explorerr.beginPathEdit")
}

extension Notification.Name {
    static let explorerrFocusSearch = Notification.Name("explorerr.focusSearch")
}
