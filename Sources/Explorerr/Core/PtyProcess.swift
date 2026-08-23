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

    /// Short shell name (e.g. "zsh", "bash") shown in the terminal header.
    static var shellName: String { (defaultShell as NSString).lastPathComponent }

    var isRunning: Bool { masterFD >= 0 }

    // MARK: spawn

    /// Environment for the child shell. With `usesProfile` false (default) the shell is
    /// non-login and, for zsh, ZDOTDIR points at a minimal rc: the user's fastfetch /
    /// fancy-prompt startup files stay out of the small built-in emulator. PATH gets the
    /// Homebrew locations a login shell would have added via path_helper.
    static func shellEnvironment(usesProfile: Bool, shellName: String, zdotDir: String?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Explorerr"
        env["XPC_SERVICE_NAME"] = nil   // don't inherit XPC bootstrap hazards
        if !usesProfile {
            if shellName == "zsh", let zdotDir { env["ZDOTDIR"] = zdotDir }
            var path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            let parts = path.split(separator: ":").map(String.init)
            for extra in ["/opt/homebrew/bin", "/usr/local/bin"] where !parts.contains(extra) {
                path += ":" + extra
            }
            env["PATH"] = path
        }
        return env
    }

    /// Directory holding the minimal .zshrc used when the user's profile is skipped.
    private static func cleanZDotDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("explorerr-zdot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rc = """
        # Explorerr integrated terminal (clean profile).
        # Turn on "Load my shell profile" in Explorerr's Options to use your own zshrc.
        autoload -Uz colors && colors
        PS1='%F{cyan}%1~%f %# '
        export CLICOLOR=1
        """
        try? rc.write(to: dir.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        return dir
    }

    func start(cwd: URL?, cols: Int, rows: Int, usesProfile: Bool = false) {
        // A rapid restart can race the read source's cancel handler (which is what closes
        // masterFD). Bail gracefully instead of crashing; the next launch attempt succeeds.
        guard masterFD < 0 else { return }
        let shell = Self.defaultShell
        let shellName = (shell as NSString).lastPathComponent

        // Prepare everything that needs Swift/allocations BEFORE fork.
        let zdot = usesProfile ? nil : Self.cleanZDotDir().path
        let env = Self.shellEnvironment(usesProfile: usesProfile, shellName: shellName, zdotDir: zdot)
        let envEntries = env.map { "\($0.key)=\($0.value)" }

        // Login shell ("-zsh") loads the user's startup files; otherwise plain + no rc.
        var argStrings = [usesProfile ? "-\(shellName)" : shellName]
        if !usesProfile, shellName == "bash" { argStrings += ["--noprofile", "--norc"] }

        let cwdPath = cwd?.path ?? NSHomeDirectory()
        let shellCString = strdup(shell)!
        let cwdCString = strdup(cwdPath)!
        var argv: [UnsafeMutablePointer<CChar>?] = argStrings.map { strdup($0)! }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = envEntries.map { strdup($0)! }
        envp.append(nil)

        let master = posix_openpt(Int32(O_RDWR | O_NOCTTY))
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
              let slaveNameC = ptsname(master) else {
            free(shellCString); free(cwdCString)
            argv.forEach { if let p = $0 { free(p) } }
            envp.forEach { if let p = $0 { free(p) } }
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
                _ = ioctl(slave, TIOCSCTTY, 0)
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
        free(shellCString); free(cwdCString)
        argv.forEach { if let p = $0 { free(p) } }
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

    /// True when the shell itself owns the terminal foreground (no command running).
    /// The shell is its session/process-group leader (setsid in the child), so the
    /// pty's foreground pgid equals the shell pid exactly when it sits at a prompt.
    var isShellForeground: Bool {
        guard masterFD >= 0, pid > 0 else { return false }
        return tcgetpgrp(masterFD) == pid
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
