import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DevControlCore

/// Owns the regular settings window (activating, with a standard title bar).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(appState: AppState) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsRootView(appState: appState))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Mission Control — Settings"
            newWindow.styleMask = [.titled, .closable]
            newWindow.setContentSize(NSSize(width: 460, height: 560))
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsRootView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Repositories") {
                    ForEach(appState.config.repos) { repo in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(repo.id).font(.callout.weight(.medium))
                                Text(repo.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                appState.removeRepo(id: repo.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove repository")
                        }
                    }
                    Button {
                        addRepo()
                    } label: {
                        Label("Add Repository…", systemImage: "plus")
                    }
                }

                Section("Editor") {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            if let editorPath = appState.config.editorApplicationPath {
                                Text(URL(fileURLWithPath: editorPath).lastPathComponent)
                                    .font(.callout.weight(.medium))
                                Text(editorPath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("No editor selected")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Choose Editor…") { chooseEditor() }
                        if appState.config.editorApplicationPath != nil {
                            Button("Clear") { appState.config.editorApplicationPath = nil }
                        }
                    }
                    Text("The Editor action opens the selected worktree in this application.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Scan") {
                    Stepper(value: $appState.config.refreshIntervalMinutes, in: 1...60) {
                        labeled("Refresh every", "\(appState.config.refreshIntervalMinutes) min")
                    }
                }

                Section("Attention thresholds") {
                    Stepper(value: $appState.config.staleWorktreeDays, in: 1...90) {
                        labeled("Worktree idle more than", "\(appState.config.staleWorktreeDays) days")
                    }
                    Stepper(value: $appState.config.stalePRDays, in: 1...90) {
                        labeled("PR open more than", "\(appState.config.stalePRDays) days")
                    }
                    Stepper(value: $appState.config.inactivityDays, in: 1...180) {
                        labeled("No agent activity for more than", "\(appState.config.inactivityDays) days")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Text("\(appState.config.repos.count) repositories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .bottom], 12)
        }
    }

    private func labeled(_ prefix: String, _ value: String) -> some View {
        HStack {
            Text(prefix).font(.callout)
            Spacer()
            Text(value).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private func chooseEditor() {
        let panel = NSOpenPanel()
        panel.title = "Choose Editor Application"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.applicationBundle]
        if panel.runModal() == .OK, let url = panel.url {
            appState.config.editorApplicationPath = url.standardizedFileURL.path
        }
    }

    private func addRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Users/joelmay/Documents/Projects")
        if panel.runModal() == .OK, let url = panel.url {
            appState.addRepo(path: url.path)
        }
    }
}
