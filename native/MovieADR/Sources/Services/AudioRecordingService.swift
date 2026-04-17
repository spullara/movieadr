import AVFoundation
import Observation

@Observable
final class AudioRecordingService {
    private(set) var isRecording = false
    private(set) var audioLevel: Float = 0
    private(set) var headphonesConnected = false

    #if os(iOS)
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    #else
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    #endif

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
        #if os(iOS)
        try startRecordingIOS(to: url)
        #else
        try startRecordingMacOS(to: url)
        #endif
    }

    func stopRecording() {
        #if os(iOS)
        stopRecordingIOS()
        #else
        stopRecordingMacOS()
        #endif
    }

    // MARK: - iOS Recording (AVAudioRecorder)

    #if os(iOS)
    private func startRecordingIOS(to url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .mixWithOthers])
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()
        self.audioRecorder = recorder
        isRecording = true

        // Start level metering timer
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }
            recorder.updateMeters()
            let db = recorder.averagePower(forChannel: 0) // -160 to 0
            let normalized = max(0, min(1, (db + 60) / 60))
            Task { @MainActor in
                self.audioLevel = normalized
            }
        }

        print("[AudioRecordingService] iOS recording started to: \(url.lastPathComponent)")
    }

    private func stopRecordingIOS() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder?.stop()
        if let url = audioRecorder?.url {
            print("[AudioRecordingService] iOS recording stopped, file: \(url.lastPathComponent)")
        }
        audioRecorder = nil
        isRecording = false
        audioLevel = 0
    }
    #endif

    // MARK: - macOS Recording (AVAudioEngine)

    #if os(macOS)
    private func startRecordingMacOS(to url: URL) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)

        let wavSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: tapFormat.sampleRate,
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

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            guard let self, let file = self.audioFile else { return }
            do {
                if buffer.format.channelCount == 1 {
                    try file.write(from: buffer)
                } else {
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
                            try file.write(from: buffer)
                        }
                    } else {
                        try file.write(from: buffer)
                    }
                }
            } catch {
                print("AudioRecordingService: write error: \(error)")
            }

            let level = self.computeRMSLevel(buffer: buffer)
            Task { @MainActor in
                self.audioLevel = level
            }
        }

        // Connect input through silent mixer for macOS
        let silentMixer = AVAudioMixerNode()
        engine.attach(silentMixer)
        engine.connect(inputNode, to: silentMixer, format: tapFormat)
        engine.connect(silentMixer, to: engine.mainMixerNode, format: tapFormat)
        silentMixer.outputVolume = 0

        engine.prepare()
        try engine.start()
        self.audioEngine = engine
        isRecording = true
        print("[AudioRecordingService] macOS recording started, format: \(tapFormat)")
    }

    private func stopRecordingMacOS() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false
        audioLevel = 0
    }
    #endif

    // MARK: - Level Metering (macOS only — iOS uses AVAudioRecorder metering)

    private func computeRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        let data = channelData[0]
        for i in 0..<frameLength {
            let sample = data[i]
            sum += sample * sample
        }
        let rms = sqrtf(sum / Float(frameLength))
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
