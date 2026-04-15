import AVFoundation
import Foundation
import Observation

/// Pipeline step identifiers
enum PipelineStep: String, CaseIterable {
    case downloadingModels = "Downloading Models"
    case extractingAudio = "Extracting Audio"
    case transcribing = "Transcribing Speech"
    case separatingVocals = "Separating Vocals"
    case generatingWaveform = "Generating Waveform"
    case complete = "Complete"
}

/// Observable model for the preparation pipeline.
/// Orchestrates: audio extraction → WhisperKit → Demucs → waveform peaks.
@Observable
final class PreparationPipeline {
    var currentStep: PipelineStep = .downloadingModels
    var stepProgress: Double = 0.0
    var overallProgress: Double = 0.0
    var isRunning = false
    var error: Error?
    var statusMessage = ""

    // Step weights for overall progress calculation
    private static let stepWeights: [(PipelineStep, Double)] = [
        (.downloadingModels, 0.20),
        (.extractingAudio, 0.10),
        (.transcribing, 0.30),
        (.separatingVocals, 0.30),
        (.generatingWaveform, 0.10),
    ]

    private let transcriptionService = TranscriptionService()
    private let separationService = VocalSeparationService()

    /// Run the full preparation pipeline on a project.
    @MainActor
    func run(
        videoURL: URL,
        projectDir: URL,
        trimRange: CMTimeRange? = nil
    ) async throws {
        isRunning = true
        error = nil
        overallProgress = 0.0

        defer { isRunning = false }

        let fm = FileManager.default
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Step 1: Download/load models
        print("[Pipeline] Starting step: Downloading Models")
        try await runStep(.downloadingModels) {
            try await self.loadModels()
        }
        print("[Pipeline] Completed step: Downloading Models")

        // Step 2: Extract audio
        print("[Pipeline] Starting step: Extracting Audio")
        let audioResult = try await runStep(.extractingAudio) {
            try await AudioExtractor.extract(
                from: videoURL,
                to: projectDir,
                trimRange: trimRange,
                progress: { [weak self] p in
                    guard let self else { return }
                    Task { @MainActor in
                        self.updateStepProgress(p)
                        self.statusMessage = "Extracting audio… \(Int(p * 100))%"
                    }
                }
            )
        }
        print("[Pipeline] Completed step: Extracting Audio")

        // Step 3: Transcribe with WhisperKit
        print("[Pipeline] Starting step: Transcribing Speech")
        let words = try await runStep(.transcribing) {
            try await self.transcriptionService.transcribe(
                audioURL: audioResult.whisperAudioURL,
                progress: { [weak self] p in
                    guard let self else { return }
                    Task { @MainActor in
                        self.updateStepProgress(p)
                        self.statusMessage = "Transcribing… \(Int(p * 100))%"
                    }
                }
            )
        }
        print("[Pipeline] Completed step: Transcribing Speech")

        // Save timestamps JSON
        let timestampsURL = projectDir.appendingPathComponent("word_timestamps.json")
        try TranscriptionService.saveTimestamps(words, to: timestampsURL)

        // Step 4: Separate vocals with Demucs
        print("[Pipeline] Starting step: Separating Vocals")
        _ = try await runStep(.separatingVocals) {
            try await self.separationService.separate(
                audioURL: audioResult.demucsAudioURL,
                outputDir: projectDir,
                progress: { [weak self] p in
                    guard let self else { return }
                    Task { @MainActor in
                        self.updateStepProgress(p)
                        self.statusMessage = "Separating vocals… \(Int(p * 100))%"
                    }
                }
            )
        }
        print("[Pipeline] Completed step: Separating Vocals")

        // Step 5: Generate waveform peaks
        print("[Pipeline] Starting step: Generating Waveform")
        try await runStep(.generatingWaveform) {
            let peaks = try WaveformGenerator.generatePeaks(
                from: audioResult.demucsAudioURL,
                progress: { [weak self] p in
                    guard let self else { return }
                    Task { @MainActor in
                        self.updateStepProgress(p)
                        self.statusMessage = "Generating waveform… \(Int(p * 100))%"
                    }
                }
            )
            let peaksURL = projectDir.appendingPathComponent("waveform_peaks.json")
            try WaveformGenerator.savePeaks(peaks, to: peaksURL)
            return peaks
        }
        print("[Pipeline] Completed step: Generating Waveform")

        currentStep = .complete
        overallProgress = 1.0
        statusMessage = "Preparation complete"
        print("[Pipeline] All steps complete")
    }

    private func loadModels() async throws {
        // Load WhisperKit model
        statusMessage = "Loading WhisperKit model..."
        print("[Pipeline] Loading WhisperKit model...")
        try await transcriptionService.loadModel { [weak self] p in
            guard let self else { return }
            Task { @MainActor in
                self.updateStepProgress(p * 0.5)
                self.statusMessage = "Loading WhisperKit model… \(Int(p * 100))%"
            }
        }

        // Load Demucs model
        statusMessage = "Loading Demucs model..."
        print("[Pipeline] Loading Demucs model...")
        try await separationService.loadModel { [weak self] p in
            guard let self else { return }
            Task { @MainActor in
                self.updateStepProgress(0.5 + p * 0.5)
                self.statusMessage = "Loading Demucs model… \(Int(p * 100))%"
            }
        }
    }

    @discardableResult
    @MainActor
    private func runStep<T>(_ step: PipelineStep, work: () async throws -> T) async throws -> T {
        currentStep = step
        stepProgress = 0.0
        statusMessage = step.rawValue
        updateOverallProgress()

        do {
            let result = try await work()
            stepProgress = 1.0
            updateOverallProgress()
            return result
        } catch {
            self.error = error
            throw error
        }
    }

    @MainActor
    private func updateStepProgress(_ progress: Double) {
        stepProgress = min(max(progress, 0), 1)
        updateOverallProgress()
    }

    @MainActor
    private func updateOverallProgress() {
        var completed = 0.0
        for (step, weight) in Self.stepWeights {
            if step == currentStep {
                completed += weight * stepProgress
                break
            } else {
                completed += weight
            }
        }
        overallProgress = completed
    }
}
