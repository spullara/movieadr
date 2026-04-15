import SwiftUI
import SwiftData

/// Play/pause/seek transport bar for the video player, with optional record button.
struct TransportControlsView: View {
    @Bindable var controller: PlayerController
    var recordingVM: RecordingViewModel?
    var modelContext: ModelContext

    var body: some View {
        VStack(spacing: 4) {
            // Seek slider (disabled during recording)
            Slider(
                value: Binding(
                    get: { controller.currentTime },
                    set: { controller.seek(to: $0) }
                ),
                in: 0...max(controller.duration, 0.01)
            )
            .disabled(recordingVM?.isRecording ?? false)

            HStack {
                // Play/pause
                Button(action: {
                    controller.togglePlayPause()
                    handlePlayPauseRecording()
                }) {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)

                // Skip backward 5s (disabled during recording)
                Button(action: { controller.seek(to: max(0, controller.currentTime - 5)) }) {
                    Image(systemName: "gobackward.5")
                }
                .buttonStyle(.plain)
                .disabled(recordingVM?.isRecording ?? false)

                // Skip forward 5s (disabled during recording)
                Button(action: { controller.seek(to: min(controller.duration, controller.currentTime + 5)) }) {
                    Image(systemName: "goforward.5")
                }
                .buttonStyle(.plain)
                .disabled(recordingVM?.isRecording ?? false)

                // Record button
                if let vm = recordingVM {
                    Button(action: { toggleRecording(vm: vm) }) {
                        ZStack {
                            Circle()
                                .fill(vm.isRecording ? .red : .red.opacity(0.7))
                                .frame(width: 28, height: 28)

                            if vm.isRecording {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.white)
                                    .frame(width: 10, height: 10)
                            } else {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
    }

    private func toggleRecording(vm: RecordingViewModel) {
        if vm.isRecording {
            // Stop recording and video
            vm.stopRecording(modelContext: modelContext)
            controller.pause()
        } else {
            // Start recording and video from current position
            vm.startRecording(modelContext: modelContext)
            if !controller.isPlaying {
                controller.play()
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
