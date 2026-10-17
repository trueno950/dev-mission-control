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
            newWindow.title = L10n.t("Mission Control — Ajustes", "Mission Control — Settings")
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
                Section(L10n.t("Repositorios", "Repositories")) {
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
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(repo.isPaused ? L10n.t("Pausado", "Paused") : L10n.t("Activo", "Active"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(repo.isPaused ? Color.orange : Color.green)
                                Toggle(L10n.t("Pausar proyecto", "Pause project"), isOn: Binding(
                                    get: { repo.isPaused },
                                    set: { appState.setPaused(path: repo.path, isPaused: $0) }
                                ))
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .font(.caption2)
                                .help(L10n.t("Pausa los avisos de inactividad y de worktrees limpios inactivos de este proyecto", "Pause inactivity and idle-clean-worktree notices for this project"))
                                .accessibilityLabel(L10n.t("Pausar \(repo.id)", "Pause \(repo.id)"))
                            }
                            Button(role: .destructive) {
                                appState.removeRepo(id: repo.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(L10n.t("Quitar repositorio", "Remove repository"))
                        }
                    }
                    Button {
                        addRepo()
                    } label: {
                        Label(L10n.t("Agregar repositorio…", "Add Repository…"), systemImage: "plus")
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
                                Text(L10n.t("Sin editor seleccionado", "No editor selected"))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(L10n.t("Elegir editor…", "Choose Editor…")) { chooseEditor() }
                        if appState.config.editorApplicationPath != nil {
                            Button(L10n.t("Quitar", "Clear")) { appState.config.editorApplicationPath = nil }
                        }
                    }
                    Text(L10n.t("La acción Editor abre el worktree seleccionado en esta aplicación.", "The Editor action opens the selected worktree in this application."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.t("Escaneo", "Scan")) {
                    Stepper(value: $appState.config.refreshIntervalMinutes, in: 1...60) {
                        labeled(L10n.t("Escanear cada", "Refresh every"), "\(appState.config.refreshIntervalMinutes) min")
                    }
                }

                Section(L10n.t("Umbrales de atención", "Attention thresholds")) {
                    Stepper(value: $appState.config.staleWorktreeDays, in: 1...90) {
                        labeled(L10n.t("Worktree inactivo más de", "Worktree idle more than"), "\(appState.config.staleWorktreeDays) \(L10n.t("días", "days"))")
                    }
                    Stepper(value: $appState.config.stalePRDays, in: 1...90) {
                        labeled(L10n.t("PR abierta más de", "PR open more than"), "\(appState.config.stalePRDays) \(L10n.t("días", "days"))")
                    }
                    Stepper(value: $appState.config.inactivityDays, in: 1...180) {
                        labeled(L10n.t("Sin actividad del agente más de", "No agent activity more than"), "\(appState.config.inactivityDays) \(L10n.t("días", "days"))")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Text(L10n.t("\(appState.config.repos.count) repositorios", "\(appState.config.repos.count) repositories"))
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
        panel.title = L10n.t("Elegir aplicación editora", "Choose Editor Application")
        panel.message = L10n.t("Elegí la aplicación que abrirá los worktrees.",
                               "Choose the application that will open worktrees.")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.applicationBundle]
        // Anchor the picker on the installed-applications list instead of a
        // generic file browser.
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
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
