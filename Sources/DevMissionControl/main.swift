import AppKit
import SwiftUI
import DevControlCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: StatusPanel?
    private let settingsController = SettingsWindowController()
    private lazy var detailController = RepositoryDetailWindowController()
    private lazy var engramPanelController = EngramPanelWindowController()
    private lazy var appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = StatusPanel(content: MissionControlPanelView(
            appState: appState,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenDetail: { [weak self] repoPath, focusWorktreePath in
                guard let self else { return }
                self.detailController.show(
                    appState: self.appState,
                    repoPath: repoPath,
                    focusWorktreePath: focusWorktreePath,
                    onOpenSettings: { [weak self] in self?.openSettings() },
                    onOpenEngramPanel: { [weak self] in
                        guard let self else { return }
                        self.engramPanelController.show(appState: self.appState,
                                                        repoPath: repoPath)
                    })
            },
            onOpenEngramPanel: { [weak self] repoPath in
                guard let self else { return }
                self.engramPanelController.show(appState: self.appState, repoPath: repoPath)
            },
            onQuit: { NSApp.terminate(nil) }
        ))
        self.panel = panel

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "scope",
                                   accessibilityDescription: "Dev Mission Control")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        panel.placeBelowStatusBarItem(item)
        appState.startAutoRefresh()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent, let button = statusItem?.button else {
            togglePanel()
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu(for: button)
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        guard let panel, let statusItem else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.placeBelowStatusBarItem(statusItem)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func showContextMenu(for button: NSStatusBarButton) {
        let menu = NSMenu()
        let settingsItem = menu.addItem(withTitle: L10n.t("Ajustes…", "Settings…"),
                                        action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t("Salir de Dev Mission Control", "Quit Dev Mission Control"),
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openSettings() {
        panel?.orderOut(nil)
        settingsController.show(appState: appState)
    }
}

// MARK: - Headless scan mode

/// `--scan-once`: runs the full pipeline against the configured repositories,
/// prints a summary, and exits. Used for functional verification without UI.
private func runScanOnceAndExit() -> Never {
    let store = AppState.makeDefaultStore()
    let config = (try? store.load()) ?? nil ?? .default

    let gitScanner = GitScanner()
    let ghScanner = GhScanner()
    let engramScanner = EngramScanner()
    let now = Date()
    let calendar = Calendar.current
    var exitCode: Int32 = 0

    for repo in config.repos where repo.enabled {
        let git = gitScanner.scan(repoPath: repo.path, now: now, calendar: calendar)
        let pr = ghScanner.scan(repoPath: repo.path, slugOverride: repo.githubSlug,
                                now: now, calendar: calendar)

        let semaphore = DispatchSemaphore(value: 0)
        var activity = ActivityStatus()
        let project = repo.resolvedEngramProject
        Task {
            activity = await engramScanner.scan(project: project)
            semaphore.signal()
        }
        semaphore.wait()

        let snapshot = RepoSnapshot(config: repo, git: git, pr: pr, activity: activity)
        let items = AttentionMath.classify(snapshot, now: now, calendar: calendar,
                                           thresholds: config)

        print("== \(repo.id) (\(repo.path))")
        if let branch = git.branch { print("   \(L10n.t("rama:", "branch:")) \(branch)") }
        if !pr.available, let error = pr.error { print("   prs: \(L10n.t("no disponible", "unavailable")) (\(error))") }
        if !activity.available, let error = activity.error {
            print("   engram: \(L10n.t("no disponible", "unavailable")) (\(error))")
        }
        if items.isEmpty {
            print("   \(L10n.t("sin hallazgos", "clean"))")
        } else {
            exitCode = 1
            for item in items {
                print("   [\(item.severity)] \(item.message)")
            }
        }
    }
    exit(exitCode)
}

MainActor.assumeIsolated {
    if ProcessInfo.processInfo.arguments.contains("--scan-once") {
        runScanOnceAndExit()
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
