import SwiftUI
import AppKit

// Top-left-only rounded corner for the Win11 content card
struct TopLeftRoundedShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width, rect.height)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Main window (multi-pane)

struct MainWindow: View {
    @StateObject private var windowModel: WindowModel
    @StateObject private var chrome = WindowChromeState()
    @StateObject private var theme = Theme()
    @StateObject private var terminal = TerminalController()

    @EnvironmentObject var app: AppModel
    @EnvironmentObject var menuCoord: MenuCoordinator
    @Environment(\.colorScheme) private var systemScheme

    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?
    @State private var typeAheadBuffer = ""
    @State private var typeAheadAt = Date.distantPast

    private let splitterWidth: CGFloat = 5

    init(seed: WindowSeed?, shared app: AppModel) {
        _windowModel = StateObject(wrappedValue: WindowModel(app: app))
    }

    var body: some View {
        withDialogs(
            rootContent
                .onAppear {
                    theme.scheme = systemScheme
                    installMonitors()
                    if windowModel.terminalVisible {
                        terminal.launchIfNeeded(cwd: windowModel.activeTab.currentFolderURL)
                    }
                }
                .onChange(of: windowModel.terminalVisible) { visible in
                    if visible {
                        terminal.launchIfNeeded(cwd: windowModel.activeTab.currentFolderURL)
                    }
                }
                .onDisappear {
                    removeMonitors()
                    QuickLook.dismissIfVisible()
                    terminal.terminate()
                }
                .onChange(of: systemScheme) { theme.scheme = $0 }
                .onReceive(NotificationCenter.default.publisher(for: .explorerrOpenInNewTab)) { note in
                    if let loc = note.object as? Location {
                        windowModel.activePane.controller.addTab(loc)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .explorerrToggleDualPane)) { _ in
                    windowModel.toggleDualPane()
                }
                .onReceive(NotificationCenter.default.publisher(for: .explorerrZoomWindow)) { _ in
                    chrome.toggleZoom()
                }
                .onReceive(NotificationCenter.default.publisher(for: .explorerrToggleTerminalPane)) { _ in
                    windowModel.terminalVisible.toggle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .explorerrNavigated)) { note in
                    if let sender = note.object as? TabState {
                        windowModel.mirrorNavigation(sender: sender, location: sender.location)
                    }
                }
                .focusedSceneValue(\.explorerWindow, windowModel)
        )
    }

    private var rootContent: some View {
        ZStack(alignment: .topLeading) {
            VisualEffectBlur(material: .underWindowBackground, blending: .behindWindow)

            GeometryReader { geo in
                let sizes = paneSizes(total: geo.size.width)

                VStack(spacing: 0) {
                    // Titlebar strip: one tab strip per pane + window controls
                    HStack(spacing: 0) {
                        // Match the content row's leading NavigationPane so tab strips align with their panes.
                        Color.clear
                            .frame(width: app.navWidth)
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(themeDivider).frame(width: 1).padding(.vertical, 7)
                            }

                        ForEach(Array(windowModel.panes.enumerated()), id: \.element.id) { idx, pane in
                            let isLast = idx == windowModel.panes.count - 1
                            PaneTabStrip(
                                controller: pane.controller,
                                isPaneActive: pane.id == windowModel.activePaneID,
                                isLastPane: isLast
                            )
                            // The last strip gives up room for the caption buttons so the
                            // whole row fits the window instead of overflowing off-screen.
                            .frame(width: isLast ? max(60, sizes.paneWidths[idx] - windowControlsReserve) : sizes.paneWidths[idx])
                            .background(
                                GeometryReader { g in
                                    Color.clear.preference(key: StripFrameKey.self, value: [pane.id: g.frame(in: .named("win"))])
                                }
                            )
                            .overlay(alignment: .trailing) {
                                if !isLast {
                                    Rectangle().fill(themeDivider).frame(width: 1).padding(.vertical, 7)
                                }
                            }
                        }
                        Spacer(minLength: 4)
                        WindowControls(chrome: chrome)
                    }

                    HStack(spacing: 0) {
                        NavigationPane(tab: windowModel.activeTab, app: app)
                        NavResizeDivider()

                        ForEach(Array(windowModel.panes.enumerated()), id: \.element.id) { idx, pane in
                            paneColumn(pane)
                                .frame(width: sizes.paneWidths[idx])

                            if idx < windowModel.panes.count - 1 {
                                PaneSplitter(
                                    onDrag: { delta in
                                        windowModel.dragSplitter(
                                            index: idx,
                                            deltaPixels: delta,
                                            availableWidth: sizes.available
                                        )
                                    }
                                )
                                .frame(width: splitterWidth)
                            }
                        }
                    }

                    if windowModel.terminalVisible {
                        TerminalResizeDivider(onDrag: { delta in
                            windowModel.terminalHeight = min(640, max(120, windowModel.terminalHeight - delta))
                        })
                        TerminalPanelView(
                            controller: terminal,
                            currentFolder: { [weak windowModel] in
                                windowModel?.activeTab.currentFolderURL
                            },
                            onClose: { windowModel.terminalVisible = false }
                        )
                        .frame(height: CGFloat(windowModel.terminalHeight))
                        .padding(.horizontal, 1)
                    }
                }
            }
            .environmentObject(theme)

            MenuHost()
        }
        .coordinateSpace(name: "win")
        .onPreferenceChange(TabFrameKey.self) { [weak windowModel] frames in
            windowModel?.tabFrames = frames
        }
        .onPreferenceChange(StripFrameKey.self) { [weak windowModel] frames in
            windowModel?.stripFrames = frames
        }
        .frame(minWidth: Win11.Metrics.windowMinWidth, minHeight: Win11.Metrics.windowMinHeight)
        .background(WindowConfigurator())
        .background(WindowAccessor(state: chrome))
        .environmentObject(theme)
    }

    private var themeDivider: Color { Win11.palette(theme.scheme).divider }

    /// Width the caption buttons need at the trailing end of the titlebar row (3 × 46 + spacer).
    private let windowControlsReserve: CGFloat = 142

    /// Pane column widths from the weight distribution.
    private func paneSizes(total: CGFloat) -> (paneWidths: [CGFloat], available: CGFloat) {
        let count = windowModel.panes.count
        let available = max(60, total - app.navWidth - splitterWidth * CGFloat(max(0, count - 1)) - 1)
        let totalWeight = windowModel.panes.reduce(0.0) { $0 + $1.weight }
        let widths = windowModel.panes.map { available * CGFloat($0.weight / totalWeight) }
        return (widths, available)
    }

    // MARK: pane column

    private func paneColumn(_ pane: PaneModel) -> some View {
        let p = Win11.palette(theme.scheme)
        let tab = pane.controller.active
        let isActive = pane.id == windowModel.activePaneID

        return VStack(spacing: 0) {
            CommandBar(tab: tab, app: app)
            AddressBar(tab: tab, app: app)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    contentRouter(tab)
                    if isActive && app.prefs.showDetailsPane {
                        DetailsPaneView(tab: tab, app: app)
                    }
                }
                if app.prefs.statusVisible {
                    StatusBar(tab: tab, app: app)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TopLeftRoundedShape(radius: 8).fill(p.contentBG))
            .clipShape(TopLeftRoundedShape(radius: 8))
            .overlay(
                TopLeftRoundedShape(radius: 8)
                    .stroke(isActive ? p.selectionBorder : p.stroke, lineWidth: 1)
                    .allowsHitTesting(false)
            )
        }
        .opacity(isActive ? 1 : 0.88)
        .background(
            GeometryReader { g in
                Color.clear.preference(key: PaneFrameKey.self, value: [pane.id: g.frame(in: .named("win"))])
            }
        )
        .onPreferenceChange(PaneFrameKey.self) { frames in
            windowModel.paneFrames.merge(frames) { _, new in new }
        }
    }

    @ViewBuilder
    private func contentRouter(_ tab: TabState) -> some View {
        switch tab.location {
        case .folder: FolderContentView(tab: tab, app: app)
        case .home: HomeView(tab: tab, app: app)
        case .thisPC: ThisPCView(tab: tab, app: app)
        case .gallery: GalleryView(tab: tab, app: app)
        case .trash: TrashView(tab: tab, app: app)
        case .network: NetworkView(tab: tab, app: app)
        }
    }

    // MARK: dialogs

    private func withDialogs<V: View>(_ content: V) -> some View {
        content
            .sheet(isPresented: Binding(get: { app.activeSheet != nil }, set: { if !$0 { app.activeSheet = nil } })) {
                sheetContent
                    .environmentObject(theme)
                    .environmentObject(app)
                    .environmentObject(app.menuCoordinator)
            }
            .alert(item: Binding(get: { app.confirm }, set: { app.confirm = $0 })) { request in
                confirmAlert(request)
            }
            .alert(
                "Explorerr",
                isPresented: Binding(get: { app.lastError != nil }, set: { if !$0 { app.lastError = nil } }),
                presenting: app.lastError
            ) { _ in
                Button("OK") { app.lastError = nil }
            } message: { msg in
                Text(msg)
            }
    }

    private func confirmAlert(_ request: ConfirmRequest) -> Alert {
        let primary: Alert.Button = request.destructive
            ? .destructive(Text(request.confirmLabel), action: request.action)
            : .default(Text(request.confirmLabel), action: request.action)
        return Alert(
            title: Text(request.title),
            message: Text(request.message),
            primaryButton: primary,
            secondaryButton: .cancel(Text(request.cancelLabel))
        )
    }

    @ViewBuilder
    private var sheetContent: some View {
        if let sheet = app.activeSheet {
            switch sheet {
            case .conflict(let ctx): ConflictSheet(context: ctx, app: app)
            case .progress(let progress): ProgressSheet(progress: progress, app: app)
            case .properties(let url): PropertiesSheet(url: url, app: app)
            case .about: AboutSheet()
            case .shortcuts: ShortcutsSheet()
            case .emptyTrash: EmptyTrashSheet(app: app)
            case .restorePick: EmptyTrashSheet(app: app) // unused; placeholder
            }
        }
    }

    // MARK: keyboard (Windows muscle-memory + commander pane keys)

    private func installMonitors() {
        guard keyMonitor == nil else { return }

        // Pane activation, middle-click (close tab / open folder in new tab) and
        // mouse back/forward buttons (Windows mice).
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak windowModel, weak chrome] event in
            guard let model = windowModel, let window = event.window else { return event }
            // Monitors are app-wide: only handle events for this window (not sheets,
            // panels or other Explorerr windows).
            guard window === chrome?.window else { return event }
            // AppKit window coords are bottom-left origin; the "win" preference frames
            // are top-left. Flip Y so hit-testing is exact everywhere, not just for
            // full-height columns.
            let height = window.contentView?.bounds.height ?? window.frame.height
            let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)

            // Middle click: close the tab under the cursor, or open the folder item
            // under the cursor in a background tab (Explorer/Dolphin/browsers).
            if event.type == .otherMouseDown, event.buttonNumber == 2 {
                for pane in model.panes {
                    if let hit = pane.controller.tabs.first(where: { model.tabFrames[$0.id]?.contains(point) == true }) {
                        pane.controller.closeTab(hit.id)
                        return nil
                    }
                }
                for pane in model.panes {
                    let tab = pane.controller.active
                    guard case .folder = tab.location, tab.contentClipInWin.contains(point) else { continue }
                    let origin = tab.contentOriginInWin
                    if let id = tab.itemFrames.first(where: { $0.value.offsetBy(dx: origin.x, dy: origin.y).contains(point) })?.key,
                       let item = tab.sortedItems.first(where: { $0.id == id }), item.isDirectory {
                        pane.controller.addTab(.folder(item.url), activate: false)
                        return nil
                    }
                    break
                }
            }

            if model.panes.count > 1 {
                for pane in model.panes {
                    let inColumn = model.paneFrames[pane.id]?.contains(point) == true
                    let inStrip = model.stripFrames[pane.id]?.contains(point) == true
                    if inColumn || inStrip {
                        model.activate(paneID: pane.id)
                        break
                    }
                }
            }

            if event.type == .otherMouseDown {
                if event.buttonNumber == 3 { model.activeTab.goBack(); return nil }
                if event.buttonNumber == 4 { model.activeTab.goForward(); return nil }
            }
            return event
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak windowModel, weak app, weak chrome] event in
            guard let model = windowModel, let app else { return event }
            // Only handle keys for this window (monitors are app-wide; ⌘N windows and
            // the Quick Look panel install/receive their own events).
            guard event.window == nil || event.window === chrome?.window else { return event }
            let tab = model.activeTab

            // Don't interfere with text editing (rename, path editor, search)
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }

            // Escape: close dropdowns, then cancel search, then clear selection (Explorer order)
            if event.keyCode == 53 {
                if app.menuCoordinator.request != nil {
                    app.menuCoordinator.dismiss()
                    return nil
                }
                if tab.isSearching {
                    tab.clearSearch()
                    return nil
                }
                if !tab.selection.isEmpty {
                    tab.clearSelection()
                    return nil
                }
                return event
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Command-key shortcuts are handled by the menu bar; skip here
            if mods.contains(.command) { return event }

            // Windows navigation keys
            if mods.contains(.option) {
                switch event.keyCode {
                case 123: tab.goBack(); return nil
                case 124: tab.goForward(); return nil
                case 126: tab.goUp(); return nil
                default: return event
                }
            }

            // ⇧+arrows extend the selection from the anchor (Explorer/Finder)
            if mods.contains(.shift) {
                switch event.keyCode {
                case 123: if arrowMove(tab, .left, extend: true) { return nil }; return event
                case 124: if arrowMove(tab, .right, extend: true) { return nil }; return event
                case 125:
                    if arrowMove(tab, .down, extend: true) { return nil }
                    tab.extendSelection(delta: 1)
                    return nil
                case 126:
                    if arrowMove(tab, .up, extend: true) { return nil }
                    tab.extendSelection(delta: -1)
                    return nil
                default: break
                }
            }

            switch event.keyCode {
            case 120: // F2 rename
                if tab.selection.count == 1, let id = tab.selection.first {
                    tab.renamingID = id
                    return nil
                }
                return event
            case 96: // F5: refresh — or "copy to other pane" in multi-pane (commander keys)
                if model.panes.count > 1 {
                    if transferToOtherPane(move: false, model: model, app: app) { return nil }
                    return event
                }
                tab.reload()
                return nil
            case 97: // F6: move to other pane (multi-pane commander)
                if model.panes.count > 1, transferToOtherPane(move: true, model: model, app: app) {
                    return nil
                }
                return event
            case 118: // F4 → toggle the integrated terminal (Dolphin)
                model.terminalVisible.toggle()
                return nil
            case 51: // Backspace (delete key on Mac keyboards)
                if mods.contains(.shift) || mods.contains(.command) {
                    let items = tab.selectedItems
                    if !items.isEmpty {
                        Task { await FileOps.deleteItems(items, app: app) }
                        return nil
                    }
                } else if tab.currentFolderURL != nil {
                    tab.goUp()   // Windows: Backspace goes up
                    return nil
                }
                return event
            case 117: // fn+Delete (forward delete)
                let items = tab.selectedItems
                if !items.isEmpty {
                    Task { await FileOps.deleteItems(items, app: app) }
                    return nil
                }
                return event
            case 49: // Space → Quick Look (Finder parity)
                let previewable = tab.selectedItems.filter { !$0.isDirectory }
                if !previewable.isEmpty {
                    QuickLook.toggle(items: previewable)
                    return nil
                }
                return event
            case 36, 76: // Return · ⌥↩ = Properties (Windows Alt+Enter)
                if mods.contains(.option) {
                    if let sel = tab.selectedItems.first {
                        app.activeSheet = .properties(sel.url)
                        return nil
                    } else if let dir = tab.currentFolderURL {
                        app.activeSheet = .properties(dir)
                        return nil
                    }
                    return event
                }
                if !tab.selection.isEmpty {
                    FileOps.openSelection(in: tab, app: app)
                    return nil
                }
                return event
            case 123: // Arrow left (grids/list: spatial; details: no-op)
                if arrowMove(tab, .left) { return nil }
                return event
            case 124: // Arrow right
                if arrowMove(tab, .right) { return nil }
                return event
            case 125: // Arrow down
                if arrowMove(tab, .down) { return nil }
                moveSelection(tab, delta: 1)
                return nil
            case 126: // Arrow up
                if arrowMove(tab, .up) { return nil }
                moveSelection(tab, delta: -1)
                return nil
            case 115: // Home → first item
                moveSelection(tab, delta: .min)
                return nil
            case 119: // End → last item
                moveSelection(tab, delta: .max)
                return nil
            case 116: // Page Up
                moveSelection(tab, delta: -15)
                return nil
            case 121: // Page Down
                moveSelection(tab, delta: 15)
                return nil
            default:
                // Type-ahead: typing letters/digits jumps to the matching item (Explorer/Finder/Dolphin)
                if handleTypeAhead(event, tab: tab, mods: mods) { return nil }
                return event
            }
        }
    }

    // MARK: type-ahead ("type to select")

    private func handleTypeAhead(_ event: NSEvent, tab: TabState, mods: NSEvent.ModifierFlags) -> Bool {
        guard mods.subtracting(.shift).isEmpty,
              let chars = event.charactersIgnoringModifiers, !chars.isEmpty,
              let scalar = chars.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value < 0xF700,   // printable, not a function key
              !tab.sortedItems.isEmpty
        else { return false }

        let now = Date()
        if now.timeIntervalSince(typeAheadAt) > 0.9 { typeAheadBuffer = "" }
        typeAheadAt = now
        typeAheadBuffer += chars.lowercased()

        let items = tab.sortedItems
        // Repeating one letter cycles through its matches; otherwise prefix-match from the top.
        let cycling = typeAheadBuffer.count > 1 && Set(typeAheadBuffer).count == 1
        let needle = cycling ? String(typeAheadBuffer.first!) : typeAheadBuffer
        var start = 0
        if cycling, tab.selection.count == 1, let id = tab.selection.first,
           let idx = items.firstIndex(where: { $0.id == id }) {
            start = idx + 1
        }
        for offset in 0..<items.count {
            let idx = (start + offset) % items.count
            if items[idx].displayName.lowercased().hasPrefix(needle) {
                tab.selection = [items[idx].id]
                tab.anchorIndex = idx
                tab.focusIndex = idx
                return true
            }
        }
        return true // consume even without a match, like Explorer
    }

    /// F5/F6 commander action: copy/move selection to the other pane's folder.
    private func transferToOtherPane(move: Bool, model: WindowModel, app: AppModel) -> Bool {
        let tab = model.activeTab
        let items = tab.selectedItems
        guard !items.isEmpty, let other = model.otherFolderPane,
              let dest = other.active.currentFolderURL else {
            app.toast(move ? "No folder pane to move to" : "No folder pane to copy to")
            return false
        }
        Task {
            await FileOps.transfer(items.map { $0.url }, to: dest, move: move, app: app, tab: tab)
        }
        return true
    }

    // MARK: spatial arrow navigation (grid-aware, uses the frames BandSelectable reports)

    /// Returns true when the event was handled (including a boundary no-op).
    /// Returns false only when spatial data is unavailable — callers fall back to
    /// linear movement (↑/↓) or pass the event through (←/→).
    private func arrowMove(_ tab: TabState, _ direction: BandSelect.Direction, extend: Bool = false) -> Bool {
        let items = tab.sortedItems
        guard !items.isEmpty else { return false }

        func apply(_ idx: Int) {
            if extend {
                tab.extendSelection(to: idx)
            } else {
                tab.selection = [items[idx].id]
                tab.anchorIndex = idx
                tab.focusIndex = idx
            }
        }

        // Nothing focused yet: ↓/→ start at the first item, ↑/← at the last (Explorer).
        guard let currentIdx = focusedIndex(tab, items: items) else {
            apply(direction == .down || direction == .right ? 0 : items.count - 1)
            return true
        }

        let currentID = items[currentIdx].id
        guard tab.itemFrames[currentID] != nil else { return false }

        if let targetID = BandSelect.spatialMove(from: currentID, frames: tab.itemFrames, direction: direction),
           let targetIdx = items.firstIndex(where: { $0.id == targetID }) {
            apply(targetIdx)
            return true
        }

        // Boundary. Grid views wrap ←/→ linearly onto the previous/next row (Explorer).
        if tab.viewMode.isGrid, direction == .left || direction == .right {
            let next = currentIdx + (direction == .right ? 1 : -1)
            if items.indices.contains(next) {
                apply(next)
                return true
            }
        }
        return true // edge of the layout: consume without moving
    }

    private func focusedIndex(_ tab: TabState, items: [FSItem]) -> Int? {
        if let f = tab.focusIndex, items.indices.contains(f) { return f }
        if tab.selection.count == 1, let id = tab.selection.first {
            return items.firstIndex { $0.id == id }
        }
        return nil
    }

    /// Move the single selection by `delta` rows; `.min`/`.max` jump to first/last (Home/End).
    private func moveSelection(_ tab: TabState, delta: Int) {
        let items = tab.sortedItems
        guard !items.isEmpty else { return }
        let next: Int
        if delta == .min {
            next = 0
        } else if delta == .max {
            next = items.count - 1
        } else {
            let current: Int
            if tab.selection.count == 1, let id = tab.selection.first,
               let idx = items.firstIndex(where: { $0.id == id }) {
                current = idx
            } else {
                current = delta > 0 ? -1 : 0
            }
            next = max(0, min(items.count - 1, current + delta))
        }
        tab.selection = [items[next].id]
        tab.anchorIndex = next
        tab.focusIndex = next
    }

    private func removeMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }
}

// MARK: - Pane frame preference

struct PaneFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Window-space frames of each pane's titlebar tab strip.
struct StripFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Pane splitter

struct PaneSplitter: View {
    let onDrag: (Double) -> Void
    @EnvironmentObject var theme: Theme
    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        let p = Win11.palette(theme.scheme)
        Rectangle()
            .fill(hovering || dragging ? p.selectionBorder : p.divider)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        dragging = true
                        onDrag(Double(value.translation.width))
                    }
                    .onEnded { _ in dragging = false }
            )
            .onHover { h in
                hovering = h
                if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }
}

// MARK: - Terminal panel resize divider

struct TerminalResizeDivider: View {
    let onDrag: (Double) -> Void
    @EnvironmentObject var theme: Theme
    @State private var hovering = false
    @State private var dragging = false
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        let p = Win11.palette(theme.scheme)
        Rectangle()
            .fill(hovering || dragging ? p.selectionBorder : p.divider)
            .frame(height: 5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle().inset(by: -3))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        dragging = true
                        let delta = value.translation.height - lastTranslation
                        lastTranslation = value.translation.height
                        onDrag(Double(delta))
                    }
                    .onEnded { _ in
                        dragging = false
                        lastTranslation = 0
                    }
            )
            .onHover { h in
                hovering = h
                if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
    }
}

// MARK: - Nav pane resize divider

struct NavResizeDivider: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @State private var hovering = false

    var body: some View {
        let p = Win11.palette(theme.scheme)
        Rectangle()
            .fill(hovering ? p.strokeStrong : p.divider)
            .frame(width: hovering ? 3 : 1.5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle().inset(by: -3))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let proposed = app.navWidth + value.translation.width
                        app.navWidth = min(Win11.Metrics.navPaneMaxWidth, max(Win11.Metrics.navPaneMinWidth, proposed))
                    }
            )
            .onHover { h in
                hovering = h
                if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }
}

// MARK: - Focused values (menu commands → active window)

struct ExplorerWindowKey: FocusedValueKey { typealias Value = WindowModel }

extension FocusedValues {
    var explorerWindow: WindowModel? {
        get { self[ExplorerWindowKey.self] }
        set { self[ExplorerWindowKey.self] = newValue }
    }
}
