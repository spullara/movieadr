import SwiftUI
import SwiftData

/// Assembles the video player, teleprompter canvas overlay, transport controls,
/// recording UI, and take list.
struct PlayerContainerView: View {
    let project: Project

    @State private var controller: PlayerController?
    @State private var words: [TimedWord] = []
    @State private var waveform: WaveformPeaks?
    @State private var recordingVM: RecordingViewModel?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            if let controller {
                // Video + overlay
                ZStack {
                    VideoLayerView(player: controller.player)

                    TeleprompterCanvasView(
                        words: words,
                        waveform: waveform,
                        currentTime: controller.currentTime,
                        duration: controller.duration
                    )
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipped()

                // Recording level meter (shown during recording)
                if let vm = recordingVM {
                    RecordingLevelMeterView(
                        level: vm.audioLevel,
                        isRecording: vm.isRecording
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }

                // Transport controls with record button
                if let vm = recordingVM {
                    TransportControlsView(
                        controller: controller,
                        recordingVM: vm,
                        modelContext: modelContext
                    )
                } else {
                    TransportControlsView(
                        controller: controller,
                        recordingVM: nil,
                        modelContext: modelContext
                    )
                }

                // Take list
                if let vm = recordingVM {
                    TakeListView(
                        project: project,
                        recordingVM: vm
                    )
                }
            } else {
                ProgressView("Loading video…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.black)
        .task {
            loadProject()
        }
        .alert("Headphones Recommended",
               isPresented: Binding(
                   get: { recordingVM?.showHeadphoneWarning ?? false },
                   set: { if !$0 { recordingVM?.dismissHeadphoneWarning() } }
               )
        ) {
            Button("OK") { recordingVM?.dismissHeadphoneWarning() }
        } message: {
            Text("Connect headphones to prevent speaker audio from being picked up by the microphone during recording.")
        }
        .alert("Recording Error",
               isPresented: Binding(
                   get: { recordingVM?.error != nil },
                   set: { if !$0 { /* error cleared */ } }
               )
        ) {
            Button("OK") { }
        } message: {
            Text(recordingVM?.error ?? "")
        }
    }

    private func loadProject() {
        // Build video URL
        guard let videoPath = project.videoRelativePath else { return }
        let videoURL = project.directoryURL.appendingPathComponent(videoPath)
        controller = PlayerController(url: videoURL)

        // Seek to trim start if the video was trimmed
        if let trimStart = project.trimStart {
            controller?.seek(to: trimStart)
        }

        // Set trim bounds so playback stays within the trimmed range
        controller?.trimStart = project.trimStart ?? 0
        controller?.trimEnd = project.trimEnd

        // Load instrumental audio (mutes video, plays instrumental instead)
        if let instrumentalPath = project.instrumentalRelativePath {
            let instrumentalURL = project.directoryURL.appendingPathComponent(instrumentalPath)
            controller?.loadInstrumental(url: instrumentalURL)
        } else {
            // Fallback: try standard filename
            let fallbackURL = project.directoryURL.appendingPathComponent("instrumental.wav")
            if FileManager.default.fileExists(atPath: fallbackURL.path) {
                controller?.loadInstrumental(url: fallbackURL)
            }
        }

        recordingVM = RecordingViewModel(project: project)

        // Load word timestamps
        if let data = project.timestampsJSON {
            do {
                words = try JSONDecoder().decode([TimedWord].self, from: data)
            } catch {
                print("Failed to decode timestamps: \(error)")
            }
        }

        // Load waveform peaks
        let waveformURL: URL?
        if let waveformPath = project.waveformPeaksRelativePath {
            waveformURL = project.directoryURL.appendingPathComponent(waveformPath)
        } else {
            // Fallback for projects prepared before waveformPeaksRelativePath was added
            let fallbackURL = project.directoryURL.appendingPathComponent("waveform_peaks.json")
            waveformURL = FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil
        }
        if let url = waveformURL, let data = try? Data(contentsOf: url) {
            waveform = try? JSONDecoder().decode(WaveformPeaks.self, from: data)
            // Backfill the relative path for future loads
            if waveform != nil && project.waveformPeaksRelativePath == nil {
                project.waveformPeaksRelativePath = "waveform_peaks.json"
            }
        }
    }
}
