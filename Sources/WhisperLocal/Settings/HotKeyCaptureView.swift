import SwiftUI
import AppKit
import HotKey

struct HotKeyCaptureView: NSViewRepresentable {
    @Binding var binding: HotKeyBinding

    @MainActor
    func makeNSView(context: Context) -> CaptureField {
        let v = CaptureField()
        v.binding = $binding
        return v
    }

    @MainActor
    func updateNSView(_ nsView: CaptureField, context: Context) {
        nsView.binding = $binding
        nsView.refresh()
    }

    @MainActor
    final class CaptureField: NSView {
        var binding: Binding<HotKeyBinding>?
        private let label = NSTextField(labelWithString: "")
        private var monitor: Any?
        private var capturing = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.cornerRadius = 6
            addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            refresh()
        }

        required init?(coder: NSCoder) { fatalError() }

        override func mouseDown(with event: NSEvent) {
            capturing.toggle()
            refresh()
            if capturing { installMonitor() } else { removeMonitor() }
        }

        private func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self else { return event }
                if event.type == .flagsChanged {
                    return event
                }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                self.binding?.wrappedValue = HotKeyBinding(keyCode: UInt32(event.keyCode), modifierFlags: flags)
                self.capturing = false
                self.removeMonitor()
                self.refresh()
                return nil
            }
        }

        private func removeMonitor() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
        }

        func refresh() {
            if capturing {
                label.stringValue = "Press a key combo\u{2026}"
            } else if let b = binding?.wrappedValue {
                label.stringValue = describe(binding: b)
            }
        }

        private func describe(binding: HotKeyBinding) -> String {
            var parts = [binding.modifierFlags.description]
            if let keyCode = binding.keyCode {
                parts.append(Key(carbonKeyCode: keyCode)?.description ?? "key(\(keyCode))")
            }
            return parts.filter { !$0.isEmpty }.joined(separator: " ")
        }
    }
}
