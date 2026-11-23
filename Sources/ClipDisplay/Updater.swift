import AppKit

/// Self-updater that pulls the latest version from GitHub.
///
/// Two cases, depending on where the running bundle lives:
/// - **Source checkout** (`<repo>/ClipDisplay.app`): fetch the tracked branch,
///   pull, rebuild with `build-app.sh`, relaunch the same bundle.
/// - **Anywhere else** (e.g. `/Applications`): compare the commit stamped into
///   the build against GitHub's `HEAD`, clone the latest source, build it, then
///   swap the new bundle over the running one and relaunch.
enum Updater {
    private enum CheckResult {
        case upToDate
        case updateAvailable(behind: Int?)
        case failed(String)
    }

    private static let git = "/usr/bin/git"
    private static let remoteURL = "https://github.com/coreyloftus/clipdisplay.git"
    private static var progressWindow: NSWindow?

    /// "1.0 (abc1234)" — shown in Settings.
    static var versionDescription: String {
        guard let commit = installedCommit else { return currentVersion }
        return "\(currentVersion) (\(commit.prefix(7)))"
    }

    /// Entry point for the menu item and Settings button. Runs the (blocking)
    /// git work off the main thread, then presents the outcome.
    static func checkForUpdates() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = check()
            DispatchQueue.main.async { present(result) }
        }
    }

    // MARK: - Checking

    /// The git checkout the running bundle was built in, or nil when the app
    /// isn't sitting inside its source repo.
    private static func repoURL() -> URL? {
        let parent = URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent()
        let fm = FileManager.default
        let hasGit = fm.fileExists(atPath: parent.appendingPathComponent(".git").path)
        let hasBuildScript = fm.fileExists(atPath: parent.appendingPathComponent("build-app.sh").path)
        return (hasGit && hasBuildScript) ? parent : nil
    }

    private static func check() -> CheckResult {
        if let repo = repoURL() { return checkCheckout(repo) }
        return checkRemote()
    }

    private static func checkCheckout(_ repo: URL) -> CheckResult {
        let fetch = run(git, ["fetch", "--quiet"], cwd: repo)
        if fetch.status != 0 {
            return .failed("Couldn't reach GitHub to check for updates.\n\n\(fetch.output)")
        }

        let local = run(git, ["rev-parse", "HEAD"], cwd: repo)
        let remote = run(git, ["rev-parse", "@{u}"], cwd: repo)
        guard local.status == 0, remote.status == 0 else {
            return .failed("Couldn't determine the latest version.\n\n\(remote.output)")
        }
        if local.output == remote.output { return .upToDate }

        let behind = Int(run(git, ["rev-list", "--count", "HEAD..@{u}"], cwd: repo).output)
        return .updateAvailable(behind: behind)
    }

    private static func checkRemote() -> CheckResult {
        let head = run(git, ["ls-remote", remoteURL, "HEAD"])
        guard head.status == 0, let latest = head.output.split(whereSeparator: \.isWhitespace).first else {
            return .failed("Couldn't reach GitHub to check for updates.\n\n\(head.output)")
        }
        if String(latest) == installedCommit { return .upToDate }
        return .updateAvailable(behind: nil)
    }

    // MARK: - Presenting results

    private static func present(_ result: CheckResult) {
        switch result {
        case .upToDate:
            info("You're up to date",
                 "ClipDisplay \(versionDescription) is the latest version.")

        case .updateAvailable(let behind):
            let alert = NSAlert()
            alert.messageText = "An update is available"
            let what: String
            switch behind {
            case 1?: what = "1 new commit is available."
            case let n?: what = "\(n) new commits are available."
            case nil: what = "A newer version is available on GitHub."
            }
            alert.informativeText = "\(what) ClipDisplay will download the latest version, rebuild it, and relaunch. This takes about a minute."
            alert.addButton(withTitle: "Update & Relaunch")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { performUpdate() }

        case .failed(let message):
            warn("Couldn't check for updates", message)
        }
    }

    // MARK: - Performing the update

    private static func performUpdate() {
        showProgress()
        DispatchQueue.global(qos: .userInitiated).async {
            if let repo = repoURL() {
                updateCheckout(repo)
            } else {
                updateDownloaded()
            }
        }
    }

    private static func updateCheckout(_ repo: URL) {
        let pull = run(git, ["pull", "--ff-only", "--quiet"], cwd: repo)
        if pull.status != 0 {
            fail("Update failed",
                 "Couldn't pull the latest changes — you may have local edits in the checkout.\n\n\(pull.output)")
            return
        }
        if let error = build(in: repo) { fail("Rebuild failed", error); return }
        DispatchQueue.main.async { relaunch(installing: nil) }
    }

    private static func updateDownloaded() {
        let bundle = URL(fileURLWithPath: Bundle.main.bundlePath)
        guard FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) else {
            fail("Update failed", "ClipDisplay can't write to \(bundle.deletingLastPathComponent().path).")
            return
        }

        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipDisplay-update-\(UUID().uuidString)")
        let clone = run(git, ["clone", "--depth", "1", remoteURL, source.path])
        if clone.status != 0 {
            fail("Update failed", "Couldn't download the latest version.\n\n\(clone.output)")
            return
        }
        if let error = build(in: source) { fail("Rebuild failed", error); return }

        DispatchQueue.main.async { relaunch(installing: source.appendingPathComponent("ClipDisplay.app")) }
    }

    /// Runs `build-app.sh` in `dir`; returns an error message on failure.
    private static func build(in dir: URL) -> String? {
        let script = dir.appendingPathComponent("build-app.sh").path
        let build = run("/bin/bash", [script], cwd: dir)
        guard build.status != 0 else { return nil }
        return "Building the latest version failed. Check that the developer command-line tools are installed.\n\n\(build.output)"
    }

    /// Wait for this instance to quit, optionally swap in a freshly built
    /// bundle, then reopen it.
    private static func relaunch(installing newBundle: URL?) {
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        var script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; "
        if let newBundle {
            script += "/bin/rm -rf \"\(bundlePath)\" && /usr/bin/ditto \"\(newBundle.path)\" \"\(bundlePath)\"; "
        }
        script += "/usr/bin/open \"\(bundlePath)\""

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run() // orphaned to launchd; survives our termination

        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static var installedCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "GitCommit") as? String
    }

    /// Run a command, capturing merged stdout/stderr. Reads output before
    /// waiting on exit so large output can't deadlock the pipe.
    private static func run(_ launchPath: String, _ args: [String], cwd: URL? = nil) -> (status: Int32, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        if let cwd { proc.currentDirectoryURL = cwd }
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (proc.terminationStatus, output)
    }

    private static func showProgress() {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        let label = NSTextField(labelWithString: "Updating ClipDisplay… this takes about a minute.")
        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "ClipDisplay"
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        progressWindow = window
    }

    private static func fail(_ title: String, _ message: String) {
        DispatchQueue.main.async {
            progressWindow?.close()
            progressWindow = nil
            warn(title, message)
        }
    }

    private static func info(_ title: String, _ message: String) {
        alert(title, message, style: .informational)
    }

    private static func warn(_ title: String, _ message: String) {
        alert(title, message, style: .warning)
    }

    private static func alert(_ title: String, _ message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
