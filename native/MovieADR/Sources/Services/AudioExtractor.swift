import AVFoundation
import Foundation

/// Extracts audio from a video file using AVAssetReader (no ffmpeg).
/// Outputs a 16kHz mono WAV for WhisperKit and a 44.1kHz stereo WAV for Demucs.
enum AudioExtractor {

    struct ExtractionResult {
        let whisperAudioURL: URL   // 16kHz mono for WhisperKit
        let demucsAudioURL: URL    // 44.1kHz stereo for Demucs
    }

    /// Extract audio from video, optionally trimmed to a time range.
    /// - Parameters:
    ///   - videoURL: Source video file
    ///   - outputDir: Directory to write audio files
    ///   - trimRange: Optional time range to extract (nil = full video)
    ///   - progress: Progress callback (0.0 - 1.0)
    static func extract(
        from videoURL: URL,
        to outputDir: URL,
        trimRange: CMTimeRange? = nil,
        progress: @escaping (Double) -> Void
    ) async throws -> ExtractionResult {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)

        let whisperURL = outputDir.appendingPathComponent("audio_16k.wav")
        let demucsURL = outputDir.appendingPathComponent("audio_44k.wav")

        // Extract 16kHz mono for WhisperKit
        progress(0.0)
        try await extractAudio(
            from: asset,
            to: whisperURL,
            sampleRate: 16000,
            channels: 1,
            trimRange: trimRange,
            duration: duration
        )
        progress(0.5)

        // Extract 44.1kHz stereo for Demucs
        try await extractAudio(
            from: asset,
            to: demucsURL,
            sampleRate: 44100,
            channels: 2,
            trimRange: trimRange,
            duration: duration
        )
        progress(1.0)

        return ExtractionResult(whisperAudioURL: whisperURL, demucsAudioURL: demucsURL)
    }

    private static func extractAudio(
        from asset: AVURLAsset,
        to outputURL: URL,
        sampleRate: Double,
        channels: UInt32,
        trimRange: CMTimeRange?,
        duration: CMTime
    ) async throws {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw AudioExtractorError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        if let range = trimRange {
            reader.timeRange = range
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(readerOutput)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: true
        ) else {
            throw AudioExtractorError.formatCreationFailed
        }

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings
        )

        guard reader.startReading() else {
            throw AudioExtractorError.readerStartFailed(reader.error?.localizedDescription ?? "Unknown")
        }

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            _ = data.withUnsafeMutableBytes { ptr in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
            }

            let frameCount = AVAudioFrameCount(length / (Int(channels) * 2))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else { continue }
            buffer.frameLength = frameCount
            data.withUnsafeBytes { rawPtr in
                let src = rawPtr.baseAddress!
                memcpy(buffer.int16ChannelData![0], src, length)
            }
            try outputFile.write(from: buffer)
        }

        guard reader.status == .completed else {
            throw AudioExtractorError.readingFailed(reader.error?.localizedDescription ?? "Unknown")
        }
    }
}

enum AudioExtractorError: LocalizedError {
    case noAudioTrack
    case formatCreationFailed
    case readerStartFailed(String)
    case readingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "Video has no audio track"
        case .formatCreationFailed: return "Failed to create audio format"
        case .readerStartFailed(let msg): return "Failed to start reading: \(msg)"
        case .readingFailed(let msg): return "Audio reading failed: \(msg)"
        }
    }
}
