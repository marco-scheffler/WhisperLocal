import SwiftUI
import AppKit

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
            var parts: [String] = []
            let f = binding.modifierFlags
            if f.contains(.control) { parts.append("\u{2303}") }
            if f.contains(.option) { parts.append("\u{2325}") }
            if f.contains(.shift) { parts.append("\u{21E7}") }
            if f.contains(.command) { parts.append("\u{2318}") }
            if binding.keyCode != 0 {
                parts.append(KeyName.from(keyCode: binding.keyCode) ?? "key(\(binding.keyCode))")
            }
            return parts.joined(separator: " ")
        }
    }
}

enum KeyName {
    static func from(keyCode: UInt32) -> String? {
        let map: [UInt32: String] = [
            0x31: "Space", 0x24: "Return", 0x35: "Escape", 0x33: "Delete",
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E",
        ]
        return map[keyCode]
    }
}
