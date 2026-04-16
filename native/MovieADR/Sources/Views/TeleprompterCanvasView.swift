import SwiftUI

/// Canvas overlay that draws the teleprompter (scrolling words), waveform, and "now" line.
struct TeleprompterCanvasView: View {
    let words: [TimedWord]
    let waveform: WaveformPeaks?
    let currentTime: Double
    let duration: Double
    let trimStart: Double
    let trimDuration: Double

    /// The "now" line sits at 20% from the left edge.
    private let nowLineRatio: CGFloat = 0.2

    var body: some View {
        Canvas { context, size in
            let W = size.width
            let H = size.height
            let nowX = W * nowLineRatio

            // Dark background band behind waveform/text area
            let bandCenterY = H * 0.85
            let bandH = H * 0.15
            context.fill(
                Path(CGRect(x: 0, y: bandCenterY - bandH, width: W, height: bandH * 2)),
                with: .color(.black.opacity(0.6))
            )

            // Draw waveform
            if let wf = waveform, !wf.peaks.isEmpty {
                drawWaveform(context: &context, waveform: wf, W: W, H: H, nowX: nowX)
            }

            // Draw teleprompter words
            if !words.isEmpty {
                drawTeleprompter(context: &context, W: W, H: H, nowX: nowX)
            }

            // Now line
            var nowPath = Path()
            nowPath.move(to: CGPoint(x: nowX, y: 0))
            nowPath.addLine(to: CGPoint(x: nowX, y: H))
            context.stroke(nowPath, with: .color(.red.opacity(0.8)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Waveform Drawing

    private func drawWaveform(
        context: inout GraphicsContext,
        waveform: WaveformPeaks,
        W: CGFloat, H: CGFloat, nowX: CGFloat
    ) {
        let peakDuration = Double(waveform.samplesPerPeak) / Double(waveform.sampleRate)
        let waveH = H * 0.15
        let waveY = H * 0.85
        let barW: CGFloat = 2
        let step: CGFloat = 3 // barW + gap

        let trimmedCurrentTime = currentTime - trimStart
        let centerPeakIdx = trimmedCurrentTime / peakDuration
        var px: CGFloat = 0
        while px < W {
            let peakIdx = Int(centerPeakIdx + Double(px - nowX) / Double(step))
            guard peakIdx >= 0, peakIdx < waveform.peaks.count else {
                px += step
                continue
            }
            let barH = min(CGFloat(waveform.peaks[peakIdx]) * waveH * 10, waveH)

            let color: Color
            if px < nowX {
                color = Color.blue.opacity(0.3)
            } else if abs(px - nowX) < step {
                color = Color.red.opacity(0.9)
            } else {
                color = Color.blue.opacity(0.6)
            }

            let rect = CGRect(x: px, y: waveY - barH / 2, width: barW, height: max(barH, 1))
            context.fill(Path(rect), with: .color(color))
            px += step
        }
    }

    // MARK: - Teleprompter Drawing

    private func drawTeleprompter(
        context: inout GraphicsContext,
        W: CGFloat, H: CGFloat, nowX: CGFloat
    ) {
        let fontSize = max(14, min(22, H * 0.035))
        let pxPerSec = W * 0.15
        let baseY = H * 0.85
        let wordGap = fontSize * 0.5
        let visibleLeft = currentTime - Double(nowX / pxPerSec) - 2
        let visibleRight = currentTime + Double((W - nowX) / pxPerSec) + 2

        // Build lines: split on gaps > 0.3s
        var lines: [[TimedWord]] = []
        var currentLine: [TimedWord] = []
        for word in words {
            if let last = currentLine.last, word.start - last.end > 0.3 {
                lines.append(currentLine)
                currentLine = []
            }
            currentLine.append(word)
        }
        if !currentLine.isEmpty { lines.append(currentLine) }

        for (lineIdx, line) in lines.enumerated() {
            // Only draw lines that are near the visible time range
            guard let firstWord = line.first, let lastWord = line.last else { continue }
            if lastWord.end < visibleLeft || firstWord.start > visibleRight { continue }

            // Alternate lines between just above and just below baseY (2 positions only)
            let lineOffset = (lineIdx % 2 == 0) ? -fontSize * 0.8 : fontSize * 0.8
            let y = baseY + lineOffset

            var nextMinX: CGFloat = -.infinity
            for word in line {
                let tsX = nowX + CGFloat(word.start - currentTime) * pxPerSec
                let resolvedFont = Font.system(size: fontSize, weight: .bold)

                var text = context.resolve(Text(word.word).font(resolvedFont))
                let textSize = text.measure(in: CGSize(width: W, height: H))
                let x = max(tsX, nextMinX)
                nextMinX = x + textSize.width + wordGap

                // Skip off-screen words
                if x + textSize.width < 0 || x > W { continue }

                // Highlight current word
                if currentTime >= word.start && currentTime <= word.end {
                    let highlightRect = CGRect(
                        x: x - 2, y: y - fontSize * 0.6,
                        width: textSize.width + 4, height: fontSize * 1.2
                    )
                    context.fill(Path(highlightRect), with: .color(.red.opacity(0.35)))
                }

                // Text color
                if currentTime > word.end {
                    text.shading = .color(.white.opacity(0.5))
                } else {
                    text.shading = .color(.white)
                }

                // Draw outline (stroke) then fill
                var outlineText = text
                outlineText.shading = .color(.black)
                // Draw at slight offsets for outline effect
                for dx in stride(from: -1.0, through: 1.0, by: 1.0) {
                    for dy in stride(from: -1.0, through: 1.0, by: 1.0) {
                        if dx == 0 && dy == 0 { continue }
                        context.draw(outlineText, at: CGPoint(x: x + textSize.width / 2 + dx, y: y + dy), anchor: .center)
                    }
                }
                context.draw(text, at: CGPoint(x: x + textSize.width / 2, y: y), anchor: .center)
            }
        }
    }
}
