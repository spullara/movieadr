import SwiftUI
#if os(iOS)
import Photos
#endif

/// Lets the user pick a take, export the video with mixed audio, and share/save the result.
struct ExportView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTake: Take?
    @State private var exportService = ExportService()
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if exportService.isExporting {
                    exportingView
                } else if let url = exportedURL {
                    completedView(url: url)
                } else {
                    takeSelectionView
                }
            }
            .padding()
            .navigationTitle("Export Video")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        exportService.cancel()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Take Selection

    @ViewBuilder
    private var takeSelectionView: some View {
        if project.takes.isEmpty {
            ContentUnavailableView(
                "No Takes",
                systemImage: "mic.slash",
                description: Text("Record a take first, then come back to export.")
            )
        } else {
            Text("Select a take to export")
                .font(.headline)

            List(project.takes.sorted(by: { $0.takeNumber < $1.takeNumber }), selection: $selectedTake) { take in
                HStack {
                    Image(systemName: selectedTake?.id == take.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedTake?.id == take.id ? .blue : .secondary)
                    VStack(alignment: .leading) {
                        Text("Take \(take.takeNumber)")
                            .font(.body.bold())
                        if let dur = take.duration {
                            Text(formatDuration(dur))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(take.recordedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedTake = take }
            }
            .listStyle(.plain)

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button(action: startExport) {
                Label("Export Video", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTake == nil)
        }
    }

    // MARK: - Exporting Progress

    private var exportingView: some View {
        VStack(spacing: 16) {
            ProgressView(value: exportService.progress) {
                Text("Exporting…")
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(exportService.progress * 100))%")
                    .font(.caption.monospacedDigit())
            }
            .progressViewStyle(.linear)

            Button("Cancel Export", role: .destructive) {
                exportService.cancel()
            }
        }
    }

    // MARK: - Completed

    private func completedView(url: URL) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Export Complete!")
                .font(.title3.bold())

            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)

            ShareLink(item: url) {
                Label("Share / Save Video", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)

            #if os(iOS)
            Button(action: { saveToPhotos(url: url) }) {
                Label("Save to Photos", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            #endif

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions

    private func startExport() {
        guard let take = selectedTake else { return }
        errorMessage = nil

        Task {
            do {
                let url = try await exportService.export(project: project, take: take)
                exportedURL = url
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    #if os(iOS)
    private func saveToPhotos(url: URL) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    self.errorMessage = nil
                } else {
                    self.errorMessage = error?.localizedDescription ?? "Failed to save to Photos"
                }
            }
        }
    }
    #endif

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
