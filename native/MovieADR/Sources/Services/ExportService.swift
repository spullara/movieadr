import AVFoundation
import Foundation

/// Mixes a recorded take with the instrumental track and exports a new video file.
/// Uses AVMutableComposition so the video track is copied without re-encoding.
@Observable
final class ExportService {

    enum ExportError: LocalizedError {
        case missingVideoFile
        case missingInstrumental
        case missingTakeAudio
        case noVideoTrack
        case noAudioTrack
        case exportFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .missingVideoFile: return "Original video file not found."
            case .missingInstrumental: return "Instrumental audio track not found."
            case .missingTakeAudio: return "Take audio recording not found."
            case .noVideoTrack: return "No video track in source file."
            case .noAudioTrack: return "No audio track in source file."
            case .exportFailed(let msg): return "Export failed: \(msg)"
            case .cancelled: return "Export was cancelled."
            }
        }
    }

    private(set) var progress: Double = 0
    private(set) var isExporting: Bool = false
    private var exportSession: AVAssetExportSession?

    /// Export a video with mixed audio (take recording + instrumental).
    /// - Parameters:
    ///   - project: The project containing video and instrumental paths
    ///   - take: The recorded take to mix in
    /// - Returns: URL of the exported video file
    @MainActor
    func export(project: Project, take: Take) async throws -> URL {
        guard let videoPath = project.videoRelativePath else {
            throw ExportError.missingVideoFile
        }
        guard let instrumentalPath = project.instrumentalRelativePath else {
            throw ExportError.missingInstrumental
        }
        guard let takePath = take.audioRelativePath else {
            throw ExportError.missingTakeAudio
        }

        let projectDir = project.directoryURL
        let videoURL = projectDir.appendingPathComponent(videoPath)
        let instrumentalURL = projectDir.appendingPathComponent(instrumentalPath)
        let takeURL = projectDir.appendingPathComponent(takePath)

        isExporting = true
        progress = 0
        defer { isExporting = false }

        // Load assets
        let videoAsset = AVURLAsset(url: videoURL)
        let instrumentalAsset = AVURLAsset(url: instrumentalURL)
        let takeAsset = AVURLAsset(url: takeURL)

        let videoDuration = try await videoAsset.load(.duration)

        // Build composition
        let composition = AVMutableComposition()

        // 1. Copy video track (passthrough — no re-encoding)
        guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )!
        let timeRange = CMTimeRange(start: .zero, duration: videoDuration)
        try compVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)

        // 2. Add instrumental audio track
        let compInstrumentalTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )!
        if let instrumentalAudioTrack = try await instrumentalAsset.loadTracks(withMediaType: .audio).first {
            let instrDuration = try await instrumentalAsset.load(.duration)
            let instrRange = CMTimeRange(start: .zero, duration: min(instrDuration, videoDuration))
            try compInstrumentalTrack.insertTimeRange(instrRange, of: instrumentalAudioTrack, at: .zero)
        }

        // 3. Add take (recorded voice) audio track
        let compTakeTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )!
        if let takeAudioTrack = try await takeAsset.loadTracks(withMediaType: .audio).first {
            let takeDuration = try await takeAsset.load(.duration)
            let takeRange = CMTimeRange(start: .zero, duration: min(takeDuration, videoDuration))
            try compTakeTrack.insertTimeRange(takeRange, of: takeAudioTrack, at: .zero)
        }

        // 4. Audio mix parameters — both tracks at full volume
        let instrumentalParams = AVMutableAudioMixInputParameters(track: compInstrumentalTrack)
        instrumentalParams.setVolume(1.0, at: .zero)

        let takeParams = AVMutableAudioMixInputParameters(track: compTakeTrack)
        takeParams.setVolume(1.0, at: .zero)

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [instrumentalParams, takeParams]

        // 5. Output file
        let outputFilename = "export_take\(take.takeNumber)_\(UUID().uuidString.prefix(8)).mp4"
        let outputURL = projectDir.appendingPathComponent(outputFilename)
        try? FileManager.default.removeItem(at: outputURL)

        // 6. Export with passthrough preset (copies video, re-encodes audio)
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw ExportError.exportFailed("Could not create export session.")
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.audioMix = audioMix

        self.exportSession = session

        // Monitor progress
        let progressTask = Task { @MainActor in
            while !Task.isCancelled, session.status == .exporting || session.status == .waiting {
                self.progress = Double(session.progress)
                try? await Task.sleep(for: .milliseconds(100))
            }
            self.progress = 1.0
        }

        await session.export()
        progressTask.cancel()

        switch session.status {
        case .completed:
            progress = 1.0
            return outputURL
        case .cancelled:
            throw ExportError.cancelled
        default:
            let msg = session.error?.localizedDescription ?? "Unknown error"
            throw ExportError.exportFailed(msg)
        }
    }

    func cancel() {
        exportSession?.cancelExport()
    }
}
