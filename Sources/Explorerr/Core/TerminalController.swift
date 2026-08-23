import SwiftUI
import AppKit

/// Glue between the UI, the emulator, and the pty. One per window.
@MainActor
final class TerminalController: ObservableObject {
    let emulator = TerminalEmulator()
    private let pty = PtyProcess()

    @Published var revision = 0            // bump → view rebuilds the attributed text
    @Published var title = "Terminal"
    @Published var exited = false

    @Published var fontSize: CGFloat = 12.5

    var font: NSFont { NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    var cellWidth: CGFloat { ceil(NSAttributedString(string: "M", attributes: [.font: font]).size().width) }
    var lineHeight: CGFloat { ceil(font.boundingRectForFont.height) + 1.5 }
    var boldFont: NSFont { NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }

    func zoomIn() { fontSize = min(24, fontSize + 1.5) }
    func zoomOut() { fontSize = max(9, fontSize - 1.5) }
    func resetZoom() { fontSize = 12.5 }
    private var pendingData = Data()
    private var drainScheduled = false
    private var lastCols = 80
    private var lastRows = 24
    private var launched = false
    /// Load the user's shell startup files (Options; off by default so fastfetch and
    /// heavyweight prompts don't mangle the minimal emulator). Applies at (re)launch.
    var usesProfile = false

    var isRunning: Bool { pty.isRunning }

    // MARK: lifecycle

    func launchIfNeeded(cwd: URL?) {
        guard !launched else { return }
        launched = true
        exited = false

        pty.onOutput = { [weak self] data in
            guard let self else { return }
            Task { @MainActor in
                self.pendingData.append(data)
                self.scheduleDrain()
            }
        }
        pty.onExit = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.exited = true
                self.bump()
            }
        }
        pty.start(cwd: cwd, cols: lastCols, rows: lastRows, usesProfile: usesProfile)
    }

    func restart(cwd: URL?) {
        pty.terminate()
        pendingData.removeAll()
        emulator.clearScreenAndScrollback()
        title = "Terminal"
        exited = false
        bump()
        // Small delay so the old child can die before we spawn a fresh pty
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.launched = false
            self.launchIfNeeded(cwd: cwd)
        }
    }

    func terminate() {
        pty.terminate()
    }

    // MARK: IO

    private func scheduleDrain() {
        guard !drainScheduled else { return }
        drainScheduled = true
        // Coalesce bursts (large `cat` output) into ~30fps updates
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.drainScheduled = false
            let chunk = self.pendingData
            self.pendingData.removeAll()
            guard !chunk.isEmpty else { return }
            if let text = String(data: chunk, encoding: .utf8) {
                self.emulator.feed(text)
            } else {
                // Split multibyte sequence: UTF-8 characters are at most 4 bytes long,
                // so check if dropping the last 1-3 trailing bytes yields valid UTF-8.
                var boundary = chunk.count
                var decoded: String? = nil
                let minBoundary = max(0, chunk.count - 4)
                while boundary > minBoundary {
                    decoded = String(data: chunk.prefix(boundary), encoding: .utf8)
                    if decoded != nil { break }
                    boundary -= 1
                }
                if let text = decoded {
                    self.emulator.feed(text)
                    if boundary < chunk.count {
                        self.pendingData = Data(chunk[boundary...])
                    }
                } else {
                    // Binary or invalid UTF-8 data: perform lossy decoding and flush
                    let fallback = String(decoding: chunk, as: UTF8.self)
                    self.emulator.feed(fallback)
                }
            }
            if self.emulator.title != self.title {
                self.title = self.emulator.title
            }
            self.bump()
        }
    }

    private func bump() { revision += 1 }

    func send(_ text: String) {
        guard !exited else { return }
        pty.write(Data(text.utf8))
    }

    func send(bytes: [UInt8]) {
        guard !exited else { return }
        pty.write(Data(bytes))
    }

    /// Sends `cd <folder>` to the shell (Windows-terminal-style sync button).
    func cd(to url: URL) {
        let escaped = url.path.replacingOccurrences(of: "'", with: "'\\''")
        send("\u{15}cd '\(escaped)'\n")
    }

    /// Dolphin-style automatic cwd sync on navigation. Only fires when it's safe:
    /// the shell must be idle (own the pty foreground — no vim/less/running command)
    /// and the terminal must not be focused (the user isn't mid-keystroke). ^U first
    /// clears any leftover prompt input.
    func autoCD(to url: URL) {
        guard !exited, pty.isRunning, pty.isShellForeground else { return }
        if NSApp.keyWindow?.firstResponder is TerminalHostView.TerminalTextView { return }
        let escaped = url.path.replacingOccurrences(of: "'", with: "'\\''")
        send("\u{15}cd '\(escaped)'\n")
    }

    func paste(_ string: String) {
        send(string)
    }

    func clear() {
        emulator.clearScreenAndScrollback()
        bump()
    }

    // MARK: sizing

    func viewportChanged(width: CGFloat, height: CGFloat, padding: CGFloat) {
        let cols = max(20, Int((width - padding * 2) / cellWidth))
        let rows = max(4, Int((height - padding * 2) / lineHeight))
        guard cols != lastCols || rows != lastRows else { return }
        lastCols = cols
        lastRows = rows
        emulator.resize(cols: cols, rows: rows)
        pty.setWinsize(cols: cols, rows: rows)
        bump()
    }

    // MARK: rendering

    /// Windows Terminal Campbell Powershell palette (indexed 0–15) + xterm 256/truecolor.
    static let defaultBackground = NSColor(red: 0x0C / 255, green: 0x0C / 255, blue: 0x0C / 255, alpha: 1)
    static let defaultForeground = NSColor(red: 0xCC / 255, green: 0xCC / 255, blue: 0xCC / 255, alpha: 1)
    private static let palette: [NSColor] = [
        NSColor(hex: 0x0C0C0C), NSColor(hex: 0xC50F1F), NSColor(hex: 0x13A10E), NSColor(hex: 0xC19C00),
        NSColor(hex: 0x3B78FF), NSColor(hex: 0x881798), NSColor(hex: 0x3A96DD), NSColor(hex: 0xCCCCCC),
        NSColor(hex: 0x767676), NSColor(hex: 0xE74856), NSColor(hex: 0x16C60C), NSColor(hex: 0xF9F1A5),
        NSColor(hex: 0x689CFF), NSColor(hex: 0xB4009E), NSColor(hex: 0x61D6D6), NSColor(hex: 0xF2F2F2),
    ]

    static func color(_ term: TermColor, isBackground: Bool) -> NSColor {
        switch term {
        case .default:
            return isBackground ? defaultBackground : defaultForeground
        case .indexed(let idx):
            if Int(idx) < palette.count { return palette[Int(idx)] }
            return ansi256(idx)
        case .rgb(let value):
            return NSColor(hex: value)
        }
    }

    private static func ansi256(_ idx: UInt8) -> NSColor {
        let i = Int(idx)
        if i >= 16 && i < 232 {
            // 6×6×6 cube
            let c = i - 16
            let steps: [CGFloat] = [0, 95, 135, 175, 215, 255]
            return NSColor(
                red: steps[(c / 36) % 6] / 255,
                green: steps[(c / 9) % 6] / 255,
                blue: steps[c % 6] / 255,
                alpha: 1
            )
        }
        if i >= 232 {
            let gray = CGFloat(8 + (i - 232) * 10) / 255
            return NSColor(white: gray, alpha: 1)
        }
        return defaultForeground
    }

    /// Builds the attributed contents: scrollback + screen with a block cursor.
    func attributedContent(cursorVisible: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 0
        para.paragraphSpacing = 0
        let baseFont = font

        func attributes(fg: TermColor, bg: TermColor, bold: Bool, italic: Bool,
                        underline: Bool, inverse: Bool, extraInverted: Bool) -> [NSAttributedString.Key: Any] {
            var f = fg, g = bg
            if inverse { swap(&f, &g) }
            if extraInverted { swap(&f, &g) }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: bold ? self.boldFont : baseFont,
                .foregroundColor: Self.color(f, isBackground: false),
                .backgroundColor: Self.color(g, isBackground: true),
                .paragraphStyle: para,
            ]
            if italic { attrs[.obliqueness] = 0.15 }
            if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            return attrs
        }

        func append(_ line: [TermCell], isCursorLine: Bool, cursorCol: Int) {
            var run = ""
            var runAttr: (fg: TermColor, bg: TermColor, b: Bool, i: Bool, u: Bool, inv: Bool)? = nil

            func flush() {
                guard !run.isEmpty, let ra = runAttr else { return }
                result.append(NSAttributedString(string: run, attributes: attributes(
                    fg: ra.fg, bg: ra.bg, bold: ra.b, italic: ra.i, underline: ra.u,
                    inverse: ra.inv, extraInverted: false)))
                run = ""
            }

            for (col, cell) in line.enumerated() {
                let isCursor = isCursorLine && col == cursorCol && cursorVisible
                if let ra = runAttr, !isCursor,
                   ra.fg == cell.fg, ra.bg == cell.bg, ra.b == cell.bold,
                   ra.i == cell.italic, ra.u == cell.underline, ra.inv == cell.inverse {
                    run.append(cell.ch)
                } else {
                    flush()
                    if isCursor {
                        result.append(NSAttributedString(string: String(cell.ch), attributes: attributes(
                            fg: cell.fg, bg: cell.bg, bold: cell.bold, italic: cell.italic,
                            underline: cell.underline, inverse: cell.inverse, extraInverted: true)))
                        runAttr = nil
                    } else {
                        runAttr = (cell.fg, cell.bg, cell.bold, cell.italic, cell.underline, cell.inverse)
                        run = String(cell.ch)
                    }
                }
            }
            flush()
            result.append(NSAttributedString(string: "\n", attributes: [.font: baseFont, .paragraphStyle: para]))
        }

        for line in emulator.scrollback {
            append(line, isCursorLine: false, cursorCol: -1)
        }
        for (row, line) in emulator.lines.enumerated() {
            append(line, isCursorLine: row == emulator.cursorRow, cursorCol: emulator.cursorCol)
        }
        return result
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
