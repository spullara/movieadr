# SwiftUI Desktop/iOS Port

## Why Port

- **Single app bundle** — no Python, Node, or ffmpeg to install
- **Apple Silicon acceleration** — Neural Engine + Metal GPU for ML workloads
- **10-50x faster processing** — hardware-accelerated Whisper and Demucs vs CPU Python
- **iOS support** — iPad is a natural fit for ADR work
- **Native audio** — AVFoundation gives lower latency, better sync, headphone detection

## Architecture

Single SwiftUI app. No client/server split. All processing on-device.

Project data stored in app sandbox (`~/Library/Containers/...`) or user-selected folder via document picker.

## Key Libraries

### WhisperKit

[github.com/argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit)

Native Swift transcription on CoreML/Neural Engine. Word-level timestamps supported.

- Models: `large-v3` available as CoreML models on HuggingFace
- Requirements: macOS 14+, iOS 17+, Xcode 16+

```swift
// Package.swift
.package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
```

### demucs-mlx-swift

[github.com/kylehowells/demucs-mlx-swift](https://github.com/kylehowells/demucs-mlx-swift)

Native Swift stem separation on MLX (Apple's ML framework for Apple Silicon GPU).

- Library target: `DemucsMLX` — importable directly
- Two-stem mode: vocals + no_vocals
- Performance: **38x realtime** on Apple Silicon (~12s for a 7-minute song)
- Float16 models available for memory-constrained iOS
- Requirements: macOS 14+, iOS 17+, **Apple Silicon only**

```swift
// Package.swift
.package(url: "https://github.com/kylehowells/demucs-mlx-swift", branch: "master")
```

### AVFoundation (built-in)

- `AVPlayer` — video playback
- `AVAudioEngine` — mic recording with real-time level metering
- `AVAudioSession` — audio routing, headphone detection
- `AVAssetExportSession` / `AVMutableComposition` — mux audio into video
- No ffmpeg needed for audio extraction, mixing, or muxing

## Component Mapping

| Current (Web) | SwiftUI Equivalent |
|---|---|
| React + Vite | SwiftUI App |
| HTML5 `<video>` | `AVPlayer` + `AVPlayerLayer` |
| Canvas overlay | SwiftUI `Canvas` or `CALayer` overlay |
| Web Audio API recording | `AVAudioEngine` + `AVAudioRecorder` |
| ScriptProcessorNode (waveform) | `AVAudioEngine` tap + Accelerate FFT |
| fetch/XHR API calls | Direct function calls (no server) |
| ffmpeg subprocess | AVFoundation |
| Express server | Not needed |
| Python + Whisper | WhisperKit (native Swift) |
| Python + Demucs | demucs-mlx-swift (native Swift) |
| multer file upload | `FileManager` / document picker |
| yt-dlp | No direct equivalent — shell out, use extraction lib, or drop feature |

## View Structure

```
App
├── ProjectListView (NavigationSplitView sidebar)
│   ├── Import button (NSOpenPanel / document picker)
│   └── Project rows with status
└── ADRSessionView
    ├── VideoPlayerView (AVPlayerLayer + Canvas overlay)
    │   ├── Teleprompter (scrolling words)
    │   ├── Waveform (pre-computed peaks)
    │   └── Now line (20% from left)
    ├── TransportBar (play, record, seek)
    └── TakesPanel (list takes, play, export)
```

## Effort Estimate

| Week | Focus |
|---|---|
| 1 | Project setup, video player with overlay, teleprompter rendering |
| 2 | WhisperKit + Demucs integration, preparation pipeline |
| 3 | Audio recording, take management, export/muxing |
| 4 | Polish, iOS adaptation, testing |

## Advantages Over Web Version

- No dependency installation
- 10-50x faster ML processing (Neural Engine + Metal vs CPU Python)
- Native headphone detection (auto-warn or auto-switch audio routing)
- Better audio sync (AVFoundation precise timestamps)
- App Store distribution
- Background processing with OS integration

## Challenges

- **YouTube download** — no yt-dlp equivalent; needs workaround
- **Apple Silicon only** — MLX doesn't run on Intel for Demucs
- **Model download** — WhisperKit large-v3 is ~3GB, needs first-run download
- **App size** — large if models are bundled
- **iOS memory** — processing full-length movies may hit limits

## Open Questions

- Bundle models in app vs download on first launch?
- Support Intel Macs? (Fall back to whisper.cpp; no MLX Demucs alternative)
- iPad support from day one?
