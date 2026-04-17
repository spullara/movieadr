import Foundation
import WhisperKit

/// Word-level timestamp entry for serialization
struct WordTimestamp: Codable {
    let word: String
    let start: Float
    let end: Float
    let probability: Float
}

/// Manages WhisperKit model loading and transcription with word-level timestamps.
actor TranscriptionService {

    private var whisperKit: WhisperKit?

    /// Load the WhisperKit model. Downloads on first use.
    /// - Parameter progress: Callback for download/load progress (0.0 - 1.0)
    func loadModel(progress: @escaping (Double) -> Void) async throws {
        progress(0.0)
        let config = WhisperKitConfig()
        #if os(iOS)
        config.model = "small"
        #else
        config.model = "large-v3"
        #endif
        config.download = true
        config.prewarm = true

        let kit = try await WhisperKit(config)
        self.whisperKit = kit
        progress(1.0)
    }

    /// Whether the model is loaded and ready
    var isModelLoaded: Bool {
        whisperKit != nil
    }

    /// Transcribe audio file and return word-level timestamps.
    /// - Parameters:
    ///   - audioURL: Path to 16kHz mono WAV file
    ///   - progress: Callback for transcription progress (0.0 - 1.0)
    /// - Returns: Array of word timestamps
    func transcribe(
        audioURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> [WordTimestamp] {
        guard let kit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        progress(0.0)

        let options = DecodingOptions(
            wordTimestamps: true,
            chunkingStrategy: .vad
        )

        let results: [TranscriptionResult] = try await kit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )

        progress(0.8)

        var words: [WordTimestamp] = []
        for result in results {
            for segment in result.segments {
                if let segmentWords = segment.words {
                    for w in segmentWords {
                        words.append(WordTimestamp(
                            word: w.word,
                            start: w.start,
                            end: w.end,
                            probability: w.probability
                        ))
                    }
                }
            }
        }

        progress(1.0)
        return words
    }

    /// Save word timestamps as JSON
    static func saveTimestamps(_ words: [WordTimestamp], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(words)
        try data.write(to: url)
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "WhisperKit model not loaded"
        }
    }
}
