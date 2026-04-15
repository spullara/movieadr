import AVFoundation
import SwiftUI

/// Trim view with thumbnail scrubber and draggable start/end handles.
/// User sets in/out points to select the scene they want.
struct VideoTrimView: View {
    let videoURL: URL
    @Binding var project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var duration: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0
    @State private var thumbnails: [CGImage] = []
    @State private var isLoading = true
    @State private var pipeline = PreparationPipeline()
    @State private var isProcessing = false

    private let thumbnailCount = 20
    private let scrubberHeight: CGFloat = 60

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView("Loading video...")
                } else {
                    trimTimeDisplay
                    thumbnailScrubber
                    processingSection
                }
            }
            .padding()
            .navigationTitle("Trim Video")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isProcessing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isProcessing ? "Processing..." : "Process") {
                        Task { await startProcessing() }
                    }
                    .disabled(isProcessing)
                }
            }
        }
        .task { await loadVideoInfo() }
    }

    private var trimTimeDisplay: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Start").font(.caption).foregroundStyle(.secondary)
                Text(formatTime(trimStart)).font(.headline.monospacedDigit())
            }
            Spacer()
            VStack {
                Text("Duration").font(.caption).foregroundStyle(.secondary)
                Text(formatTime(trimEnd - trimStart)).font(.headline.monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("End").font(.caption).foregroundStyle(.secondary)
                Text(formatTime(trimEnd)).font(.headline.monospacedDigit())
            }
        }
        .padding(.horizontal)
    }

    private var thumbnailScrubber: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                // Thumbnail strip
                HStack(spacing: 0) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, img in
                        Image(decorative: img, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: width / CGFloat(thumbnailCount), height: scrubberHeight)
                            .clipped()
                    }
                }

                // Dimmed regions outside trim
                let startX = width * trimStart / duration
                let endX = width * trimEnd / duration

                Rectangle().fill(.black.opacity(0.5))
                    .frame(width: max(startX, 0), height: scrubberHeight)

                Rectangle().fill(.black.opacity(0.5))
                    .frame(width: max(width - endX, 0), height: scrubberHeight)
                    .offset(x: endX)

                // Start handle
                trimHandle(color: .yellow, xPosition: startX)
                    .gesture(DragGesture().onChanged { v in
                        let newStart = max(0, min(v.location.x / width * duration, trimEnd - 0.5))
                        trimStart = newStart
                    })

                // End handle
                trimHandle(color: .yellow, xPosition: endX)
                    .gesture(DragGesture().onChanged { v in
                        let newEnd = max(trimStart + 0.5, min(v.location.x / width * duration, duration))
                        trimEnd = newEnd
                    })
            }
        }
        .frame(height: scrubberHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func trimHandle(color: Color, xPosition: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 8, height: scrubberHeight + 8)
            .offset(x: xPosition - 4)
            .shadow(radius: 2)
    }

    private var processingSection: some View {
        Group {
            if isProcessing {
                VStack(spacing: 8) {
                    Text(pipeline.statusMessage)
                        .font(.subheadline)
                    ProgressView(value: pipeline.overallProgress)
                    Text("\(Int(pipeline.overallProgress * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = pipeline.error {
                        Text(error.localizedDescription)
                            .foregroundStyle(.red).font(.caption)
                    }
                }
            } else {
                Text("Drag the yellow handles to select the scene you want, or press Process to use the full video.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private func loadVideoInfo() async {
        let asset = AVURLAsset(url: videoURL)
        if let dur = try? await asset.load(.duration) {
            duration = dur.seconds
            trimEnd = dur.seconds
        }
        await generateThumbnails(asset: asset)
        isLoading = false
    }

    private func generateThumbnails(asset: AVURLAsset) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 80)

        var images: [CGImage] = []
        for i in 0..<thumbnailCount {
            let time = CMTime(seconds: duration * Double(i) / Double(thumbnailCount), preferredTimescale: 600)
            if let img = try? generator.copyCGImage(at: time, actualTime: nil) {
                images.append(img)
            }
        }
        thumbnails = images
    }

    private func startProcessing() async {
        isProcessing = true
        let isFullVideo = trimStart == 0 && trimEnd == duration

        let trimRange: CMTimeRange? = isFullVideo ? nil : CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: trimEnd, preferredTimescale: 600)
        )

        project.trimStart = isFullVideo ? nil : trimStart
        project.trimEnd = isFullVideo ? nil : trimEnd

        do {
            try await pipeline.run(
                videoURL: videoURL,
                projectDir: project.directoryURL,
                trimRange: trimRange
            )
            project.isPrepared = true

            // Store relative paths
            project.instrumentalRelativePath = "instrumental.wav"
            project.vocalsRelativePath = "vocals.wav"

            // Load timestamps into project
            let timestampsURL = project.directoryURL.appendingPathComponent("word_timestamps.json")
            project.timestampsJSON = try Data(contentsOf: timestampsURL)

            dismiss()
        } catch {
            // Error is shown via pipeline.error
        }
        isProcessing = false
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds - Double(Int(seconds))) * 10)
        return String(format: "%d:%02d.%d", mins, secs, frac)
    }
}
