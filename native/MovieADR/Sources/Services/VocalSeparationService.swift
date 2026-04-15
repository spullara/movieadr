import Foundation
import DemucsMLX

/// Manages Demucs model loading and vocal/instrumental separation.
actor VocalSeparationService {

    private var separator: DemucsSeparator?

    /// Load the Demucs model. Downloads from HuggingFace on first use.
    /// - Parameter progress: Callback for download/load progress (0.0 - 1.0)
    func loadModel(progress: @escaping (Double) -> Void) async throws {
        progress(0.0)

        // DemucsSeparator init downloads models automatically if not cached
        let sep = try DemucsSeparator(modelName: "htdemucs")
        self.separator = sep

        progress(1.0)
    }

    /// Whether the model is loaded and ready
    var isModelLoaded: Bool {
        separator != nil
    }

    /// Separate vocals from audio, saving the instrumental track.
    /// - Parameters:
    ///   - audioURL: Path to 44.1kHz stereo WAV file
    ///   - outputDir: Directory to write output files
    ///   - progress: Callback for separation progress (0.0 - 1.0)
    /// - Returns: URL to the instrumental (no_vocals) audio file
    func separate(
        audioURL: URL,
        outputDir: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> SeparationResult {
        guard let sep = separator else {
            throw VocalSeparationError.modelNotLoaded
        }

        let instrumentalURL = outputDir.appendingPathComponent("instrumental.wav")
        let vocalsURL = outputDir.appendingPathComponent("vocals.wav")

        return try await Task.detached(priority: .userInitiated) {
            try await withCheckedThrowingContinuation { continuation in
                sep.separate(
                    fileAt: audioURL,
                    cancelToken: nil,
                    interpolateProgress: true,
                    progress: { demucsProgress in
                        progress(Double(demucsProgress.fraction))
                    },
                    completion: { result in
                        autoreleasepool {
                            switch result {
                            case .success(let separationResult):
                                do {
                                    let stems = separationResult.stems
                                    if let noVocals = stems["no_vocals"] {
                                        try AudioIO.writeWAV(noVocals, to: instrumentalURL)
                                    } else {
                                        let instrumental = try self.mixStems(
                                            stems: stems,
                                            names: ["drums", "bass", "other"],
                                            sampleRate: sep.sampleRate,
                                            channels: sep.audioChannels
                                        )
                                        try AudioIO.writeWAV(instrumental, to: instrumentalURL)
                                    }

                                    if let vocals = stems["vocals"] {
                                        try AudioIO.writeWAV(vocals, to: vocalsURL)
                                    }

                                    continuation.resume(returning: SeparationResult(
                                        instrumentalURL: instrumentalURL,
                                        vocalsURL: vocalsURL
                                    ))
                                } catch {
                                    continuation.resume(throwing: error)
                                }
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                )
            }
        }.value
    }

    /// Mix multiple stems into a single audio track
    private nonisolated func mixStems(
        stems: [String: DemucsAudio],
        names: [String],
        sampleRate: Int,
        channels: Int
    ) throws -> DemucsAudio {
        let matchedStems = names.compactMap { stems[$0] }
        guard let first = matchedStems.first else {
            throw VocalSeparationError.noStemsFound
        }

        var mixed = [Float](repeating: 0, count: first.channelMajorSamples.count)
        for stem in matchedStems {
            let samples = stem.channelMajorSamples
            for i in 0..<min(mixed.count, samples.count) {
                mixed[i] += samples[i]
            }
        }

        return try DemucsAudio(channelMajor: mixed, channels: channels, sampleRate: sampleRate)
    }
}

struct SeparationResult {
    let instrumentalURL: URL
    let vocalsURL: URL
}

enum VocalSeparationError: LocalizedError {
    case modelNotLoaded
    case noStemsFound

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Demucs model not loaded"
        case .noStemsFound: return "No audio stems found in separation result"
        }
    }
}
