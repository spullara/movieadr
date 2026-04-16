#if os(macOS)
import Foundation
import Observation

/// Service for downloading YouTube videos via yt-dlp on macOS.
@Observable
final class YouTubeDownloadService {
    var isDownloading = false
    var progress: Double = 0.0
    var statusMessage = ""
    var error: String?

    /// Common locations where yt-dlp might be installed
    private static let commonPaths = [
        "/opt/homebrew/bin/yt-dlp",     // Apple Silicon Homebrew
        "/usr/local/bin/yt-dlp",        // Intel Homebrew
        "/usr/bin/yt-dlp",              // System
    ]

    /// Path to bundled yt-dlp in Application Support
    private static var bundledPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MovieADR")
        return dir.appendingPathComponent("yt-dlp").path
    }

    /// Check whether yt-dlp is installed on the system.
    static func isYtDlpInstalled() -> Bool {
        return ytDlpPath() != nil
    }

    /// Find the path to yt-dlp by checking common install locations,
    /// then falling back to `which`.
    private static func ytDlpPath() -> String? {
        // Check common paths first (works inside sandbox)
        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Check bundled path in Application Support
        if FileManager.default.fileExists(atPath: bundledPath) {
            return bundledPath
        }

        // Fallback to which (may not work in sandbox)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["yt-dlp"]
        // Add common paths to the process environment
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(existingPath)"
        } else {
            env["PATH"] = extraPaths
        }
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Download the official yt-dlp macOS binary to Application Support.
    @MainActor
    static func ensureYtDlpAvailable() async throws {
        // Already available?
        if ytDlpPath() != nil { return }

        // Download official standalone binary
        let downloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MovieADR")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destURL = URL(fileURLWithPath: bundledPath)

        // Configure session to follow redirects
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)

        let (tempURL, response) = try await session.download(from: downloadURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeDownloadError.downloadFailed("Invalid response downloading yt-dlp")
        }
        guard httpResponse.statusCode == 200 else {
            throw YouTubeDownloadError.downloadFailed("Failed to download yt-dlp: HTTP \(httpResponse.statusCode)")
        }

        // Verify we got a reasonable file (should be > 1MB)
        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let fileSize = attrs[.size] as? Int ?? 0
        guard fileSize > 1_000_000 else {
            throw YouTubeDownloadError.downloadFailed("Downloaded yt-dlp is too small (\(fileSize) bytes), likely not the real binary")
        }

        // Move to final location (overwrite if exists)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destURL)

        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)

        print("[YouTubeDownloadService] yt-dlp installed at \(destURL.path)")
    }

    /// Download a YouTube video to the specified directory.
    /// Returns the URL of the downloaded file.
    @MainActor
    func download(url: String, to directory: URL) async throws -> URL {
        // Auto-download yt-dlp if not found
        if Self.ytDlpPath() == nil {
            statusMessage = "Installing yt-dlp..."
            try await Self.ensureYtDlpAvailable()
            // Verify it was installed
            guard Self.ytDlpPath() != nil else {
                throw YouTubeDownloadError.downloadFailed("Auto-installed yt-dlp but binary not found at \(Self.bundledPath)")
            }
        }
        guard let ytDlpPath = Self.ytDlpPath() else {
            throw YouTubeDownloadError.ytDlpNotInstalled
        }

        isDownloading = true
        progress = 0.0
        statusMessage = "Starting download..."
        error = nil

        defer { isDownloading = false }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Output template: download as source_video.%(ext)s
        let outputTemplate = directory.appendingPathComponent("source_video.%(ext)s").path

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            // Build the full command with properly escaped arguments
            let escapedPath = ytDlpPath.replacingOccurrences(of: "'", with: "'\\''")
            let escapedTemplate = outputTemplate.replacingOccurrences(of: "'", with: "'\\''")
            let escapedUrl = url.replacingOccurrences(of: "'", with: "'\\''")
            var cmdParts = [
                "'\(escapedPath)'",
                "--no-playlist",
                "--no-check-certificates",
                "-f", "'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best'",
                "--merge-output-format", "mp4",
                "-o", "'\(escapedTemplate)'",
                "--newline",
            ]
            // Add ffmpeg location if found
            let ffmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            if let ffmpegPath = ffmpegPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                let ffmpegDir = URL(fileURLWithPath: ffmpegPath).deletingLastPathComponent().path
                cmdParts.insert(contentsOf: ["--ffmpeg-location", "'\(ffmpegDir)'"], at: 3)
            }
            cmdParts.append("'\(escapedUrl)'")
            let fullCommand = cmdParts.joined(separator: " ")
            process.arguments = ["-c", fullCommand]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Parse progress from stdout in real time
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.parseProgress(line)
                }
            }

            process.terminationHandler = { [weak self] proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                Task { @MainActor [weak self] in
                    if proc.terminationStatus == 0 {
                        self?.statusMessage = "Download complete"
                        self?.progress = 1.0
                        // Find the downloaded file
                        let downloadedFile = directory.appendingPathComponent("source_video.mp4")
                        if FileManager.default.fileExists(atPath: downloadedFile.path) {
                            continuation.resume(returning: downloadedFile)
                        } else {
                            // Try to find any video file yt-dlp created
                            if let found = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                                .first(where: { $0.lastPathComponent.hasPrefix("source_video") }) {
                                continuation.resume(returning: found)
                            } else {
                                continuation.resume(throwing: YouTubeDownloadError.downloadFailed("Downloaded file not found"))
                            }
                        }
                    } else {
                        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                        self?.error = errMsg
                        continuation.resume(throwing: YouTubeDownloadError.downloadFailed(errMsg))
                    }
                }
            }

            // Ensure Homebrew paths are in PATH for any subprocesses
            var env = ProcessInfo.processInfo.environment
            let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
            if let existingPath = env["PATH"] {
                env["PATH"] = "\(extraPaths):\(existingPath)"
            } else {
                env["PATH"] = extraPaths
            }
            process.environment = env

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: YouTubeDownloadError.downloadFailed(error.localizedDescription))
            }
        }
    }

    @MainActor
    private func parseProgress(_ output: String) {
        // yt-dlp progress lines look like: [download]  45.2% of ~50.00MiB at 5.00MiB/s ETA 00:05
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("[download]"), trimmed.contains("%") {
                // Extract percentage
                let parts = trimmed.components(separatedBy: .whitespaces)
                for part in parts {
                    if part.hasSuffix("%"), let pct = Double(part.dropLast()) {
                        progress = pct / 100.0
                        statusMessage = "Downloading: \(Int(pct))%"
                        break
                    }
                }
            } else if trimmed.contains("[Merger]") || trimmed.contains("[Merge]") {
                statusMessage = "Merging audio and video..."
            }
        }
    }
}

enum YouTubeDownloadError: LocalizedError {
    case ytDlpNotInstalled
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .ytDlpNotInstalled:
            return "yt-dlp could not be installed automatically. Check your internet connection and try again."
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        }
    }
}
#endif
