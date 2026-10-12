import AppKit
import Carbon.HIToolbox

struct PasteboardSnapshot: Sendable {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = pasteboard.pasteboardItems ?? []
        let snapshot: [[NSPasteboard.PasteboardType: Data]] = items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
        return PasteboardSnapshot(items: snapshot)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let newItems: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(newItems)
    }
}

@MainActor
final class TextInjector {
    func inject(_ text: String) {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pb)

        pb.clearContents()
        pb.setString(text, forType: .string)
        // nspasteboard.org convention: clipboard managers skip transient
        // content, so dictations don't pile up in their history.
        pb.setData(Data(), forType: .transient)
        let ownChangeCount = pb.changeCount

        postCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // If anything was copied in the meantime, it is newer than the
            // snapshot — keep it.
            guard pb.changeCount == ownChangeCount else { return }
            snapshot.restore(to: pb)
        }
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

extension NSPasteboard.PasteboardType {
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}
