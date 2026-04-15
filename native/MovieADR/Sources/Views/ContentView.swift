import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var selectedProject: Project?

    @State private var renamingProject: Project?
    @State private var renameText = ""
    @State private var showRenameAlert = false
    @State private var newProjectName = ""
    @State private var showNewProjectAlert = false

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
                    .contextMenu {
                        Button("Rename") {
                            renamingProject = project
                            renameText = project.name
                            showRenameAlert = true
                        }
                        Button("Delete", role: .destructive) {
                            try? FileManager.default.removeItem(at: project.directoryURL)
                            if selectedProject?.id == project.id {
                                selectedProject = nil
                            }
                            modelContext.delete(project)
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

            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addProject) {
                        Label("New Project", systemImage: "plus")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
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
        .alert("Rename Project", isPresented: $showRenameAlert) {
            TextField("Project name", text: $renameText)
            Button("Save") {
                renamingProject?.name = renameText
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Project", isPresented: $showNewProjectAlert) {
            TextField("Project name", text: $newProjectName)
            Button("Create") {
                let project = Project(name: newProjectName.isEmpty ? "New Project" : newProjectName)
                modelContext.insert(project)
                selectedProject = project
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func addProject() {
        newProjectName = ""
        showNewProjectAlert = true
    }

}

#Preview {
    ContentView()
        .modelContainer(for: [Project.self, Take.self, ExportJob.self], inMemory: true)
}
