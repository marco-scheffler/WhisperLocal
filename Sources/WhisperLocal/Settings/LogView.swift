import SwiftUI
import AppKit

struct LogView: View {
    @ObservedObject var store: LogStore = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(store.entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(store.asText, forType: .string)
                }
                .buttonStyle(.borderless)
                Button("Clear") {
                    store.clear()
                }
                .buttonStyle(.borderless)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(store.entries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.timeString)
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .foregroundStyle(color(for: entry.level))
                                    .textSelection(.enabled)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(height: 200)
                .onChange(of: store.entries.count) { _, _ in
                    if let last = store.entries.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private func color(for level: LogEntry.Level) -> Color {
        switch level {
        case .info: return .primary
        case .warn: return .orange
        case .error: return .red
        }
    }
}
