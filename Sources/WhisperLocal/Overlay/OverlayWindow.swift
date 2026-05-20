import AppKit
import SwiftUI

@MainActor
final class OverlayWindow {
    let state = OverlayState()
    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: OverlayView(state: state))
        positionBottomCenter()
    }

    func show() {
        positionBottomCenter()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        state.phase = .hidden
    }

    private func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let frame = panel.frame
        let x = screen.visibleFrame.midX - frame.width / 2
        let y = screen.visibleFrame.minY + 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
