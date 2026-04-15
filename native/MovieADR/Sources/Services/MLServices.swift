import Foundation
import WhisperKit
import DemucsMLX

/// ML availability checks and shared utilities.
enum MLServices {
    static let whisperKitAvailable = true

    /// Demucs requires Apple Silicon with MLX support.
    /// On iOS, requires 8GB+ RAM (iPhone 15 Pro+, M-series iPads).
    static var demucsAvailable: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}
