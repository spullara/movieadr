import Accelerate
import AVFoundation
import Foundation

/// Waveform peak data for visualization
struct WaveformPeaks: Codable {
    let sampleRate: Int
    let samplesPerPeak: Int
    let peaks: [Float]
    let duration: Double
}

/// Generates waveform peak data from audio using the Accelerate framework.
enum WaveformGenerator {

    /// Generate waveform peaks from an audio file.
    /// - Parameters:
    ///   - audioURL: Path to audio file (WAV)
    ///   - peaksPerSecond: Number of peaks per second of audio (default 100)
    ///   - progress: Progress callback (0.0 - 1.0)
    /// - Returns: WaveformPeaks data
    static func generatePeaks(
        from audioURL: URL,
        peaksPerSecond: Int = 100,
        progress: @escaping (Double) -> Void
    ) throws -> WaveformPeaks {
        progress(0.0)

        let file = try AVAudioFile(forReading: audioURL)
        let format = file.processingFormat
        let sampleRate = Int(format.sampleRate)
        let totalFrames = Int(file.length)
        let channelCount = Int(format.channelCount)

        let samplesPerPeak = sampleRate / peaksPerSecond
        let peakCount = (totalFrames + samplesPerPeak - 1) / samplesPerPeak

        // Read all audio into a buffer
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ) else {
            throw WaveformError.bufferAllocationFailed
        }

        try file.read(into: buffer)
        progress(0.3)

        guard let channelData = buffer.floatChannelData else {
            throw WaveformError.noChannelData
        }

        // Mix to mono if multichannel
        var monoSamples = [Float](repeating: 0, count: totalFrames)
        if channelCount == 1 {
            memcpy(&monoSamples, channelData[0], totalFrames * MemoryLayout<Float>.size)
        } else {
            // Average all channels using temp buffer to avoid overlapping access
            let scale = 1.0 / Float(channelCount)
            for ch in 0..<channelCount {
                var scaled = [Float](repeating: 0, count: totalFrames)
                var s = scale
                vDSP_vsmul(channelData[ch], 1, &s, &scaled, 1, vDSP_Length(totalFrames))
                vDSP_vadd(scaled, 1, monoSamples, 1, &monoSamples, 1, vDSP_Length(totalFrames))
            }
        }

        progress(0.5)

        // Compute absolute values for peak detection
        var absSamples = [Float](repeating: 0, count: totalFrames)
        vDSP_vabs(monoSamples, 1, &absSamples, 1, vDSP_Length(totalFrames))

        // Generate peaks using Accelerate
        var peaks = [Float](repeating: 0, count: peakCount)
        for i in 0..<peakCount {
            let start = i * samplesPerPeak
            let count = min(samplesPerPeak, totalFrames - start)
            guard count > 0 else { break }

            var maxVal: Float = 0
            absSamples.withUnsafeBufferPointer { ptr in
                vDSP_maxv(ptr.baseAddress! + start, 1, &maxVal, vDSP_Length(count))
            }
            peaks[i] = maxVal

            if i % 1000 == 0 {
                progress(0.5 + 0.5 * Double(i) / Double(peakCount))
            }
        }

        progress(1.0)

        let duration = Double(totalFrames) / Double(sampleRate)
        return WaveformPeaks(
            sampleRate: sampleRate,
            samplesPerPeak: samplesPerPeak,
            peaks: peaks,
            duration: duration
        )
    }

    /// Save waveform peaks as JSON
    static func savePeaks(_ peaks: WaveformPeaks, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(peaks)
        try data.write(to: url)
    }
}

enum WaveformError: LocalizedError {
    case formatCreationFailed
    case bufferAllocationFailed
    case noChannelData

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed: return "Failed to create audio format for waveform"
        case .bufferAllocationFailed: return "Failed to allocate audio buffer"
        case .noChannelData: return "No channel data in audio buffer"
        }
    }
}
