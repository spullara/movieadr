import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    @Bindable var project: Project
    @State private var showExportSheet = false

    var body: some View {
        Group {
            if project.isPrepared {
                preparedView
            } else if project.videoRelativePath != nil {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Video imported. Processing needed.")
                        .font(.headline)
                    Text("Open the project to trim and process the video.")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                VideoImportView(project: Binding(get: { project }, set: { _ in }))
                    .padding()
            }
        }
        .navigationTitle(project.name)
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
