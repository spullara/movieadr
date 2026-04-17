import SwiftUI
import SwiftData

/// Play/pause/seek transport bar for the video player, with optional record button.
struct TransportControlsView: View {
    @Bindable var controller: PlayerController
    var recordingVM: RecordingViewModel?
    var modelContext: ModelContext

    var body: some View {
        VStack(spacing: 4) {
            // Seek slider (disabled during recording, hidden until duration loads)
            if controller.duration > 0 {
                Slider(
                    value: Binding(
                        get: { controller.currentTime },
                        set: { controller.seek(to: $0) }
                    ),
                    in: controller.trimStart...max(controller.trimEnd ?? controller.duration, controller.trimStart + 0.01)
                )
                .disabled(recordingVM?.isRecording ?? false)
            } else {
                // Placeholder while duration loads
                ProgressView()
                    .frame(height: 20)
            }

            HStack {
                // Play/pause
                Button(action: {
                    controller.togglePlayPause()
                    handlePlayPauseRecording()
                }) {
                    Label(controller.isPlaying ? "Pause" : "Play",
                          systemImage: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body)
                }
                .buttonStyle(.bordered)

                // Skip backward 5s (disabled during recording)
                Button(action: { controller.seek(to: max(controller.trimStart, controller.currentTime - 5)) }) {
                    Image(systemName: "gobackward.5")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(recordingVM?.isRecording ?? false)

                // Skip forward 5s (disabled during recording)
                Button(action: { controller.seek(to: min(controller.trimEnd ?? controller.duration, controller.currentTime + 5)) }) {
                    Image(systemName: "goforward.5")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(recordingVM?.isRecording ?? false)

                // Record button
                if let vm = recordingVM {
                    Button(action: { toggleRecording(vm: vm) }) {
                        Label(
                            vm.isRecording ? "Stop Rec" : "Record + Play",
                            systemImage: vm.isRecording ? "stop.fill" : "record.circle"
                        )
                        .font(.body)
                        .foregroundStyle(vm.isRecording ? .red : .white)
                    }
                    .buttonStyle(.bordered)
                    .tint(vm.isRecording ? .red : .red.opacity(0.7))
                    .padding(.leading, 8)
                }

                Spacer()

                // Recording indicator
                if recordingVM?.isRecording ?? false {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("REC")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                }

                // Time display
                Text("\(formatTime(controller.currentTime)) / \(formatTime(controller.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6))
        .colorScheme(.dark)
    }

    private func toggleRecording(vm: RecordingViewModel) {
        if vm.isRecording {
            // Stop recording and video
            vm.stopRecording(modelContext: modelContext)
            controller.pause()
        } else {
            // Start recording - seek to trim start first, then play
            vm.startRecording(modelContext: modelContext)
            // Only play if recording actually started
            if vm.isRecording {
                controller.seek(to: controller.trimStart) {
                    controller.play()
                }
            }
        }
    }

    /// When user presses play/pause while recording, auto-stop recording
    private func handlePlayPauseRecording() {
        guard let vm = recordingVM, vm.isRecording else { return }
        if !controller.isPlaying {
            // User paused → stop recording
            vm.stopRecording(modelContext: modelContext)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
