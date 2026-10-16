import AppKit
import SwiftUI

/// Borderless, non-activating panel shown under the menu bar, styled after
/// system menu extras (Control Center look).
final class StatusPanel: NSPanel {
    private var monitor: Any?

    init(content: some View) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
                   styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        contentView = NSHostingView(rootView: content)
        startOutsideClickMonitor()
    }

    override var canBecomeKey: Bool { true }

    func placeBelowStatusBarItem(_ item: NSStatusItem) {
        guard let button = item.button, let buttonWindow = button.window else { return }
        let frame = buttonWindow.frame
        let width = self.frame.width
        let x = max(8, frame.midX - width / 2)
        let y = frame.minY - 8
        setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    private func startOutsideClickMonitor() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible else { return }
            if !self.frame.contains(NSEvent.mouseLocation) {
                self.orderOut(nil)
            }
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

/// Native behind-window vibrancy used as the panel background.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.masksToBounds = true
        view.layer?.cornerCurve = .continuous
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
