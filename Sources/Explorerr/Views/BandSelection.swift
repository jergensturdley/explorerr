import SwiftUI
import AppKit

// MARK: - Rubber-band (marquee) selection
//
// Mechanism: every item reports its frame in the scroll content's named coordinate
// space; a clear catcher layer sits BEHIND the items, so a click-drag that starts on
// empty space draws the band while a drag that starts on an item still hit-tests the
// item (file drag). Selection updates live as the band grows.
// ponytail: no autoscroll while banding — the band covers what's on screen; add
// NSScrollView autoscroll if selecting past the viewport ever matters.

/// Pure band math, kept separate so --selftest can exercise it.
enum BandSelect {
    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func hits(frames: [String: CGRect], rect: CGRect) -> Set<String> {
        Set(frames.filter { $0.value.intersects(rect) }.keys)
    }

    // MARK: spatial arrow navigation (grid-aware, driven by the same reported frames)

    enum Direction { case up, down, left, right }

    /// Nearest item in `direction` from `id`: minimal travel along the axis (within a
    /// tolerance bucket, so a whole grid row competes), then minimal cross-axis offset.
    /// nil when `id` has no frame or nothing lies in that direction (boundary).
    static func spatialMove(from id: String, frames: [String: CGRect], direction: Direction) -> String? {
        guard let c = frames[id] else { return nil }
        var candidates: [(id: String, primary: CGFloat, secondary: CGFloat)] = []
        for (fid, f) in frames where fid != id {
            let dx = f.midX - c.midX
            let dy = f.midY - c.midY
            switch direction {
            case .down: if dy > 0.5 { candidates.append((fid, dy, abs(dx))) }
            case .up: if dy < -0.5 { candidates.append((fid, -dy, abs(dx))) }
            case .right: if dx > 0.5 { candidates.append((fid, dx, abs(dy))) }
            case .left: if dx < -0.5 { candidates.append((fid, -dx, abs(dy))) }
            }
        }
        guard let minPrimary = candidates.map({ $0.primary }).min() else { return nil }
        let vertical = direction == .up || direction == .down
        let tolerance = (vertical ? c.height : c.width) * 0.6
        return candidates
            .filter { $0.primary <= minPrimary + tolerance }
            .min { $0.secondary != $1.secondary ? $0.secondary < $1.secondary : $0.primary < $1.primary }?
            .id
    }
}

struct BandFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private let bandSpace = "explorerr.bandspace"

/// Attach to each selectable item so the band knows where it is.
struct ReportsBandFrame: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { g in
                Color.clear.preference(key: BandFramesKey.self, value: [id: g.frame(in: .named(bandSpace))])
            }
        )
    }
}

/// Attach to the scroll CONTENT of an item view (Details/Icons/Tiles/List/Gallery).
struct BandSelectable: ViewModifier {
    @ObservedObject var tab: TabState
    @EnvironmentObject var theme: Theme

    @State private var frames: [String: CGRect] = [:]
    @State private var bandOrigin: CGPoint? = nil
    @State private var bandRect: CGRect? = nil
    @State private var baseSelection: Set<String> = []

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: bandSpace)
            .onPreferenceChange(BandFramesKey.self) {
                frames = $0
                tab.itemFrames = $0   // shared with keyboard spatial navigation
            }
            .background(catcher)
            .overlay(alignment: .topLeading) { bandOverlay }
    }

    // Clear layer behind the items: only presses on empty space reach it.
    private var catcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(bandSpace))
                    .onChanged { value in
                        if bandOrigin == nil {
                            bandOrigin = value.startLocation
                            // ⌘/⇧ band adds to the existing selection (Explorer)
                            let mods = NSEvent.modifierFlags
                            baseSelection = (mods.contains(.command) || mods.contains(.shift)) ? tab.selection : []
                            tab.renamingID = nil
                            tab.isBandSelecting = true
                        }
                        let r = BandSelect.rect(from: bandOrigin ?? value.startLocation, to: value.location)
                        bandRect = r
                        let newSelection = baseSelection.union(BandSelect.hits(frames: frames, rect: r))
                        if newSelection != tab.selection { tab.selection = newSelection }
                    }
                    .onEnded { _ in
                        bandOrigin = nil
                        bandRect = nil
                        baseSelection = []
                        tab.isBandSelecting = false
                    }
            )
    }

    @ViewBuilder
    private var bandOverlay: some View {
        if let r = bandRect {
            let p = Win11.palette(theme.scheme)
            Rectangle()
                .fill(p.accent.opacity(0.13))
                .overlay(Rectangle().strokeBorder(p.accent.opacity(0.6), lineWidth: 1))
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
                .allowsHitTesting(false)
        }
    }
}
