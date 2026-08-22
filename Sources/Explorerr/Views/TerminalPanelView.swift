import SwiftUI
import AppKit

/// The integrated terminal panel: Win11-styled header + the live terminal view.
struct TerminalPanelView: View {
    @ObservedObject var controller: TerminalController
    let currentFolder: () -> URL?
    let onClose: () -> Void

    @EnvironmentObject var theme: Theme
    @State private var focused = false

    var body: some View {
        VStack(spacing: 0) {
            header
            TerminalHostView(controller: controller) { focused = $0 }
        }
        .background(Color(nsColor: TerminalController.defaultBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(focused ? Win11.palette(theme.scheme).selectionBorder : Win11.palette(theme.scheme).stroke, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .clipShape(RoundedCornersShape(radius: 8, corners: [.topLeft, .topRight]))
        .overlay(alignment: .bottom) {
            if controller.exited {
                exitedBar
            }
        }
    }

    private var header: some View {
        let p = Win11.palette(theme.scheme)
        return HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.accentText)
            Text(controller.title == "Terminal" ? "Terminal" : controller.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(p.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("zsh")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(p.accentText)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(p.selectionBG))

            Spacer(minLength: 8)

            headerButton("arrow.turn.down.right", help: "cd to the active folder") {
                if let folder = currentFolder() {
                    controller.cd(to: folder)
                }
            }
            headerButton("arrow.clockwise", help: "Restart shell") {
                controller.restart(cwd: currentFolder())
            }
            headerButton("xmark.circle", help: "Clear terminal") {
                controller.clear()
            }
            headerButton("xmark", help: "Close terminal (F4)") {
                onClose()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(p.menuBG)
        .overlay(alignment: .bottom) { Rectangle().fill(p.divider).frame(height: 1) }
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11.5, weight: .medium))
        }
        .buttonStyle(WinIconButtonStyle(padding: 5))
        .help(help)
    }

    private var exitedBar: some View {
        let p = Win11.palette(theme.scheme)
        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(p.caution)
            Text("The shell exited.")
                .font(.system(size: 12))
                .foregroundStyle(p.textSecondary)
            Spacer()
            Button("Restart") {
                controller.restart(cwd: currentFolder())
            }
            .buttonStyle(WinStandardButtonStyle())
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(p.menuBG)
        .overlay(alignment: .top) { Rectangle().fill(p.divider).frame(height: 1) }
    }
}

/// Rectangle with only some corners rounded.
struct RoundedCornersShape: Shape {
    var radius: CGFloat
    struct Corner: OptionSet {
        let rawValue: Int
        static let topLeft = Corner(rawValue: 1)
        static let topRight = Corner(rawValue: 2)
    }
    let corners: Corner

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(radius, rect.width / 2, rect.height)
        let tl = corners.contains(.topLeft)
        let tr = corners.contains(.topRight)
        p.move(to: CGPoint(x: rect.minX + (tl ? r : 0), y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - (tr ? r : 0), y: rect.minY))
        if tr { p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY)) }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        if tl { p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + r), control: CGPoint(x: rect.minX, y: rect.minY)) }
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + (tl ? r : 0)))
        p.closeSubpath()
        return p
    }
}

// MARK: - AppKit host

struct TerminalHostView: NSViewRepresentable {
    @ObservedObject var controller: TerminalController
    let onFocusChange: (Bool) -> Void

    final class TerminalTextView: NSTextView {
        weak var controller: TerminalController?

        override func keyDown(with event: NSEvent) {
            guard let controller else { super.keyDown(with: event); return }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if event.keyCode == 118 { // F4 closes the panel even while typing
                NotificationCenter.default.post(name: .explorerrToggleTerminalPane, object: nil)
                return
            }
            if event.keyCode == 53 && mods.isEmpty { // Esc reaches the shell (vim, less)
                controller.send(bytes: [0x1B])
                return
            }

            // Terminal conventions: ⌘C copies when there's a selection, otherwise sends ^C
            if mods.contains(.command), event.charactersIgnoringModifiers == "c" {
                if selectedRange().length > 0 {
                    copy(nil)
                    return
                }
                controller.send(bytes: [0x03])
                return
            }
            if mods.contains(.command), event.charactersIgnoringModifiers == "v" {
                if let text = NSPasteboard.general.string(forType: .string) {
                    controller.paste(text)
                }
                return
            }
            if mods.contains(.command) {
                return // don't type command-modified characters into the shell
            }

            if let bytes = TerminalKeyTranslator.bytes(for: event) {
                controller.send(bytes: bytes)
                return
            }
            // Plain characters flow through the input manager (IME-safe)
            super.keyDown(with: event)
        }

        override func insertText(_ string: Any, replacementRange: NSRange) {
            if let controller, let text = string as? String {
                controller.send(text)
            } else {
                super.insertText(string, replacementRange: replacementRange)
            }
        }

        override func insertNewline(_ sender: Any?) { controller?.send("\r") }
        override func insertTab(_ sender: Any?) { controller?.send("\t") }
        override func deleteBackward(_ sender: Any?) { controller?.send(bytes: [0x7F]) }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = TerminalTextView()
        textView.controller = controller
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = TerminalController.defaultBackground
        textView.textColor = TerminalController.defaultForeground
        textView.font = controller.font
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 10, height: 8)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = TerminalController.defaultBackground
        scroll.scrollerStyle = .overlay

        context.coordinator.textView = textView
        context.coordinator.scroll = scroll
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        // Follow-output: keep pinned to the bottom only if the user was at the bottom
        let docHeight = textView.frame.height
        let visible = scroll.contentView.visibleRect
        let wasAtBottom = visible.maxY >= docHeight - controller.lineHeight * 2
            || context.coordinator.lastDocHeight == 0
        context.coordinator.lastDocHeight = docHeight

        let focusedNow = NSApp.keyWindow?.firstResponder === textView
        if context.coordinator.lastFocused != focusedNow {
            context.coordinator.lastFocused = focusedNow
            onFocusChange(focusedNow)
        }

        let oldSel = textView.selectedRange()
        textView.textStorage?.setAttributedString(controller.attributedContent(cursorVisible: focusedNow))
        if let storage = textView.textStorage {
            let loc = min(oldSel.location, storage.length)
            let len = min(oldSel.length, storage.length - loc)
            textView.setSelectedRange(NSRange(location: loc, length: len))
        }

        if wasAtBottom {
            let bottom = NSPoint(x: 0, y: max(0, textView.frame.height - scroll.contentView.bounds.height))
            scroll.contentView.scroll(to: bottom)
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        // Viewport → cols/rows (keeps the pty grid in sync with the visible area)
        controller.viewportChanged(
            width: scroll.contentSize.width,
            height: scroll.contentSize.height,
            padding: 10
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        weak var textView: TerminalTextView?
        weak var scroll: NSScrollView?
        var lastFocused = false
        var lastDocHeight: CGFloat = 0
    }
}

// MARK: - Key translation (NSEvent → terminal bytes)

enum TerminalKeyTranslator {
    /// Bytes for special keys; nil for plain characters (those go through
    /// the text input system so IME keeps working).
    private static func asciiScalar(_ string: String) -> UInt8? {
        guard let value = string.unicodeScalars.first?.value, value <= 127 else { return nil }
        return UInt8(value)
    }

    static func bytes(for event: NSEvent) -> [UInt8]? {
        guard let chars = event.charactersIgnoringModifiers else { return nil }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCtrl = mods.contains(.control)

        if hasCtrl, let ascii = asciiScalar(chars.lowercased()) {
            if ascii >= 0x61 && ascii <= 0x7A { return [ascii - 0x60] }   // ^A…^Z
            switch ascii {
            case 0x20: return [0x00]      // ^Space → NUL
            case 0x5B: return [0x1B]      // ^[ → ESC
            case 0x5C: return [0x1C]
            case 0x5D: return [0x1D]
            case 0x40: return [0x00]
            default: break
            }
        }

        // Option = Alt → ESC prefix (terminal convention)
        if mods.contains(.option), !mods.contains(.command),
           let ascii = asciiScalar(chars.lowercased()),
           (ascii >= 0x61 && ascii <= 0x7A) || (ascii >= 0x30 && ascii <= 0x39) {
            return [0x1B, ascii]
        }

        switch event.keyCode {
        case 117: return escSeq("[3~")      // Delete
        case 115: return escSeq("[H")       // Home
        case 119: return escSeq("[F")       // End
        case 116: return escSeq("[5~")      // Page Up
        case 121: return escSeq("[6~")      // Page Down
        case 123: return arrow("D", mods)   // Left
        case 124: return arrow("C", mods)   // Right
        case 125: return arrow("B", mods)   // Down
        case 126: return arrow("A", mods)   // Up
        default: return nil                 // Return/Tab/Backspace handled via doCommand
        }
    }

    private static func escSeq(_ body: String) -> [UInt8] {
        Array("\u{1B}\(body)".utf8)
    }

    private static func arrow(_ final: String, _ mods: NSEvent.ModifierFlags) -> [UInt8] {
        let hasShift = mods.contains(.shift)
        let hasOpt = mods.contains(.option)
        let hasCtrl = mods.contains(.control)
        if hasShift || hasOpt || hasCtrl {
            let modifier = (hasShift ? 1 : 0) + (hasOpt ? 2 : 0) + (hasCtrl ? 4 : 0)
            return escSeq("[1;\(modifier + 1)\(final)")
        }
        return escSeq("[\(final)")
    }
}

extension Notification.Name {
    static let explorerrToggleTerminalPane = Notification.Name("explorerr.toggleTerminalPane")
}
