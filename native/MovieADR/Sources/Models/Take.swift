import Foundation
import SwiftData

@Model
final class Take {
    var id: UUID
    var takeNumber: Int
    var recordedAt: Date
    
    /// Relative path to the recorded audio file within the project directory
    var audioRelativePath: String?
    
    /// Duration of the recording in seconds
    var duration: Double?
    
    /// User rating (optional)
    var rating: Int?
    
    /// Notes about this take
    var notes: String?
    
    var project: Project?
    
    init(takeNumber: Int, project: Project) {
        self.id = UUID()
        self.takeNumber = takeNumber
        self.recordedAt = Date()
        self.project = project
    }
}
