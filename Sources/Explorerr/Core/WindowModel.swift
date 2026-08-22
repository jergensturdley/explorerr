import Foundation
import AppKit

/// One pane inside a window: its own tab controller + relative width weight.
struct PaneModel: Identifiable {
    let id = UUID()
    let controller: TabController
    var weight: Double = 1.0
}

struct PaneLayout: Codable {
    var locations: [Location]
    var activeTab: Int
}

struct SessionLayout: Codable {
    var panes: [PaneLayout]
    var activePane: Int
    var weights: [Double]?
    var syncPanes: Bool? = nil
    var terminalVisible: Bool? = nil
    var terminalHeight: Double? = nil
}

/// Per-window layout: 1–3 side-by-side panes (OneCommander-style multi-pane),
/// each with independent tabs, plus the active pane used for keyboard commands.
@MainActor
final class WindowModel: ObservableObject {
    static let maxPanes = 3
    static let registry = NSHashTable<WindowModel>.weakObjects()

    @Published var panes: [PaneModel]
    @Published var activePaneID: UUID
    /// Dolphin-style "navigate panes together": navigation in one pane mirrors to the others.
    @Published var syncPanes: Bool = false {
        didSet { app.layoutChanged() }
    }
    /// Integrated terminal panel (Dolphin F4).
    @Published var terminalVisible: Bool = false {
        didSet { app.layoutChanged() }
    }
    @Published var terminalHeight: Double = 260 {
        didSet { app.layoutChanged() }
    }
    private var isMirroring = false

    let app: AppModel

    /// Window-space frames of pane columns (for hit-testing clicks into panes). Not published.
    var paneFrames: [UUID: CGRect] = [:]

    init(app: AppModel) {
        self.app = app

        if !AppModel.sessionRestoreDone, let layout = Store.loadSessionLayout() {
            AppModel.sessionRestoreDone = true
            var restored: [PaneModel] = []
            for (idx, paneLayout) in layout.panes.enumerated() {
                let clampedActive = min(max(0, paneLayout.activeTab), paneLayout.locations.count - 1)
                let controller = TabController(
                    app: app,
                    locations: paneLayout.locations.isEmpty ? [.home] : paneLayout.locations,
                    activeIndex: paneLayout.locations.isEmpty ? 0 : clampedActive
                )
                let w = layout.weights?[idx] ?? 1.0
                restored.append(PaneModel(controller: controller, weight: max(0.15, w)))
            }
            if restored.isEmpty { restored = [PaneModel(controller: TabController(app: app, location: .home), weight: 1)] }
            let activeIdx = min(max(0, layout.activePane), restored.count - 1)
            let active = restored[activeIdx].id
            syncPanes = layout.syncPanes ?? false
            terminalVisible = layout.terminalVisible ?? false
            if let h = layout.terminalHeight { terminalHeight = min(600, max(120, h)) }
            panes = restored
            activePaneID = active
        } else {
            AppModel.sessionRestoreDone = true
            let first = app.prefs.startupHome ? Location.home : .folder(DirectoryLoader.homeURL)
            let initial = [PaneModel(controller: TabController(app: app, location: first), weight: 1)]
            panes = initial
            activePaneID = initial[0].id
        }
        Self.registry.add(self)
        app.layoutChanged()
    }

    // MARK: accessors

    var activePane: PaneModel { panes.first { $0.id == activePaneID } ?? panes[0] }
    var activeTab: TabState { activePane.controller.active }
    var paneCount: Int { panes.count }
    var isMultiPane: Bool { panes.count > 1 }

    // MARK: pane management

    func addPane(location: Location = .home) {
        guard panes.count < Self.maxPanes else { return }
        let pane = PaneModel(controller: TabController(app: app, location: location), weight: 1)
        panes.append(pane)
        activePaneID = pane.id
        equalizeWeights()
        app.layoutChanged()
    }

    func removePane(id: UUID) {
        guard panes.count > 1, let idx = panes.firstIndex(where: { $0.id == id }) else { return }
        panes.remove(at: idx)
        if activePaneID == id {
            activePaneID = panes[min(idx, panes.count - 1)].id
        }
        equalizeWeights()
        app.layoutChanged()
    }

    /// Toggle the classic dual-pane layout (OneCommander-style).
    func toggleDualPane() {
        if panes.count > 1 {
            // Collapse: keep only the active pane
            let keep = panes.firstIndex { $0.id == activePaneID } ?? 0
            panes = [panes[keep]]
            panes[0].weight = 1
        } else {
            addPane()
        }
        app.layoutChanged()
    }

    func closeActivePane() {
        removePane(id: activePaneID)
    }

    func focusPane(advance: Int) {
        guard panes.count > 1, let idx = panes.firstIndex(where: { $0.id == activePaneID }) else { return }
        let next = (idx + advance + panes.count) % panes.count
        activePaneID = panes[next].id
        app.layoutChanged()
    }

    func activate(paneID: UUID) {
        guard panes.contains(where: { $0.id == paneID }), paneID != activePaneID else { return }
        activePaneID = paneID
        objectWillChange.send()
    }

    /// First non-active pane that is browsing a folder (target for F5/F6).
    var otherFolderPane: TabController? {
        for pane in panes where pane.id != activePaneID {
            if pane.controller.active.currentFolderURL != nil { return pane.controller }
        }
        return nil
    }

    // MARK: weights

    private func equalizeWeights() {
        guard !panes.isEmpty else { return }
        let w = 1.0 / Double(panes.count)
        for i in panes.indices { panes[i].weight = w }
    }

    /// Drag a splitter between pane `index` and `index+1` by `deltaPixels` of available width.
    func dragSplitter(index: Int, deltaPixels: Double, availableWidth: Double) {
        guard panes.indices.contains(index), panes.indices.contains(index + 1), availableWidth > 24 else { return }
        let totalWeight = panes.reduce(0) { $0 + $1.weight }
        let deltaWeight = deltaPixels / availableWidth * totalWeight
        let minWeight = totalWeight * 0.18
        let a = panes[index].weight, b = panes[index + 1].weight
        var da = deltaWeight
        da = max(da, minWeight - a)          // don't shrink below min
        da = min(da, b - minWeight)          // don't shrink the other below min
        panes[index].weight = a + da
        panes[index + 1].weight = b - da
    }

    /// Mirror a navigation from one pane's tab into every other pane's active tab.
    func mirrorNavigation(sender: TabState, location: Location) {
        guard syncPanes, panes.count > 1, !isMirroring else { return }
        let senderPane = panes.first { $0.controller.tabs.contains { $0 === sender } }
        isMirroring = true
        for pane in panes where pane.id != senderPane?.id {
            pane.controller.active.navigate(location, addHistory: true)
        }
        isMirroring = false
    }

    // MARK: session

    func saveSession() {
        let layouts = panes.map { pane in
            PaneLayout(
                locations: pane.controller.tabs.map { $0.location },
                activeTab: pane.controller.tabs.firstIndex { $0.id == pane.controller.activeID } ?? 0
            )
        }
        let activeIdx = panes.firstIndex { $0.id == activePaneID } ?? 0
        Store.saveSessionLayout(SessionLayout(
            panes: layouts,
            activePane: activeIdx,
            weights: panes.map { $0.weight },
            syncPanes: syncPanes,
            terminalVisible: terminalVisible,
            terminalHeight: terminalHeight
        ))
    }
}

extension Notification.Name {
    static let explorerrNavigated = Notification.Name("explorerr.navigated")
}
