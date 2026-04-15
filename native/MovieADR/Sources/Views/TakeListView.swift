import SwiftUI
import SwiftData

/// Displays a scrollable list of recorded takes with playback and delete controls.
struct TakeListView: View {
    let project: Project
    @Bindable var recordingVM: RecordingViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Takes", systemImage: "mic.fill")
                    .font(.headline)
                Spacer()
                Text("\(sortedTakes.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.2), in: Capsule())
            }

            if sortedTakes.isEmpty {
                Text("No takes recorded yet. Press record to start.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(sortedTakes, id: \.id) { take in
                            takeRow(take)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(12)
    }

    private var sortedTakes: [Take] {
        project.takes.sorted { $0.takeNumber < $1.takeNumber }
    }

    private func takeRow(_ take: Take) -> some View {
        HStack(spacing: 8) {
            // Take number
            Text("Take \(take.takeNumber)")
                .font(.subheadline.monospacedDigit())

            // Duration
            if let duration = take.duration {
                Text(formatDuration(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Play/stop button
            let isPlaying = recordingVM.playingTake?.id == take.id
            Button(action: {
                if isPlaying {
                    recordingVM.stopTakePlayback()
                } else {
                    recordingVM.playTake(take)
                }
            }) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .foregroundStyle(isPlaying ? .red : .accentColor)
            }
            .buttonStyle(.plain)

            // Delete button
            Button(action: {
                recordingVM.deleteTake(take, modelContext: modelContext)
            }) {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(recordingVM.playingTake?.id == take.id ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
