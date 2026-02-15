import SwiftUI

/// A floating overlay shown on all screens when recording is active.
///
/// Displays a pulsing red dot, "REC" label, and elapsed time in a
/// translucent capsule. This is required for App Store compliance (2.5.14)
/// to ensure the user always knows the microphone is active.
struct RecordingIndicatorOverlay: View {

    // MARK: - Environment

    @EnvironmentObject private var coordinator: RecordingCoordinator

    // MARK: - State

    @State private var isPulsing = false

    // MARK: - Body

    var body: some View {
        if coordinator.state.isRecording {
            VStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true),
                            value: isPulsing
                        )

                    Text("REC")
                        .font(.caption.bold())
                        .foregroundStyle(.red)

                    Text(Self.formatElapsed(coordinator.elapsedSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .onAppear { isPulsing = true }

                Spacer()
            }
            .padding(.top, 4)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Formatting

    static func formatElapsed(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60

        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    RecordingIndicatorOverlay()
}
