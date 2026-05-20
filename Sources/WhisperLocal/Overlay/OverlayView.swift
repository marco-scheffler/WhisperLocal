import SwiftUI

struct OverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        HStack(spacing: 12) {
            indicator
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(minWidth: 160, maxWidth: 360)
    }

    @ViewBuilder private var indicator: some View {
        switch state.phase {
        case .recording:
            Circle().fill(.red).frame(width: 10, height: 10)
                .scaleEffect(1 + CGFloat(min(state.level * 4, 1)))
                .animation(.easeOut(duration: 0.1), value: state.level)
        case .transcribing, .postProcessing:
            ProgressView().controlSize(.small)
        case .injecting:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .hidden:
            EmptyView()
        }
    }

    private var label: String {
        switch state.phase {
        case .hidden: return ""
        case .recording: return "Recording\u{2026}"
        case .transcribing: return "Transcribing\u{2026}"
        case .postProcessing: return "Cleaning up\u{2026}"
        case .injecting: return "Pasting"
        case .error(let msg): return msg
        }
    }
}
