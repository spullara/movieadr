import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var selectedProject: Project?

    #if os(macOS)
    @State private var youtubeURL = ""
    @State private var downloadService = YouTubeDownloadService()
    @State private var showYtDlpMissing = false
    @State private var showTrimView = false
    @State private var downloadedVideoURL: URL?
    @State private var downloadedProject: Project?
    #endif

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(projects, selection: $selectedProject) { project in
                    NavigationLink(value: project) {
                        VStack(alignment: .leading) {
                            Text(project.name)
                                .font(.headline)
                            Text(project.createdAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .overlay {
                    if projects.isEmpty {
                        ContentUnavailableView(
                            "No Projects",
                            systemImage: "film.stack",
                            description: Text("Import a video to get started.")
                        )
                    }
                }

                #if os(macOS)
                youtubeDownloadSection
                #endif
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addProject) {
                        Label("New Project", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let project = selectedProject {
                ProjectDetailView(project: project)
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "film",
                    description: Text("Choose a project from the sidebar or create a new one.")
                )
            }
        }
        #if os(macOS)
        .alert("yt-dlp Not Installed", isPresented: $showYtDlpMissing) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Install yt-dlp via Homebrew:\nbrew install yt-dlp")
        }
        .sheet(isPresented: $showTrimView) {
            if let url = downloadedVideoURL, let project = downloadedProject {
                VideoTrimView(
                    videoURL: url,
                    project: Binding(
                        get: { project },
                        set: { _ in }
                    )
                )
            }
        }
        #endif
    }

    private func addProject() {
        let project = Project(name: "New Project")
        modelContext.insert(project)
        selectedProject = project
    }

    #if os(macOS)
    private var youtubeDownloadSection: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(.red)
                TextField("YouTube URL", text: $youtubeURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await startYouTubeDownload() } }
                Button(action: { Task { await startYouTubeDownload() } }) {
                    Image(systemName: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(youtubeURL.isEmpty || downloadService.isDownloading)
            }

            if downloadService.isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: downloadService.progress)
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @MainActor
    private func startYouTubeDownload() async {
        let urlString = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }

        guard YouTubeDownloadService.isYtDlpInstalled() else {
            showYtDlpMissing = true
            return
        }

        let project = Project(name: "YouTube Download")
        modelContext.insert(project)

        do {
            let videoURL = try await downloadService.download(
                url: urlString,
                to: project.directoryURL
            )
            project.videoRelativePath = videoURL.lastPathComponent
            downloadedVideoURL = videoURL
            downloadedProject = project
            selectedProject = project
            youtubeURL = ""
            showTrimView = true
        } catch {
            // Error is shown via downloadService.error
            // Clean up the empty project on failure
            modelContext.delete(project)
        }
    }
    #endif
}

#Preview {
    ContentView()
        .modelContainer(for: [Project.self, Take.self, ExportJob.self], inMemory: true)
}
