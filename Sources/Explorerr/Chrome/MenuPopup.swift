import SwiftUI

// MARK: - Anchor preference (window coordinate space "win")

struct MenuAnchorKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

// MARK: - Menu host (overlay at window root)

struct MenuHost: View {
    @EnvironmentObject var coord: MenuCoordinator
    @EnvironmentObject var theme: Theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let req = coord.request {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { coord.dismiss() }
                        .onTapGesture(count: 2) { coord.dismiss() }

                    // Top-left corner of the panel. `.position` places a view's CENTER,
                    // so add half the (known) panel size. Clamp so it never spills off-screen.
                    let panelHeight = MenuPanelView.height(for: req.entries)
                    let left = min(max(6, req.anchor.minX), max(6, geo.size.width - req.width - 6))
                    let top = max(6, min(req.anchor.maxY + 4, geo.size.height - panelHeight - 6))

                    MenuPanelView(entries: req.entries, width: req.width, originX: left, windowWidth: geo.size.width, onDismiss: { coord.dismiss() })
                        .id(req.id)
                        .position(
                            x: left + req.width / 2,
                            y: top + panelHeight / 2
                        )
                        .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(coord.request != nil)
    }
}

// MARK: - Menu panel

struct MenuPanelView: View {
    let entries: [WinMenuEntry]
    let width: CGFloat
    /// Window-space left edge of this panel (needed so nested submenus can flip).
    var originX: CGFloat = 0
    var windowWidth: CGFloat
    let onDismiss: () -> Void

    @EnvironmentObject var theme: Theme
    @State private var openChild: ChildPanel?
    @State private var hoverTask: Task<Void, Never>?

    struct ChildPanel: Identifiable {
        let id: UUID
        let entries: [WinMenuEntry]
        let flip: Bool
        let originX: CGFloat
    }

    private static let childWidth: CGFloat = 216

    /// Deterministic rendered height of a panel (rows are fixed-height, single-line).
    /// Used by `MenuHost` to position the panel's top-left corner without an async measure.
    static func height(for entries: [WinMenuEntry]) -> CGFloat {
        var h: CGFloat = 10 // .padding(.vertical, 5) × 2
        for e in entries {
            switch e.kind {
            case .separator: h += 11 // 1px rule + 5pt vertical padding × 2
            case .header: h += 24
            case .row: h += 30
            }
        }
        return h
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                switch entry.kind {
                case .separator:
                    Rectangle()
                        .fill(Win11.palette(theme.scheme).menuSeparator)
                        .frame(height: 1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                case .header(let text):
                    Text(text)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Win11.palette(theme.scheme).textSecondary)
                        .padding(.horizontal, 11)
                        .padding(.top, 7)
                        .padding(.bottom, 3)
                case .row(let row):
                    MenuRowView(row: row, width: width) {
                        if let children = row.children {
                            hoverTask?.cancel()
                            openChild = Self.makeChild(entry: entry, children: children, width: width, originX: originX, windowWidth: windowWidth)
                        } else {
                            onDismiss()
                            row.action?()
                        }
                    } onHoverChange: { hovering in
                        guard !row.disabled else { return }
                        hoverTask?.cancel()
                        if hovering {
                            if row.children != nil {
                                hoverTask = Task {
                                    try? await Task.sleep(nanoseconds: 130_000_000)
                                    guard !Task.isCancelled else { return }
                                    openChild = Self.makeChild(entry: entry, children: row.children ?? [], width: width, originX: originX, windowWidth: windowWidth)
                                }
                            } else {
                                openChild = nil
                            }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let child = openChild, child.id == entry.id {
                            MenuPanelView(entries: child.entries, width: Self.childWidth, originX: child.originX, windowWidth: windowWidth, onDismiss: onDismiss)
                                .fixedSize()
                                .offset(x: child.flip ? -(Self.childWidth + 4) : width + 4, y: -5)
                                .zIndex(10)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .frame(width: width, alignment: .leading)
        .background(Win11.palette(theme.scheme).menuBG)
        .clipShape(RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusMenu, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusMenu, style: .continuous)
                .strokeBorder(Win11.palette(theme.scheme).menuBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(theme.scheme == .dark ? 0.45 : 0.16), radius: 16, x: 0, y: 9)
        .fixedSize()
        .onDisappear { hoverTask?.cancel() }
    }

    /// Builds a child submenu, flipping it left when it would run off the window's
    /// right edge (the parent panel's window-space origin and widths are known here).
    private static func makeChild(entry: WinMenuEntry, children: [WinMenuEntry], width: CGFloat, originX: CGFloat, windowWidth: CGFloat) -> ChildPanel {
        let fitsRight = originX + width + 4 + childWidth <= windowWidth - 6
        let flip = !fitsRight
        let childOriginX = flip ? originX - childWidth - 4 : originX + width + 4
        return ChildPanel(id: entry.id, entries: children, flip: flip, originX: childOriginX)
    }
}

struct MenuRowView: View {
    let row: WinMenuEntry.Row
    let width: CGFloat
    let onAction: () -> Void
    let onHoverChange: (Bool) -> Void

    @EnvironmentObject var theme: Theme
    @State private var hovering = false

    var body: some View {
        let p = Win11.palette(theme.scheme)
        HStack(spacing: 9) {
            ZStack {
                if row.checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.textPrimary)
                } else if let icon = row.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(row.danger ? p.danger : p.textPrimary)
                }
            }
            .frame(width: 17)

            Text(row.label)
                .font(Win11.Fonts.menu)
                .foregroundStyle(row.danger ? p.danger : p.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 12)

            if let sc = row.shortcut {
                Text(sc)
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.textSecondary)
            }
            if row.children != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(p.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(hovering && !row.disabled ? p.menuHover : Color.clear)
        )
        .opacity(row.disabled ? 0.4 : 1)
        .contentShape(Rectangle())
        .onHover { h in
            hovering = h
            if !row.disabled { onHoverChange(h) }
        }
        .onTapGesture {
            guard !row.disabled else { return }
            onAction()
        }
    }
}

// MARK: - Trigger button that opens a Win11-style dropdown at itself

struct WinMenuButton<Label: View>: View {
    @EnvironmentObject var coord: MenuCoordinator
    let width: CGFloat
    var enabled: Bool = true
    let entries: [WinMenuEntry]
    @ViewBuilder let label: () -> Label

    @State private var anchor: CGRect = .zero

    var body: some View {
        Button {
            guard enabled else { return }
            coord.toggle(anchor: anchor, width: width, entries: entries)
        } label: {
            label()
                .contentShape(Rectangle())
        }
        .buttonStyle(WinIconButtonStyle(enabled: enabled))
        .background(
            GeometryReader { g in
                Color.clear.preference(key: MenuAnchorKey.self, value: g.frame(in: .named("win")))
            }
        )
        .onPreferenceChange(MenuAnchorKey.self) { anchor = $0 }
    }
}

// MARK: - Shared Win11 button styles

/// Icon-only command button: transparent, subtle rounded hover.
struct WinIconButtonStyle: ButtonStyle {
    var enabled: Bool = true
    var padding: CGFloat = 6.5

    func makeBody(configuration: Configuration) -> some View {
        WinIconButtonBody(configuration: configuration, enabled: enabled, padding: padding)
    }

    private struct WinIconButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let enabled: Bool
        let padding: CGFloat
        @EnvironmentObject var theme: Theme
        @State private var hovering = false

        var body: some View {
            let p = Win11.palette(theme.scheme)
            configuration.label
                .font(Win11.Fonts.commandButton)
                .foregroundStyle(enabled ? p.textPrimary : p.textDisabled)
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusControl, style: .continuous)
                        .fill(!enabled ? Color.clear : configuration.isPressed ? p.controlFillPressed : hovering ? p.controlFillHover : Color.clear)
                )
                .opacity(enabled ? 1 : 0.55)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// Standard Win11 secondary button (border + subtle fill), used by "New ▾" etc.
struct WinStandardButtonStyle: ButtonStyle {
    var enabled: Bool = true
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        WinStandardButtonBody(configuration: configuration, enabled: enabled, prominent: prominent)
    }

    private struct WinStandardButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let enabled: Bool
        let prominent: Bool
        @EnvironmentObject var theme: Theme
        @State private var hovering = false

        var body: some View {
            let p = Win11.palette(theme.scheme)
            configuration.label
                .font(Win11.Fonts.commandButton)
                .foregroundStyle(enabled ? (prominent ? p.textPrimary : p.textPrimary) : p.textDisabled)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusControl, style: .continuous)
                            .fill(configuration.isPressed ? p.controlFillPressed : hovering ? p.controlFillHover : p.controlFill)
                        RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusControl, style: .continuous)
                            .strokeBorder(
                                enabled ? (hovering ? p.strokeStrong : p.stroke) : p.stroke,
                                lineWidth: 1
                            )
                    }
                    .opacity(enabled ? 1 : 0.6)
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 && enabled }
        }
    }
}
