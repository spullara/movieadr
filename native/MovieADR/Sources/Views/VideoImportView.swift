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
}
