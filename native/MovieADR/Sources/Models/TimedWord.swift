import Foundation

/// A single word with timing information, matching the JSON produced by WhisperKit.
struct TimedWord: Codable, Identifiable {
    let word: String
    let start: Double // seconds
    let end: Double   // seconds

    var id: Double { start }
    var duration: Double { end - start }
}
