import SwiftUI
import SwiftData

@main
struct MovieADRApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Project.self, Take.self, ExportJob.self])
    }
}
