import AVFoundation
import SwiftUI

/// Observable object that owns the AVPlayer and publishes the current playback time.
@Observable
final class PlayerController {
    let player: AVPlayer
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying: Bool = false

    var trimStart: Double = 0
    var trimEnd: Double? = nil

    private var timeObserver: Any?
    private let videoURL: URL

    init(url: URL) {
        self.videoURL = url
        self.player = AVPlayer(url: url)
        setupObservers()
    }

    deinit {
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
        }
    }

    func play() {
        if currentTime < trimStart {
            seek(to: trimStart) { [weak self] in
                self?.player.play()
                self?.isPlaying = true
            }
        } else {
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to time: Double) {
        let clampedTime = max(trimStart, min(time, trimEnd ?? duration))
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clampedTime
    }

    func seek(to time: Double, completion: @escaping () -> Void) {
        let clampedTime = max(trimStart, min(time, trimEnd ?? duration))
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        currentTime = clampedTime
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            completion()
        }
    }

    func loadInstrumental(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        Task {
            do {
                let composition = AVMutableComposition()

                // Add video track from original video
                let videoAsset = AVURLAsset(url: videoURL)
                let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
                if let videoTrack = videoTracks.first {
                    let compositionVideoTrack = composition.addMutableTrack(
                        withMediaType: .video,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                    let videoDuration = try await videoAsset.load(.duration)
                    try compositionVideoTrack?.insertTimeRange(
                        CMTimeRange(start: .zero, duration: videoDuration),
                        of: videoTrack,
                        at: .zero
                    )
                }

                // Add audio track from instrumental file
                let audioAsset = AVURLAsset(url: url)
                let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
                if let audioTrack = audioTracks.first {
                    let compositionAudioTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                    let audioDuration = try await audioAsset.load(.duration)
                    try compositionAudioTrack?.insertTimeRange(
                        CMTimeRange(start: .zero, duration: audioDuration),
                        of: audioTrack,
                        at: .zero
                    )
                }

                let playerItem = AVPlayerItem(asset: composition)
                await MainActor.run {
                    player.replaceCurrentItem(with: playerItem)
                }
            } catch {
                print("Failed to create composition: \(error)")
                // Fall back to muted video (no instrumental)
            }
        }
    }

    private func setupObservers() {
        // High-frequency time observer for smooth animation (~60fps)
        let interval = CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds
            self.isPlaying = self.player.timeControlStatus == .playing

            // Stop at trim end (only while actually playing to avoid seek loops)
            if self.player.timeControlStatus == .playing,
               let trimEnd = self.trimEnd, time.seconds >= trimEnd {
                self.pause()
                self.seek(to: self.trimStart)
            }
        }

        // Observe duration
        Task { @MainActor in
            if let item = player.currentItem,
               let dur = try? await item.asset.load(.duration) {
                duration = dur.seconds
            }
        }
    }
}

// MARK: - Platform Video Layer View

#if os(iOS)
struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}

    class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        init(player: AVPlayer) {
            super.init(frame: .zero)
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            backgroundColor = .black
        }

        required init?(coder: NSCoder) { fatalError() }
    }
}
#else
struct VideoLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(playerLayer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let playerLayer = nsView.layer?.sublayers?.first as? AVPlayerLayer {
            playerLayer.frame = nsView.bounds
        }
    }
}
#endif
