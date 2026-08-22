import SwiftUI
import AppKit

// MARK: - NSWindow configuration (Win11-style: no macOS titlebar chrome)

struct WindowConfigurator: NSViewRepresentable {
    final class Coordinator { var configured = false }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { configure(v.window, context: context) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView.window, context: context)
    }

    private func configure(_ window: NSWindow?, context: Context) {
        guard let w = window, !context.coordinator.configured else { return }
        context.coordinator.configured = true
        w.styleMask.insert(.fullSizeContentView)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = false
        w.backgroundColor = .clear
        w.isOpaque = false
        w.standardWindowButton(.closeButton)?.superview?.isHidden = true
        w.animationBehavior = .documentWindow
    }
}

// MARK: - Window chrome state (zoom / minimize / close)

@MainActor
final class WindowChromeState: ObservableObject {
    @Published var isZoomed = false
    var savedFrame: NSRect?
    weak var window: NSWindow?

    func attach(_ w: NSWindow) {
        if window == nil { window = w }
    }

    func toggleZoom() {
        guard let w = window else { return }
        if isZoomed {
            if let f = savedFrame { w.setFrame(f, display: true, animate: false) }
            isZoomed = false
        } else {
            savedFrame = w.frame
            if let target = (w.screen ?? NSScreen.main)?.visibleFrame {
                w.setFrame(target, display: true, animate: false)
            }
            isZoomed = true
        }
    }

    func minimize() { window?.performMiniaturize(nil) }
    func close() { window?.close() }
}

struct WindowAccessor: NSViewRepresentable {
    @ObservedObject var state: WindowChromeState

    final class AccessorView: NSView {
        weak var chrome: WindowChromeState?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let w = window { chrome?.attach(w) }
        }
    }

    func makeNSView(context: Context) -> NSView {
        let v = AccessorView()
        v.chrome = state
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? AccessorView)?.chrome = state
        if let w = nsView.window { state.attach(w) }
    }
}

// MARK: - Windows caption buttons (minimize / maximize / close)

struct WindowControls: View {
    @ObservedObject var chrome: WindowChromeState
    @Environment(\.controlActiveState) private var activeState
    @EnvironmentObject var theme: Theme

    var body: some View {
        HStack(spacing: 0) {
            captionButton(symbol: .minimize, hoverBG: Win11.palette(theme.scheme).controlFillHover, action: { chrome.minimize() })
            captionButton(symbol: chrome.isZoomed ? .restore : .maximize, hoverBG: Win11.palette(theme.scheme).controlFillHover, action: { chrome.toggleZoom() })
            captionButton(symbol: .close, hoverBG: Win11.palette(theme.scheme).danger, action: { chrome.close() })
        }
        .frame(height: Win11.Metrics.tabStripHeight)
    }

    private enum CapSymbol { case minimize, maximize, restore, close }

    private func captionButton(symbol: CapSymbol, hoverBG: Color, action: @escaping () -> Void) -> some View {
        CaptionButton(symbol: symbol, hoverBG: hoverBG, active: activeState != .inactive, action: action)
    }

    private struct CaptionButton: View {
        let symbol: CapSymbol
        let hoverBG: Color
        let active: Bool
        let action: () -> Void
        @State private var hovering = false
        @EnvironmentObject var theme: Theme

        var body: some View {
            ZStack {
                Rectangle().fill(hovering ? hoverBG : .clear)
                glyph
                    .foregroundStyle(glyphColor)
            }
            .frame(width: 46)
            .contentShape(Rectangle())
            .onHover { h in
                hovering = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture { action() }
            .accessibilityLabel(accessibilityText)
        }

        private var accessibilityText: String {
            switch symbol {
            case .minimize: return "Minimize"
            case .maximize: return "Maximize"
            case .restore: return "Restore"
            case .close: return "Close"
            }
        }

        private var glyphColor: Color {
            let p = Win11.palette(theme.scheme)
            let base: Color = symbol == .close && hovering ? .white : p.textPrimary
            return active ? base : p.textDisabled
        }

        @ViewBuilder
        private var glyph: some View {
            switch symbol {
            case .minimize:
                Capsule().frame(width: 10, height: 1.4)
            case .maximize:
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .strokeBorder(lineWidth: 1.2)
                    .frame(width: 10.5, height: 10.5)
            case .restore:
                ZStack {
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                        .strokeBorder(lineWidth: 1.1)
                        .frame(width: 8.5, height: 8.5)
                        .offset(x: 2.6, y: -2.6)
                    Rectangle().frame(width: 8.5, height: 2.2).offset(x: -2.0, y: -5.2).opacity(0) // keep size
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                        .strokeBorder(lineWidth: 1.1)
                        .frame(width: 8.5, height: 8.5)
                        .offset(x: -2.6, y: 2.6)
                        .background(
                            RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                                .frame(width: 8.5, height: 8.5)
                                .offset(x: -2.6, y: 2.6)
                                .foregroundStyle(hovering ? hoverBG : Color.clear)
                                .opacity(0)
                        )
                }
                .frame(width: 14, height: 14)
            case .close:
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 10, y: 10))
                        p.move(to: CGPoint(x: 10, y: 0)); p.addLine(to: CGPoint(x: 0, y: 10))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 10.5, height: 10.5)
                }
            }
        }
    }
}

// MARK: - Drag region (tab strip background moves the window)

struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func draw(_ dirtyRect: NSRect) {}
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Mica-like backdrop

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? NSVisualEffectView)?.material = material
    }
}
