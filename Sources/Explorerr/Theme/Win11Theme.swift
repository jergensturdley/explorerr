import SwiftUI

/// Central Windows 11 design tokens. Never hardcode colors outside this file.
enum Win11 {
    // MARK: Palette (light / dark)

    struct Palette {
        let mica, contentBG, contentCard, sidebarTint, controlFill, controlFillHover, controlFillPressed: Color
        let stroke, strokeStrong, divider: Color
        let textPrimary, textSecondary, textDisabled: Color
        let accent, accentHover, accentPressed, accentText, onAccent: Color
        let selectionBG, selectionBorder, selectionText, hoverRow: Color
        let tabBarBG, tabActiveBG, tabHoverBG, tabStroke: Color
        let danger, caution: Color
        let menuBG, menuBorder, menuHover, menuSeparator: Color
        let addressBarBG, addressBarStroke, addressBarFocused: Color
        let scrollBar: Color
    }

    static let light = Palette(
        mica: Color(red: 243/255, green: 243/255, blue: 243/255),
        contentBG: Color.white,
        contentCard: Color.white,
        sidebarTint: Color(red: 243/255, green: 243/255, blue: 243/255).opacity(0.55),
        controlFill: Color.white.opacity(0.65),
        controlFillHover: Color(white: 0.98).opacity(0.8),
        controlFillPressed: Color(white: 0.92),
        stroke: Color.black.opacity(0.073),
        strokeStrong: Color.black.opacity(0.16),
        divider: Color.black.opacity(0.085),
        textPrimary: Color(red: 26/255, green: 26/255, blue: 26/255),
        textSecondary: Color(red: 96/255, green: 96/255, blue: 96/255),
        textDisabled: Color(red: 153/255, green: 153/255, blue: 153/255),
        accent: Color(red: 0/255, green: 103/255, blue: 192/255),          // #0067C0
        accentHover: Color(red: 25/255, green: 118/255, blue: 210/255),
        accentPressed: Color(red: 0/255, green: 78/255, blue: 151/255),
        accentText: Color(red: 0/255, green: 103/255, blue: 192/255),
        onAccent: .white,
        selectionBG: Color(red: 203/255, green: 227/255, blue: 248/255),   // #CBE3F8
        selectionBorder: Color(red: 153/255, green: 201/255, blue: 240/255),
        selectionText: Color(red: 6/255, green: 31/255, blue: 56/255),
        hoverRow: Color(red: 232/255, green: 236/255, blue: 240/255),
        tabBarBG: Color(red: 243/255, green: 243/255, blue: 243/255),
        tabActiveBG: Color(red: 253/255, green: 253/255, blue: 253/255),
        tabHoverBG: Color.black.opacity(0.045),
        tabStroke: Color.black.opacity(0.08),
        danger: Color(red: 196/255, green: 43/255, blue: 28/255),          // #C42B1C
        caution: Color(red: 255/255, green: 185/255, blue: 0/255),
        menuBG: Color(red: 249/255, green: 249/255, blue: 249/255).opacity(0.97),
        menuBorder: Color.black.opacity(0.10),
        menuHover: Color(red: 237/255, green: 237/255, blue: 237/255),
        menuSeparator: Color.black.opacity(0.09),
        addressBarBG: Color.white.opacity(0.75),
        addressBarStroke: Color.black.opacity(0.10),
        addressBarFocused: Color(red: 0/255, green: 103/255, blue: 192/255),
        scrollBar: Color.black.opacity(0.28)
    )

    static let dark = Palette(
        mica: Color(red: 32/255, green: 32/255, blue: 32/255),             // #202020
        contentBG: Color(red: 39/255, green: 39/255, blue: 39/255),        // #272727
        contentCard: Color(red: 39/255, green: 39/255, blue: 39/255),
        sidebarTint: Color(red: 28/255, green: 28/255, blue: 28/255).opacity(0.5),
        controlFill: Color.white.opacity(0.06),
        controlFillHover: Color.white.opacity(0.09),
        controlFillPressed: Color.white.opacity(0.035),
        stroke: Color.white.opacity(0.085),
        strokeStrong: Color.white.opacity(0.18),
        divider: Color.white.opacity(0.09),
        textPrimary: Color.white,
        textSecondary: Color(red: 205/255, green: 205/255, blue: 205/255),
        textDisabled: Color(red: 130/255, green: 130/255, blue: 130/255),
        accent: Color(red: 76/255, green: 194/255, blue: 255/255),         // #4CC2FF
        accentHover: Color(red: 106/255, green: 206/255, blue: 255/255),
        accentPressed: Color(red: 46/255, green: 170/255, blue: 230/255),
        accentText: Color(red: 76/255, green: 194/255, blue: 255/255),
        onAccent: Color(red: 10/255, green: 22/255, blue: 32/255),
        selectionBG: Color(red: 46/255, green: 66/255, blue: 86/255),      // #2E4256
        selectionBorder: Color(red: 76/255, green: 126/255, blue: 168/255),
        selectionText: Color.white,
        hoverRow: Color.white.opacity(0.06),
        tabBarBG: Color(red: 32/255, green: 32/255, blue: 32/255),
        tabActiveBG: Color(red: 42/255, green: 42/255, blue: 42/255),
        tabHoverBG: Color.white.opacity(0.05),
        tabStroke: Color.white.opacity(0.09),
        danger: Color(red: 255/255, green: 99/255, blue: 71/255),
        caution: Color(red: 255/255, green: 185/255, blue: 0/255),
        menuBG: Color(red: 43/255, green: 43/255, blue: 43/255).opacity(0.97),
        menuBorder: Color.white.opacity(0.11),
        menuHover: Color.white.opacity(0.075),
        menuSeparator: Color.white.opacity(0.10),
        addressBarBG: Color.white.opacity(0.07),
        addressBarStroke: Color.white.opacity(0.11),
        addressBarFocused: Color(red: 76/255, green: 194/255, blue: 255/255),
        scrollBar: Color.white.opacity(0.30)
    )

    static func palette(_ scheme: ColorScheme) -> Palette { scheme == .dark ? dark : light }

    // MARK: Metrics

    enum Metrics {
        static let cornerRadiusControl: CGFloat = 4
        static let cornerRadiusMenu: CGFloat = 8
        static let cornerRadiusCard: CGFloat = 8
        static let cornerRadiusTile: CGFloat = 6
        static let tabStripHeight: CGFloat = 36
        static let commandBarHeight: CGFloat = 44
        static let addressBarHeight: CGFloat = 44
        static let statusBarHeight: CGFloat = 26
        static let navPaneDefaultWidth: CGFloat = 250
        static let navPaneMinWidth: CGFloat = 180
        static let navPaneMaxWidth: CGFloat = 420
        static let rowHeightDetails: CGFloat = 32
        static let rowHeightList: CGFloat = 28
        static let menuRowHeight: CGFloat = 32
        static let windowMinWidth: CGFloat = 760
        static let windowMinHeight: CGFloat = 480
    }

    enum Fonts {
        static let body = Font.system(size: 13, weight: .regular)
        static let bodySecondary = Font.system(size: 12, weight: .regular)
        static let menu = Font.system(size: 13, weight: .regular)
        static let tab = Font.system(size: 12, weight: .regular)
        static let status = Font.system(size: 11.5, weight: .regular)
        static let breadcrumb = Font.system(size: 12.5, weight: .regular)
        static let commandButton = Font.system(size: 12.5, weight: .regular)
    }
}

/// Environment object holding resolved palette + shared UI prefs used by every view.
final class Theme: ObservableObject {
    @Published var scheme: ColorScheme = .light
    var p: Win11.Palette { Win11.palette(scheme) }
}
