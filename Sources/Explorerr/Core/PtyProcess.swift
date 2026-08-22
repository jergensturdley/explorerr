import Foundation
import Darwin
import CSupport

/// A child shell attached to a pseudo-terminal.
/// Spawn via posix_openpt/grantpt/unlockpt + fork + execve (all C calls in the child —
/// the exec path is async-signal-safe).
final class PtyProcess {
    private var masterFD: Int32 = -1
    private(set) var pid: pid_t = -1
    private var readSource: DispatchSourceRead?
    private let ioQueue = DispatchQueue(label: "explorerr.pty", qos: .userInitiated)

    /// Raw output bytes from the child (called on the IO queue).
    var onOutput: ((Data) -> Void)?
    /// Child exited / pty closed (called on the IO queue).
    var onExit: (() -> Void)?

    private static let defaultShell: String = {
        let envShell = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        return envShell.isEmpty ? "/bin/zsh" : envShell
    }()

    var isRunning: Bool { masterFD >= 0 }

    // MARK: spawn

    func start(cwd: URL?, cols: Int, rows: Int) {
        precondition(masterFD < 0, "pty already started")
        let shell = Self.defaultShell

        // Prepare everything that needs Swift/allocations BEFORE fork.
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["XPC_SERVICE_NAME"] = nil   // don't inherit XPC bootstrap hazards
        let envEntries = env.map { "\($0.key)=\($0.value)" }
        let shellName = (shell as NSString).lastPathComponent

        let cwdPath = cwd?.path ?? NSHomeDirectory()
        let shellCString = strdup(shell)!
        let cwdCString = strdup(cwdPath)!
        let arg0CString = strdup("-\(shellName)")!   // login shell → loads user rc
        var argv: [UnsafeMutablePointer<CChar>?] = [arg0CString, nil]
        var envp: [UnsafeMutablePointer<CChar>?] = envEntries.map { strdup($0)! }
        envp.append(nil)

        let master = posix_openpt(Int32(O_RDWR | O_NOCTTY))
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
              let slaveNameC = ptsname(master) else {
            free(shellCString); free(cwdCString); free(arg0CString)
            envp.forEach { free($0) }
            return
        }
        let slaveName = String(cString: slaveNameC)
        let slaveNameCString = strdup(slaveName)!

        // Swift blocks fork(); use the C shim (the child only runs C code until execve).
        let childPid = fork_shim()
        if childPid == 0 {
            // ---- child: only C calls from here until execve ----
            setsid()
            let slave = open(slaveNameCString, O_RDWR)
            if slave >= 0 {
                ioctl(slave, TIOCSCTTY, 0)
                dup2(slave, 0); dup2(slave, 1); dup2(slave, 2)
                if slave > 2 { close(slave) }
            }
            close(master)
            chdir(cwdCString)
            execve(shellCString, &argv, &envp)
            _exit(127)
        }

        // ---- parent ----
        free(slaveNameCString)
        free(shellCString); free(cwdCString); free(arg0CString)
        envp.forEach { if let p = $0 { free(p) } }

        guard childPid > 0 else { return }
        pid = childPid
        masterFD = master
        setWinsize(cols: cols, rows: rows)

        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: ioQueue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 65536)
            let n = read(self.masterFD, &buffer, buffer.count)
            if n > 0 {
                self.onOutput?(Data(buffer[0..<n]))
            } else {
                // EIO on read = no readers left on the slave → child exited
                self.handleExit()
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.masterFD, fd >= 0 { close(fd); self?.masterFD = -1 }
        }
        readSource = source
        source.resume()
    }

    private func handleExit() {
        readSource?.cancel()
        readSource = nil
        onExit?()
    }

    // MARK: IO

    func write(_ data: Data) {
        ioQueue.async { [weak self] in
            guard let self, self.masterFD >= 0 else { return }
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                var sent = 0
                while sent < raw.count {
                    let n = Darwin.write(self.masterFD, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                    if n <= 0 { break }
                    sent += n
                }
            }
        }
    }

    func setWinsize(cols: Int, rows: Int) {
        var win = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &win)
    }

    func terminate() {
        guard masterFD >= 0 else { return }
        if pid > 0 { kill(pid, SIGTERM) }
        readSource?.cancel()
        readSource = nil
    }
}
