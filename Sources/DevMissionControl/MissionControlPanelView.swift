import SwiftUI

/// Root view of the status panel: header with the total attention count,
/// one card per tracked project, and a footer. T1 ships the skeleton with an
/// empty state; scanners and real cards arrive in T2–T6.
struct MissionControlPanelView: View {
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)
            ScrollView {
                VStack(spacing: 12) {
                    emptyState
                }
                .padding(14)
            }
            Divider().opacity(0.25)
            footer
        }
        .frame(width: 380, height: 520)
        .background(VisualEffectBackground().ignoresSafeArea())
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.cyan.gradient)
            Text("Mission Control")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Text("0 need attention")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No projects tracked yet")
                .font(.headline)
            Text("Add repositories from Settings to see\nPRs, CI, worktrees and last activity.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var footer: some View {
        HStack {
            Text("Dev Mission Control")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
