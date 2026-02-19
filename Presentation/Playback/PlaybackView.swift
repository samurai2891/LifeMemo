import SwiftUI

/// Audio playback view with synchronized transcript highlighting.
///
/// Shows playback controls at the top and a scrollable transcript below.
/// Tapping a segment seeks to that position. The currently playing
/// segment is highlighted and auto-scrolled into view.
struct PlaybackView: View {

    @ObservedObject var controller: SyncedPlaybackController
    @ObservedObject var audioPlayer: AudioPlayer
    @EnvironmentObject private var coordinator: RecordingCoordinator

    @State private var isDragging = false
    @State private var dragTimeMs: Int64 = 0

    var body: some View {
        VStack(spacing: 0) {
            // Playback controls
            playbackControls
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))

            Divider()

            // Synced transcript
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(controller.segments) { segment in
                            segmentRow(segment)
                                .id(segment.id)
                                .onTapGesture {
                                    controller.seekToSegment(segment.id)
                                }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: controller.activeSegmentId) { _, newId in
                    if let id = newId {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .overlay { RecordingIndicatorOverlay() }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        VStack(spacing: 12) {
            // Time and progress
            VStack(spacing: 4) {
                // Progress bar
                GeometryReader { geometry in
                    let total = max(1, audioPlayer.totalDurationMs)
                    let current = isDragging ? dragTimeMs : audioPlayer.currentTimeMs
                    let progress = CGFloat(current) / CGFloat(total)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray4))
                            .frame(height: 4)

                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * min(1, progress), height: 4)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let ratio = value.location.x / geometry.size.width
                                dragTimeMs = Int64(Double(total) * Double(max(0, min(1, ratio))))
                            }
                            .onEnded { _ in
                                audioPlayer.seekTo(ms: dragTimeMs)
                                isDragging = false
                            }
                    )
                }
                .frame(height: 4)

                // Time labels
                HStack {
                    Text(formatMs(isDragging ? dragTimeMs : audioPlayer.currentTimeMs))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(formatMs(audioPlayer.totalDurationMs))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Control buttons
            HStack(spacing: 32) {
                // Speed control
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button("\(rate, specifier: "%.2g")x") {
                            audioPlayer.playbackRate = Float(rate)
                        }
                    }
                } label: {
                    Text("\(audioPlayer.playbackRate, specifier: "%.2g")x")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Skip backward
                Button {
                    audioPlayer.skipBackward()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }

                // Play/Pause
                Button {
                    switch audioPlayer.state {
                    case .playing:
                        audioPlayer.pause()
                    case .finished:
                        audioPlayer.seekTo(ms: 0)
                        audioPlayer.play()
                    default:
                        audioPlayer.play()
                    }
                } label: {
                    Image(systemName: audioPlayer.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                }

                // Skip forward
                Button {
                    audioPlayer.skipForward()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }

                // Stop
                Button {
                    audioPlayer.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Segment Row

    private func segmentRow(_ segment: SyncedPlaybackController.SegmentDisplay) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Time label
            Text(formatMs(segment.startMs))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(segment.isActive ? Color.accentColor : .secondary)
                .frame(width: 44, alignment: .trailing)

            HStack(alignment: .top, spacing: 0) {
                // Speaker accent line
                if segment.speakerIndex >= 0 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(SpeakerColors.color(for: segment.speakerIndex))
                        .frame(width: 2)
                        .padding(.trailing, 6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Speaker label
                    if let name = segment.speakerName, segment.speakerIndex >= 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(SpeakerColors.color(for: segment.speakerIndex))
                                .frame(width: 6, height: 6)

                            Text(name)
                                .font(.caption2.bold())
                                .foregroundStyle(SpeakerColors.color(for: segment.speakerIndex))
                        }
                    }

                    // Text
                    Text(segment.text)
                        .font(.body)
                        .foregroundStyle(segment.isActive ? .primary : .secondary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(segment.isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .animation(.easeInOut(duration: 0.2), value: segment.isActive)
        }
    }

    // MARK: - Formatting

    private func formatMs(_ ms: Int64) -> String {
        let totalSec = ms / 1000
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
