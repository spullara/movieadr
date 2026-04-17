import AVFoundation
import Observation

/// Manages AVAudioEngine-based mic recording with real-time level metering.
/// Uses zero-gain monitoring (mic audio is NOT played back through speakers).
@Observable
final class AudioRecordingService {
    private(set) var isRecording = false
    private(set) var audioLevel: Float = 0  // 0.0 to 1.0, for UI metering
    private(set) var headphonesConnected = false

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var levelUpdateTimer: Timer?

    init() {
        checkHeadphones()
        setupRouteChangeNotification()
    }

    deinit {
        stopRecording()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Recording

    func startRecording(to url: URL) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers])
        try session.setActive(true)
        #endif

        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create WAV file for output
        let wavSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        audioFile = try AVAudioFile(
            forWriting: url,
            settings: wavSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Install tap on input node — record audio, compute level, do NOT route to output
        // Pass nil format to use the input node's native hardware format (avoids format mismatch crash)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self, let file = self.audioFile else { return }

            // Write buffer to file — convert to mono if input is multi-channel
            do {
                if buffer.format.channelCount == 1 {
                    try file.write(from: buffer)
                } else {
                    // Convert multi-channel to mono
                    let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: buffer.format.sampleRate, channels: 1, interleaved: false)!
                    if let converter = AVAudioConverter(from: buffer.format, to: monoFormat),
                       let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength) {
                        var error: NSError?
                        converter.convert(to: monoBuffer, error: &error) { _, outStatus in
                            outStatus.pointee = .haveData
                            return buffer
                        }
                        if error == nil {
                            monoBuffer.frameLength = buffer.frameLength
                            try file.write(from: monoBuffer)
                        } else {
                            // Fallback: write first channel only
                            try file.write(from: buffer)
                        }
                    } else {
                        try file.write(from: buffer)
                    }
                }
            } catch {
                print("AudioRecordingService: write error: \(error)")
            }

            // Compute RMS level for metering
            let level = self.computeRMSLevel(buffer: buffer)
            Task { @MainActor in
                self.audioLevel = level
            }
        }

        // Do NOT connect inputNode to mainMixerNode — this is zero-gain monitoring
        // The engine only needs the tap installed; no output connection for mic audio.

        try engine.start()
        self.audioEngine = engine
        isRecording = true
    }

    func stopRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false
        audioLevel = 0
    }

    // MARK: - Level Metering

    private func computeRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sum: Float = 0
        let data = channelData[0]
        for i in 0..<frameLength {
            let sample = data[i]
            sum += sample * sample
        }
        let rms = sqrtf(sum / Float(frameLength))

        // Convert to 0-1 range with some scaling for visual display
        // -60dB to 0dB mapped to 0-1
        let db = 20 * log10f(max(rms, 1e-6))
        let normalized = max(0, min(1, (db + 60) / 60))
        return normalized
    }

    // MARK: - Headphone Detection

    private func checkHeadphones() {
        #if os(iOS)
        let route = AVAudioSession.sharedInstance().currentRoute
        headphonesConnected = route.outputs.contains { output in
            [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains(output.portType)
        }
        #else
        // On macOS, assume headphones are connected (no reliable detection API)
        headphonesConnected = true
        #endif
    }

    private func setupRouteChangeNotification() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkHeadphones()
        }
        #endif
    }
}
