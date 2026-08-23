import Foundation

// MARK: - Cell model

enum TermColor: Equatable {
    case `default`      // palette foreground / terminal background
    case indexed(UInt8) // 0–255
    case rgb(UInt32)    // 0xRRGGBB
}

struct TermCell: Equatable {
    var ch: Character = " "
    var fg: TermColor = .default
    var bg: TermColor = .default
    var bold = false
    var italic = false
    var underline = false
    var inverse = false

    static let blank = TermCell()
}

// MARK: - Emulator

/// A compact VT100/xterm-256color terminal emulator: enough for zsh prompts,
/// ls/git colors, curses-style redraws, vim/less (alt screen), and full-color output.
final class TerminalEmulator {
    private(set) var cols: Int
    private(set) var rows: Int
    private(set) var cursorRow = 0
    private(set) var cursorCol = 0

    private(set) var lines: [[TermCell]]
    private(set) var scrollback: [[TermCell]] = []
    let scrollbackLimit = 3000

    private(set) var title: String = "Terminal"

    private enum ParserState { case ground, esc, csi, osc, charset }
    private var state: ParserState = .ground
    private var csiBuffer = ""
    private var oscBuffer = ""

    // current SGR attributes
    private var fg: TermColor = .default
    private var bg: TermColor = .default
    private var bold = false, italic = false, underline = false, inverse = false
    private var pendingWrap = false

    // saved cursor (DECSC / CSI s)
    private var savedCursor = (row: 0, col: 0, fg: TermColor.default, bg: TermColor.default, false, false, false, false)
    // alt screen
    private var savedScreen: (lines: [[TermCell]], scroll: [[TermCell]])?

    init(cols: Int = 80, rows: Int = 24) {
        self.cols = max(10, cols)
        self.rows = max(4, rows)
        lines = Array(repeating: Array(repeating: TermCell.blank, count: self.cols), count: self.rows)
    }

    // MARK: introspection for tests/UI

    func text(inRow row: Int) -> String {
        guard lines.indices.contains(row) else { return "" }
        return String(lines[row].map { $0.ch })
    }

    func cell(row: Int, col: Int) -> TermCell {
        guard lines.indices.contains(row), lines[row].indices.contains(col) else { return .blank }
        return lines[row][col]
    }

    // MARK: feed

    func feed(_ text: String) {
        for ch in text {
            switch state {
            case .ground: ground(ch)
            case .esc: escape(ch)
            case .csi: csi(ch)
            case .osc: osc(ch)
            case .charset: state = .ground   // ESC ( X / ESC ) X — consume designator
            }
        }
    }

    private func ground(_ ch: Character) {
        switch ch {
        case "\u{1B}": state = .esc
        case "\n", "\u{0B}", "\u{0C}": linefeed()
        case "\r": cursorCol = 0; pendingWrap = false
        case "\t":
            let next = ((cursorCol / 8) + 1) * 8
            cursorCol = min(next, cols - 1)
        case "\u{08}": cursorCol = max(0, cursorCol - 1); pendingWrap = false
        case "\u{07}": break // BEL
        default:
            if ch.isNewline { linefeed(); return }
            let scalars = ch.unicodeScalars
            if scalars.allSatisfy({ $0.value != 0 && $0.value != 0x7F }) {
                putChar(ch)
            }
        }
    }

    private func putChar(_ ch: Character) {
        if pendingWrap {
            pendingWrap = false
            cursorCol = 0
            linefeed()
        }
        if cursorCol >= cols { cursorCol = cols - 1 }
        ensureRow()
        lines[cursorRow][cursorCol] = TermCell(ch: ch, fg: fg, bg: bg, bold: bold, italic: italic, underline: underline, inverse: inverse)
        if cursorCol == cols - 1 {
            pendingWrap = true
        } else {
            cursorCol += 1
        }
    }

    private func linefeed() {
        if cursorRow < rows - 1 {
            cursorRow += 1
        } else {
            scrollUp()
        }
    }

    private func scrollUp() {
        let removed = lines.removeFirst()
        if savedScreen == nil {
            scrollback.append(removed)
            if scrollback.count > scrollbackLimit { scrollback.removeFirst(scrollback.count - scrollbackLimit) }
        }
        lines.append(Array(repeating: TermCell.blank, count: cols))
    }

    private func ensureRow() {
        while cursorRow >= lines.count {
            lines.append(Array(repeating: TermCell.blank, count: cols))
        }
    }

    // MARK: escape sequences

    private func escape(_ ch: Character) {
        switch ch {
        case "[": state = .csi; csiBuffer = ""
        case "]": state = .osc; oscBuffer = ""
        case "(": state = .charset
        case ")": state = .charset
        case "7": saveCursor(); state = .ground
        case "8": restoreCursor(); state = .ground
        case "D": linefeed(); state = .ground
        case "M": reverseLinefeed(); state = .ground
        case "E": cursorCol = 0; linefeed(); state = .ground
        case "c": fullReset(); state = .ground   // RIS
        default: state = .ground                  // unsupported two-char sequences
        }
    }

    private func reverseLinefeed() {
        if cursorRow > 0 { cursorRow -= 1 } else {
            lines.insert(Array(repeating: TermCell.blank, count: cols), at: 0)
            lines.removeLast()
        }
    }

    private func saveCursor() {
        savedCursor = (cursorRow, cursorCol, fg, bg, bold, italic, underline, inverse)
    }

    private func restoreCursor() {
        cursorRow = min(savedCursor.0, rows - 1)
        cursorCol = min(savedCursor.1, cols - 1)
        fg = savedCursor.2; bg = savedCursor.3
        bold = savedCursor.4; italic = savedCursor.5
        underline = savedCursor.6; inverse = savedCursor.7
        pendingWrap = false
    }

    private func fullReset() {
        lines = Array(repeating: Array(repeating: TermCell.blank, count: cols), count: rows)
        cursorRow = 0; cursorCol = 0
        pendingWrap = false
        sgrReset()
    }

    private func sgrReset() {
        fg = .default; bg = .default
        bold = false; italic = false; underline = false; inverse = false
    }

    // MARK: OSC (title etc.)

    private func osc(_ ch: Character) {
        if ch == "\u{07}" {
            applyOsc(oscBuffer)
            oscBuffer = ""
            state = .ground
        } else if ch == "\u{1B}" {
            // ESC \ terminator: next char ends ST — peek by transitioning through esc state
            applyOsc(oscBuffer)
            oscBuffer = ""
            state = .esc
        } else {
            oscBuffer.append(ch)
            if oscBuffer.count > 512 { oscBuffer = ""; state = .ground }
        }
    }

    private func applyOsc(_ body: String) {
        guard let semi = body.firstIndex(of: ";") else { return }
        let code = body[body.startIndex..<semi]
        let value = String(body[body.index(after: semi)...])
        if code == "0" || code == "2" { title = value }
    }

    // MARK: CSI

    private func csi(_ ch: Character) {
        if (ch >= "0" && ch <= "9") || ch == ";" || ch == ":" || ch == "?" || ch == ">" || ch == "<" || ch == "=" || ch == " " {
            csiBuffer.append(ch)
            if csiBuffer.count > 128 { state = .ground }
            return
        }
        guard let ascii = ch.asciiValue, ascii >= 0x40 && ascii <= 0x7E else {
            state = .ground
            return
        }
        let params = csiBuffer
        let privateMarker = params.contains("?")
        let numbers = params.filter { $0.isNumber || $0 == ";" || $0 == ":" }
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { sub -> Int in Int(sub.filter { $0.isNumber }) ?? 0 }
        csiBuffer = ""
        state = .ground
        dispatchCSI(String(ch), numbers, privateMarker)
    }

    private func param(_ numbers: [Int], _ index: Int, _ defaultValue: Int) -> Int {
        guard index < numbers.count else { return defaultValue }
        let v = numbers[index]
        return v == 0 ? defaultValue : v
    }

    private func dispatchCSI(_ final: String, _ n: [Int], _ priv: Bool) {
        switch final {
        case "A": cursorRow = max(0, cursorRow - param(n, 0, 1))
        case "B": cursorRow = min(rows - 1, cursorRow + param(n, 0, 1))
        case "C": cursorCol = min(cols - 1, cursorCol + param(n, 0, 1)); pendingWrap = false
        case "D": cursorCol = max(0, cursorCol - param(n, 0, 1)); pendingWrap = false
        case "E": cursorRow = min(rows - 1, cursorRow + param(n, 0, 1)); cursorCol = 0
        case "F": cursorRow = max(0, cursorRow - param(n, 0, 1)); cursorCol = 0
        case "G", "`": cursorCol = min(cols - 1, max(0, param(n, 0, 1) - 1))
        case "d": cursorRow = min(rows - 1, max(0, param(n, 0, 1) - 1))
        case "H", "f":
            cursorRow = min(rows - 1, max(0, param(n, 0, 1) - 1))
            cursorCol = min(cols - 1, max(0, param(n, 1, 1) - 1))
            pendingWrap = false
        case "J": eraseDisplay(n.first ?? 0)
        case "K": eraseLine(n.first ?? 0)
        case "L": insertLines(param(n, 0, 1))
        case "M": deleteLines(param(n, 0, 1))
        case "P": deleteChars(param(n, 0, 1))
        case "@": insertChars(param(n, 0, 1))
        case "X": eraseChars(param(n, 0, 1))
        case "S": for _ in 0..<(n.first ?? 1) { scrollUp() }
        case "T": for _ in 0..<(n.first ?? 1) { reverseLinefeed() }
        case "m": if priv { /* DECSCUSR style ignored */ } else { sgr(n) }
        case "s": saveCursor()
        case "u": restoreCursor()
        case "h", "l":
            if priv {
                for code in n {
                    switch code {
                    case 25: break          // cursor hide/show: rendering-level concern
                    case 1049, 47, 1047: setAltScreen(final == "h")
                    default: break
                    }
                }
            }
        case "r": break // scroll region: treated as full screen
        default: break
        }
    }

    // MARK: erase / insert / delete

    private func blankCell() -> TermCell {
        TermCell(ch: " ", fg: .default, bg: bg)   // BCE: erase with current bg
    }

    private func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseLine(0)
            if cursorRow + 1 < rows {
                for r in (cursorRow + 1)..<rows { lines[r] = Array(repeating: blankCell(), count: cols) }
            }
        case 1:
            eraseLine(1)
            if cursorRow > 0 {
                for r in 0..<cursorRow { lines[r] = Array(repeating: blankCell(), count: cols) }
            }
        case 2, 3:
            for r in 0..<rows { lines[r] = Array(repeating: blankCell(), count: cols) }
        default: break
        }
    }

    private func eraseLine(_ mode: Int) {
        ensureRow()
        switch mode {
        case 0:
            for c in cursorCol..<cols { lines[cursorRow][c] = blankCell() }
        case 1:
            for c in 0...min(cursorCol, cols - 1) { lines[cursorRow][c] = blankCell() }
        case 2:
            lines[cursorRow] = Array(repeating: blankCell(), count: cols)
        default: break
        }
    }

    private func eraseChars(_ count: Int) {
        ensureRow()
        for c in cursorCol..<min(cols, cursorCol + count) { lines[cursorRow][c] = blankCell() }
    }

    private func insertChars(_ count: Int) {
        ensureRow()
        let line = lines[cursorRow]
        let blanks = Array(repeating: blankCell(), count: count)
        let head = Array(line[0..<cursorCol])
        let tail = Array(line[cursorCol..<max(cursorCol, cols - count)])
        lines[cursorRow] = head + blanks + tail
    }

    private func deleteChars(_ count: Int) {
        ensureRow()
        let line = lines[cursorRow]
        let head = Array(line[0..<cursorCol])
        let tail = Array(line[min(cols, cursorCol + count)...])
        let pad = Array(repeating: blankCell(), count: max(0, cols - head.count - tail.count))
        lines[cursorRow] = (head + tail + pad).prefix(cols).map { $0 }
    }

    private func insertLines(_ count: Int) {
        ensureRow()
        for _ in 0..<count {
            lines.insert(Array(repeating: blankCell(), count: cols), at: cursorRow)
            lines.removeLast()
        }
    }

    private func deleteLines(_ count: Int) {
        ensureRow()
        for _ in 0..<count {
            lines.remove(at: cursorRow)
            lines.append(Array(repeating: blankCell(), count: cols))
        }
    }

    // MARK: alt screen

    private func setAltScreen(_ enter: Bool) {
        if enter {
            guard savedScreen == nil else { return }
            savedScreen = (lines, scrollback)
            lines = Array(repeating: Array(repeating: TermCell.blank, count: cols), count: rows)
            scrollback = []
            cursorRow = 0; cursorCol = 0
        } else {
            guard let saved = savedScreen else { return }
            lines = saved.lines
            scrollback = saved.scroll
            savedScreen = nil
        }
    }

    // MARK: SGR

    private func sgr(_ n: [Int]) {
        var i = 0
        while i < n.count || n.isEmpty {
            let code = n.isEmpty ? 0 : n[i]
            switch code {
            case 0: sgrReset()
            case 1: bold = true
            case 3: italic = true
            case 4: underline = true
            case 22: bold = false
            case 23: italic = false
            case 24: underline = false
            case 7: inverse = true
            case 27: inverse = false
            case 39: fg = .default
            case 49: bg = .default
            case 30...37: fg = .indexed(UInt8(code - 30))
            case 40...47: bg = .indexed(UInt8(code - 40))
            case 90...97: fg = .indexed(UInt8(code - 90 + 8))
            case 100...107: bg = .indexed(UInt8(code - 100 + 8))
            case 38, 48:
                // extended: 38;5;N or 38;2;R;G;B
                if i + 1 < n.count {
                    if n[i + 1] == 5, i + 2 < n.count {
                        let color = TermColor.indexed(UInt8(max(0, min(255, n[i + 2]))))
                        if code == 38 { fg = color } else { bg = color }
                        i += 2
                    } else if n[i + 1] == 2, i + 4 < n.count {
                        let r = max(0, min(255, n[i + 2]))
                        let g = max(0, min(255, n[i + 3]))
                        let b = max(0, min(255, n[i + 4]))
                        let color = TermColor.rgb(UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b))
                        if code == 38 { fg = color } else { bg = color }
                        i += 4
                    }
                }
            default: break
            }
            if n.isEmpty { break }
            i += 1
        }
    }

    // MARK: resize

    func resize(cols newCols: Int, rows newRows: Int) {
        let newCols = max(10, newCols)
        let newRows = max(4, newRows)
        guard newCols != cols || newRows != rows else { return }

        // Adjust width (no reflow — the shell redraws on SIGWINCH)
        if newCols != cols {
            for i in lines.indices {
                if lines[i].count < newCols {
                    lines[i].append(contentsOf: Array(repeating: TermCell.blank, count: newCols - lines[i].count))
                } else {
                    lines[i].removeLast(lines[i].count - newCols)
                }
            }
        }
        // Adjust height
        if newRows > rows {
            lines.append(contentsOf: Array(repeating: Array(repeating: TermCell.blank, count: newCols), count: newRows - rows))
        } else if newRows < rows {
            // Trim BLANK rows below the cursor first: pushing the top rows out during
            // the window's layout-settling resizes shoved the prompt into scrollback
            // and left an all-blank screen (terminal looked empty until output filled it).
            var toRemove = lines.count - newRows
            while toRemove > 0, lines.count > cursorRow + 1,
                  lines.last?.allSatisfy({ $0.ch == " " }) == true {
                lines.removeLast()
                toRemove -= 1
            }
            if toRemove > 0 {
                if savedScreen == nil {
                    scrollback.append(contentsOf: lines.prefix(toRemove))
                    if scrollback.count > scrollbackLimit { scrollback.removeFirst(scrollback.count - scrollbackLimit) }
                }
                lines.removeFirst(toRemove)
                cursorRow = max(0, cursorRow - toRemove)
            }
        }

        cols = newCols
        rows = newRows
        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, cols - 1)
        pendingWrap = false
    }

    // MARK: local clear

    func clearScreenAndScrollback() {
        scrollback = []
        lines = Array(repeating: Array(repeating: TermCell.blank, count: cols), count: rows)
        cursorRow = 0
        cursorCol = 0
    }
}
