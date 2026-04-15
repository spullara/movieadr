# Multiplatform SwiftUI App (macOS + iOS)

## Why Native

- **Single app bundle** — no Python, Node, or ffmpeg to install
- **Apple Silicon acceleration** — Neural Engine + Metal GPU for ML workloads
- **10-50x faster processing** — hardware-accelerated Whisper and Demucs vs CPU Python
- **One codebase, all platforms** — macOS, iPad, iPhone from a single Multiplatform SwiftUI target
- **Native audio** — AVFoundation gives lower latency, better sync, headphone detection

## Why Not Mac Catalyst

Mac Catalyst is dead. It's buggy on macOS 26 Tahoe, Apple isn't investing in it, and developers report frequent crashes. Multiplatform SwiftUI is Apple's intended path — select "Multiplatform" in Xcode, write one codebase, ship everywhere.

## Architecture

Single SwiftUI app. Single binary, no server. All processing on-device.

**Swift Package structure** — use SPM for the entire project, no `.xcodeproj`. The Package.swift defines the app target and all dependencies.

**Models downloaded on first launch** from HuggingFace, not bundled. WhisperKit large-v3 is ~3GB, Demucs models ~200MB. Download progress shown in UI. Models cached in app container.

**Video import** — users import videos from Files or Photos. No YouTube download in the native app (drop that feature; the web version handles it).

Project data stored in app sandbox or user-selected folder via document picker.

## Key Libraries

### WhisperKit

[github.com/argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit)

Native Swift transcription on CoreML/Neural Engine. Word-level timestamps supported.

- Models: `large-v3` available as CoreML models on HuggingFace
- Requirements: macOS 14+, iOS 17+, Xcode 16+
- Works on all iOS devices via CoreML (not MLX-dependent)

```swift
.package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
```

### demucs-mlx-swift

[github.com/kylehowells/demucs-mlx-swift](https://github.com/kylehowells/demucs-mlx-swift)

Native Swift stem separation on MLX (Apple's ML framework for Apple Silicon GPU).

- Library target: `DemucsMLX` — importable directly
- Two-stem mode: vocals + no_vocals
- Performance: **38x realtime** on Apple Silicon (~12s for a 7-minute song)
- Float16 models available for memory-constrained devices
- **macOS**: all Apple Silicon Macs
- **iOS**: requires iOS 18+, 8GB+ RAM — iPhone 15 Pro and later, M-series iPads
- Older iPhones/iPads cannot run Demucs via MLX (not enough RAM or no MLX support)

```swift
.package(url: "https://github.com/kylehowells/demucs-mlx-swift", branch: "master")
```

### AVFoundation (built-in)

- `AVPlayer` — video playback
- `AVAudioEngine` — mic recording with real-time level metering
- `AVAudioSession` — audio routing, headphone detection (iOS)
- `AVAssetExportSession` / `AVMutableComposition` — mux audio into video
- No ffmpeg needed for audio extraction, mixing, or muxing

## iPhone Considerations

The teleprompter UI works fine on iPhone screens — it's a scrolling word display over video, which adapts naturally to compact widths.

**Device tiers:**
- **iPhone 15 Pro+ / M-series iPad** — full pipeline: WhisperKit transcription + Demucs stem separation via MLX
- **Older iPhones (iOS 17+)** — WhisperKit transcription only (CoreML). No Demucs. Users can still do ADR with original audio, just no vocal isolation.

Use `#if canImport(MLX)` or runtime RAM checks to conditionally enable Demucs.

## Component Mapping

| Current (Web) | SwiftUI Equivalent |
|---|---|
| React + Vite | SwiftUI App (Multiplatform) |
| HTML5 `<video>` | `AVPlayer` + `AVPlayerLayer` |
| Canvas overlay | SwiftUI `Canvas` or `CALayer` overlay |
| Web Audio API recording | `AVAudioEngine` + `AVAudioRecorder` |
| ScriptProcessorNode (waveform) | `AVAudioEngine` tap + Accelerate FFT |
| fetch/XHR API calls | Direct function calls (no server) |
| ffmpeg subprocess | AVFoundation |
| Express server | Not needed |
| Python + Whisper | WhisperKit (CoreML, all devices) |
| Python + Demucs | demucs-mlx-swift (MLX, 8GB+ devices only) |
| multer file upload | `FileManager` / document picker / PHPickerViewController |
| yt-dlp | Dropped — import from Files/Photos instead |

## View Structure

```
App
├── ProjectListView (NavigationSplitView sidebar on iPad/Mac, NavigationStack on iPhone)
│   ├── Import button (document picker / PHPicker)
│   └── Project rows with status
├── ADRSessionView
│   ├── VideoPlayerView (AVPlayerLayer + Canvas overlay)
│   │   ├── Teleprompter (scrolling words)
│   │   ├── Waveform (pre-computed peaks)
│   │   └── Now line (20% from left)
│   ├── TransportBar (play, record, seek)
│   └── TakesPanel (list takes, play, export)
└── ModelDownloadView (first-launch onboarding, progress bars)
```

On iPhone, the sidebar collapses to a list and ADRSessionView goes full-screen with the teleprompter overlaid on video.

## Effort Estimate

| Week | Focus |
|---|---|
| 1 | SPM project setup, video player with overlay, teleprompter rendering |
| 2 | WhisperKit + Demucs integration, model download, preparation pipeline |
| 3 | Audio recording, take management, export/muxing |
| 4 | iPhone layout adaptation, device-tier gating, testing on all platforms |

## Advantages Over Web Version

- No dependency installation
- 10-50x faster ML processing (Neural Engine + Metal vs CPU Python)
- Native headphone detection (auto-warn or auto-switch audio routing)
- Better audio sync (AVFoundation precise timestamps)
- App Store distribution (macOS + iOS)
- Runs on iPhone — ADR on the go

## Challenges

- **Apple Silicon only for Demucs** — MLX doesn't run on Intel Macs or older iPhones
- **Model download** — WhisperKit large-v3 ~3GB + Demucs ~200MB, needs first-run download with progress UI
- **iOS memory** — processing full-length movies on 8GB devices may hit limits; need to chunk or limit duration
- **Device gating** — graceful degradation on devices that can't run Demucs
