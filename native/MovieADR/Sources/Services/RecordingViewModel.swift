import AVFoundation
import Observation
import SwiftData

/// Coordinates recording lifecycle: ties start/stop to video playback,
/// creates Take records, and manages the AudioRecordingService.
@Observable
final class RecordingViewModel {
    let project: Project
    let recorder = AudioRecordingService()

    private(set) var currentTakeURL: URL?
    private(set) var error: String?
    private(set) var showHeadphoneWarning = false

    /// The take being played back (nil = not playing any take)
    private(set) var playingTake: Take?
    private var takePlayer: AVPlayer?
    private var takeTimeObserver: Any?

    var isRecording: Bool { recorder.isRecording }
    var audioLevel: Float { recorder.audioLevel }
    var headphonesConnected: Bool { recorder.headphonesConnected }

    init(project: Project) {
        self.project = project
    }

    deinit {
        stopTakePlayback()
    }

    // MARK: - Recording

    /// Start recording a new take. Call this when video playback starts.
    func startRecording(modelContext: ModelContext) {
        #if os(iOS)
        if !recorder.headphonesConnected {
            showHeadphoneWarning = true
            // Continue recording anyway — user can dismiss and re-record with headphones if needed
        }
        #endif

        error = nil
        showHeadphoneWarning = false

        let takeNumber = project.takes.count + 1
        let takesDir = project.directoryURL.appendingPathComponent("takes", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: takesDir, withIntermediateDirectories: true)
        } catch {
            self.error = "Failed to create takes directory: \(error.localizedDescription)"
            return
        }

        let fileName = "take_\(takeNumber).wav"
        let fileURL = takesDir.appendingPathComponent(fileName)
        currentTakeURL = fileURL

        do {
            try recorder.startRecording(to: fileURL)
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
            currentTakeURL = nil
        }
    }

    /// Stop recording. Call this when video playback stops.
    /// Returns the created Take, or nil on failure.
    @discardableResult
    func stopRecording(modelContext: ModelContext) -> Take? {
        guard recorder.isRecording else { return nil }
        recorder.stopRecording()

        guard let url = currentTakeURL else { return nil }

        // Verify file exists and get duration
        guard FileManager.default.fileExists(atPath: url.path) else {
            error = "Recording file not found"
            currentTakeURL = nil
            return nil
        }

        let take = Take(takeNumber: project.takes.count + 1, project: project)
        take.audioRelativePath = "takes/\(url.lastPathComponent)"

        // Get duration from the recorded file
        let asset = AVURLAsset(url: url)
        Task {
            if let duration = try? await asset.load(.duration) {
                take.duration = duration.seconds
            }
        }

        modelContext.insert(take)
        currentTakeURL = nil
        return take
    }

    func dismissHeadphoneWarning() {
        showHeadphoneWarning = false
    }

    // MARK: - Take Playback

    func playTake(_ take: Take) {
        stopTakePlayback()

        guard let path = take.audioRelativePath else { return }
        let url = project.directoryURL.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let player = AVPlayer(url: url)
        self.takePlayer = player
        self.playingTake = take

        // Observe end of playback
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.stopTakePlayback()
        }

        player.play()
    }

    func stopTakePlayback() {
        takePlayer?.pause()
        takePlayer = nil
        playingTake = nil
    }

    /// Delete a take and its audio file
    func deleteTake(_ take: Take, modelContext: ModelContext) {
        if let path = take.audioRelativePath {
            let url = project.directoryURL.appendingPathComponent(path)
            try? FileManager.default.removeItem(at: url)
        }
        if playingTake?.id == take.id {
            stopTakePlayback()
        }
        modelContext.delete(take)
    }
}
