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
    private var instrumentalPlayer: AVPlayer?
    private var syncTimer: Timer?

    init(url: URL) {
        self.player = AVPlayer(url: url)
        setupObservers()
    }

    deinit {
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
        }
        syncTimer?.invalidate()
    }

    func play() {
        // If before trim start, seek to it
        if currentTime < trimStart {
            seek(to: trimStart)
        }
        player.play()
        isPlaying = true
        if let ip = instrumentalPlayer {
            ip.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
            ip.play()
            startSyncTimer()
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        instrumentalPlayer?.pause()
        syncTimer?.invalidate()
        syncTimer = nil
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to time: Double) {
        let clampedTime = max(trimStart, min(time, trimEnd ?? duration))
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        instrumentalPlayer?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clampedTime
    }

    func loadInstrumental(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        player.isMuted = true
        instrumentalPlayer = AVPlayer(url: url)
        instrumentalPlayer?.volume = 1.0
    }

    private func startSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let ip = self.instrumentalPlayer else { return }
            let videoTime = self.player.currentTime().seconds
            let audioTime = ip.currentTime().seconds
            if abs(videoTime - audioTime) > 0.05 {
                ip.seek(to: CMTime(seconds: videoTime, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
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

            // Stop at trim end
            if let trimEnd = self.trimEnd, time.seconds >= trimEnd {
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
