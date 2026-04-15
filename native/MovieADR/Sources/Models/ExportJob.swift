import Foundation
import SwiftData

enum ExportStatus: String, Codable {
    case pending
    case inProgress
    case completed
    case failed
}

@Model
final class ExportJob {
    var id: UUID
    var createdAt: Date
    var status: ExportStatus
    
    /// Which take to use for the export
    var takeID: UUID?
    
    /// Relative path to the exported video file
    var outputRelativePath: String?
    
    /// Error message if export failed
    var errorMessage: String?
    
    /// Export progress (0.0 - 1.0)
    var progress: Double
    
    var project: Project?
    
    init(project: Project, takeID: UUID) {
        self.id = UUID()
        self.createdAt = Date()
        self.status = .pending
        self.takeID = takeID
        self.progress = 0.0
        self.project = project
    }
}
