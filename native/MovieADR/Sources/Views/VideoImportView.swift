import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

/// Handles video file import via document picker.
struct VideoImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var project: Project
    @State private var isPickerPresented = false
    @State private var importedVideoURL: URL?
    @State private var showTrimView = false
    @State private var importError: String?

    #if os(macOS)
    @State private var youtubeURL = ""
    @State private var downloadService = YouTubeDownloadService()
    @State private var showYtDlpMissing = false
    #endif

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Import a Video")
                .font(.title2)

            Text("Select a video file to begin ADR processing.")
                .foregroundStyle(.secondary)

            Button(action: { isPickerPresented = true }) {
                Label("Choose Video", systemImage: "doc.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            #if os(macOS)
            Divider()
                .padding(.vertical, 8)

            Text("Or download from YouTube")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(.red)
                TextField("YouTube URL", text: $youtubeURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await startYouTubeDownload() } }
                Button(action: { Task { await startYouTubeDownload() } }) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(youtubeURL.isEmpty || downloadService.isDownloading)
            }
            .frame(maxWidth: 400)

            if downloadService.isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: downloadService.progress)
                        .frame(maxWidth: 400)
                    Text(downloadService.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = downloadService.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            #endif

            if let error = importError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showTrimView) {
            if let url = importedVideoURL {
                VideoTrimView(
                    videoURL: url,
                    project: $project
                )
            }
        }
        #if os(macOS)
        .alert("yt-dlp Not Installed", isPresented: $showYtDlpMissing) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Install yt-dlp via Homebrew:\nbrew install yt-dlp")
        }
        #endif
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else { return }
            importError = nil

            // Start security-scoped access
            guard sourceURL.startAccessingSecurityScopedResource() else {
                importError = "Cannot access the selected file."
                return
            }
            defer { sourceURL.stopAccessingSecurityScopedResource() }

            do {
                // Copy video to project directory
                let projectDir = project.directoryURL
                try FileManager.default.createDirectory(
                    at: projectDir,
                    withIntermediateDirectories: true
                )

                let destFilename = "source_video" + "." + sourceURL.pathExtension
                let destURL = projectDir.appendingPathComponent(destFilename)

                // Remove existing file if any
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.copyItem(at: sourceURL, to: destURL)

                project.videoRelativePath = destFilename
                importedVideoURL = destURL
                showTrimView = true
            } catch {
                importError = "Failed to import video: \(error.localizedDescription)"
            }

        case .failure(let error):
            importError = "Import failed: \(error.localizedDescription)"
        }
    }

    #if os(macOS)
    @MainActor
    private func startYouTubeDownload() async {
        let urlString = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }

        guard YouTubeDownloadService.isYtDlpInstalled() else {
            showYtDlpMissing = true
            return
        }

        do {
            let projectDir = project.directoryURL
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            let videoURL = try await downloadService.download(url: urlString, to: projectDir)
            project.videoRelativePath = videoURL.lastPathComponent
            importedVideoURL = videoURL
            youtubeURL = ""
            showTrimView = true
        } catch {
            importError = "YouTube download failed: \(error.localizedDescription)"
        }
    }
    #endif
}
