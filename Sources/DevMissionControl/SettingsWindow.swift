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
            newWindow.title = "Mission Control — Ajustes"
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
                Section("Repositorios") {
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
                                Text(repo.isPaused ? "Pausado" : "Activo")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(repo.isPaused ? Color.orange : Color.green)
                                Toggle("Pausar proyecto", isOn: Binding(
                                    get: { repo.isPaused },
                                    set: { appState.setPaused(path: repo.path, isPaused: $0) }
                                ))
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .font(.caption2)
                                .help("Pausa los avisos de inactividad y de worktrees limpios inactivos de este proyecto")
                                .accessibilityLabel("Pausar \(repo.id)")
                            }
                            Button(role: .destructive) {
                                appState.removeRepo(id: repo.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Quitar repositorio")
                        }
                    }
                    Button {
                        addRepo()
                    } label: {
                        Label("Agregar repositorio…", systemImage: "plus")
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
                                Text("Sin editor seleccionado")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Elegir editor…") { chooseEditor() }
                        if appState.config.editorApplicationPath != nil {
                            Button("Quitar") { appState.config.editorApplicationPath = nil }
                        }
                    }
                    Text("La acción Editor abre el worktree seleccionado en esta aplicación.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Escaneo") {
                    Stepper(value: $appState.config.refreshIntervalMinutes, in: 1...60) {
                        labeled("Escanear cada", "\(appState.config.refreshIntervalMinutes) min")
                    }
                }

                Section("Umbrales de atención") {
                    Stepper(value: $appState.config.staleWorktreeDays, in: 1...90) {
                        labeled("Worktree inactivo más de", "\(appState.config.staleWorktreeDays) días")
                    }
                    Stepper(value: $appState.config.stalePRDays, in: 1...90) {
                        labeled("PR abierta más de", "\(appState.config.stalePRDays) días")
                    }
                    Stepper(value: $appState.config.inactivityDays, in: 1...180) {
                        labeled("Sin actividad del agente más de", "\(appState.config.inactivityDays) días")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Text("\(appState.config.repos.count) repositorios")
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
