import AppKit

/// Self-updater for source/in-repo builds.
///
/// ClipDisplay ships as a `.app` assembled by `build-app.sh` inside its git
/// checkout (the bundle sits at `<repo>/ClipDisplay.app`). "Check for Update"
/// fetches the checkout's tracked branch and, if the running build is behind,
/// pulls the latest commits, rebuilds via `build-app.sh`, and relaunches.
///
/// When the app isn't running from its checkout (e.g. it was copied to
/// `/Applications`), there's nothing to rebuild, so it explains how to update
/// manually instead.
enum Updater {
    private enum CheckResult {
        case upToDate
        case updateAvailable(behind: Int)
        case notAGitCheckout
        case failed(String)
    }

    private static let git = "/usr/bin/git"

    /// Entry point for the menu item. Runs the (blocking) git work off the main
    /// thread, then presents the outcome.
    static func checkForUpdates() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = check()
            DispatchQueue.main.async { present(result) }
        }
    }

    // MARK: - Git checks

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
        guard let repo = repoURL() else { return .notAGitCheckout }

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

        let behind = Int(run(git, ["rev-list", "--count", "HEAD..@{u}"], cwd: repo).output) ?? 0
        return .updateAvailable(behind: behind)
    }

    // MARK: - Presenting results

    private static func present(_ result: CheckResult) {
        switch result {
        case .upToDate:
            info("You're up to date",
                 "ClipDisplay \(currentVersion) is the latest version.")

        case .updateAvailable(let behind):
            let commits = behind == 1 ? "1 new commit is" : "\(behind) new commits are"
            let alert = NSAlert()
            alert.messageText = "An update is available"
            alert.informativeText = "\(commits) available. ClipDisplay will pull the latest changes, rebuild, and relaunch. This takes about a minute."
            alert.addButton(withTitle: "Update & Relaunch")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn, let repo = repoURL() {
                performUpdate(repo: repo)
            }

        case .notAGitCheckout:
            info("Automatic update unavailable",
                 "ClipDisplay can only update itself when it runs from its source checkout. "
                 + "To update, open the clipdisplay repository, run:\n\n    git pull\n    ./build-app.sh\n\n"
                 + "then relaunch the rebuilt app.")

        case .failed(let message):
            warn("Couldn't check for updates", message)
        }
    }

    // MARK: - Performing the update

    private static func performUpdate(repo: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let pull = run(git, ["pull", "--ff-only", "--quiet"], cwd: repo)
            if pull.status != 0 {
                DispatchQueue.main.async {
                    warn("Update failed",
                         "Couldn't pull the latest changes — you may have local edits in the checkout.\n\n\(pull.output)")
                }
                return
            }

            let script = repo.appendingPathComponent("build-app.sh").path
            let build = run("/bin/bash", [script], cwd: repo)
            if build.status != 0 {
                DispatchQueue.main.async {
                    warn("Rebuild failed",
                         "The latest changes were pulled, but rebuilding the app failed. Check that the developer command-line tools are installed.\n\n\(build.output)")
                }
                return
            }

            DispatchQueue.main.async { relaunch() }
        }
    }

    /// Wait for this instance to quit, then reopen the freshly rebuilt bundle.
    private static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let waitAndOpen = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"\(bundlePath)\""

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", waitAndOpen]
        try? task.run() // orphaned to launchd; survives our termination

        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
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
