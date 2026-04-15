import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var createdAt: Date
    
    /// Relative path to the imported video within the project's directory
    var videoRelativePath: String?
    
    /// Whether the preparation pipeline has completed
    var isPrepared: Bool
    
    /// Word-level timestamps JSON (populated by WhisperKit)
    var timestampsJSON: Data?
    
    /// Relative path to the instrumental audio track (populated by Demucs)
    var instrumentalRelativePath: String?
    
    /// Relative path to the vocals audio track (populated by Demucs)
    var vocalsRelativePath: String?

    /// Relative path to the waveform peaks JSON
    var waveformPeaksRelativePath: String?

    /// Video trim start time in seconds (nil = beginning)
    var trimStart: Double?
    
    /// Video trim end time in seconds (nil = end)
    var trimEnd: Double?
    
    @Relationship(deleteRule: .cascade, inverse: \Take.project)
    var takes: [Take]
    
    @Relationship(deleteRule: .cascade, inverse: \ExportJob.project)
    var exportJobs: [ExportJob]
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.isPrepared = false
        self.takes = []
        self.exportJobs = []
    }
    
    /// Returns the project's directory within the app's Documents folder
    var directoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appending(path: "Projects/\(id.uuidString)")
    }

    /// Returns the full URL to the imported video, if one exists
    var videoURL: URL? {
        guard let relativePath = videoRelativePath else { return nil }
        return directoryURL.appendingPathComponent(relativePath)
    }
}
