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

        guard reader.startReading() else {
            throw AudioExtractorError.readerStartFailed(reader.error?.localizedDescription ?? "Unknown")
        }

        // Write raw WAV file directly instead of using AVAudioPCMBuffer
        // This avoids the crash with interleaved Int16 data and int16ChannelData
        let bitsPerSample: UInt16 = 16
        let blockAlign = UInt16(channels) * (bitsPerSample / 8)
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)

        // Write placeholder WAV header (44 bytes), will update sizes after writing data
        let handle = try FileHandle(forWritingTo: {
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            return outputURL
        }())
        defer { try? handle.close() }

        // RIFF header
        handle.write("RIFF".data(using: .ascii)!)
        handle.write(Data(repeating: 0, count: 4))  // placeholder for file size - 8
        handle.write("WAVE".data(using: .ascii)!)
        // fmt chunk
        handle.write("fmt ".data(using: .ascii)!)
        handle.write(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })  // chunk size
        handle.write(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })   // PCM format
        handle.write(withUnsafeBytes(of: UInt16(channels).littleEndian) { Data($0) })
        handle.write(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        handle.write(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        handle.write(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        handle.write(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        // data chunk header
        handle.write("data".data(using: .ascii)!)
        handle.write(Data(repeating: 0, count: 4))  // placeholder for data size

        var totalDataBytes: UInt32 = 0

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            _ = data.withUnsafeMutableBytes { ptr in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
            }
            handle.write(data)
            totalDataBytes += UInt32(length)
        }

        guard reader.status == .completed else {
            throw AudioExtractorError.readingFailed(reader.error?.localizedDescription ?? "Unknown")
        }

        // Update WAV header with actual sizes
        let fileSize = totalDataBytes + 36  // total file size minus 8 bytes for RIFF header
        handle.seek(toFileOffset: 4)
        handle.write(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        handle.seek(toFileOffset: 40)
        handle.write(withUnsafeBytes(of: totalDataBytes.littleEndian) { Data($0) })
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
