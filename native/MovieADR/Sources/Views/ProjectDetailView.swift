import SwiftUI
import SwiftData
import AVFoundation

struct ProjectDetailView: View {
    @Bindable var project: Project
    @State private var showExportSheet = false
    @State private var showTrimView = false
    @State private var pipeline = PreparationPipeline()
    @State private var isProcessing = false

    var body: some View {
        Group {
            if project.isPrepared {
                preparedView
            } else if project.videoRelativePath != nil {
                needsProcessingView
            } else {
                VideoImportView(project: Binding(get: { project }, set: { _ in }))
                    .padding()
            }
        }
        .navigationTitle(project.name)
        .sheet(isPresented: $showTrimView) {
            if let videoURL = project.videoURL {
                VideoTrimView(
                    videoURL: videoURL,
                    project: Binding(get: { project }, set: { _ in })
                )
            }
        }
    }

    @ViewBuilder
    private var needsProcessingView: some View {
        VStack(spacing: 16) {
            if isProcessing {
                // Progress view while pipeline is running
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)

                    Text(pipeline.statusMessage.isEmpty ? "Processing..." : pipeline.statusMessage)
                        .font(.headline)

                    ProgressView(value: pipeline.overallProgress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 300)

                    Text("\(Int(pipeline.overallProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if let error = pipeline.error {
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("Video imported. Ready to process.")
                    .font(.headline)

                Text("Trim the video first, or process the full video directly.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 16) {
                    Button {
                        showTrimView = true
                    } label: {
                        Label("Trim & Process", systemImage: "timeline.selection")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await processFullVideo() }
                    } label: {
                        Label("Process Full Video", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
    }

    private func processFullVideo() async {
        guard let videoURL = project.videoURL else { return }
        isProcessing = true
        do {
            try await pipeline.run(
                videoURL: videoURL,
                projectDir: project.directoryURL
            )
            project.isPrepared = true
            project.instrumentalRelativePath = "instrumental.wav"
            project.vocalsRelativePath = "vocals.wav"
            let timestampsURL = project.directoryURL.appendingPathComponent("word_timestamps.json")
            project.timestampsJSON = try Data(contentsOf: timestampsURL)
        } catch {
            // Error is shown via pipeline.error
        }
        isProcessing = false
    }

    @ViewBuilder
    private var preparedView: some View {
        VStack(spacing: 0) {
            // Video player with teleprompter overlay
            PlayerContainerView(project: project)

            // Info bar below the player
            HStack(spacing: 16) {
                statusDot(done: project.timestampsJSON != nil, label: "Words")
                statusDot(done: project.instrumentalRelativePath != nil, label: "Instrumental")
                statusDot(done: project.vocalsRelativePath != nil, label: "Vocals")

                Spacer()

                if !project.takes.isEmpty {
                    Text("\(project.takes.count) take\(project.takes.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(action: { showExportSheet = true }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportView(project: project)
        }
    }

    private func statusDot(done: Bool, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(done ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }


}
