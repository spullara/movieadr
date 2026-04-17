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

        // Draw peaks aligned to peak boundaries, not pixel boundaries
        // Calculate the first and last visible peak indices
        let leftmostPeakIdx = Int(floor(centerPeakIdx - Double(nowX) / Double(step)))
        let rightmostPeakIdx = Int(ceil(centerPeakIdx + Double(W - nowX) / Double(step)))

        for peakIdx in leftmostPeakIdx...rightmostPeakIdx {
            guard peakIdx >= 0, peakIdx < waveform.peaks.count else { continue }

            // Calculate pixel position from peak index (stable, no jitter)
            let px = nowX + CGFloat(Double(peakIdx) - centerPeakIdx) * step
            guard px >= -step, px <= W + step else { continue }

            let barH = min(CGFloat(waveform.peaks[peakIdx]) * waveH * 3.5, waveH)

            let color: Color
            if px < nowX - step/2 {
                color = Color.blue.opacity(0.3)
            } else if abs(px - nowX) < step {
                color = Color.red.opacity(0.9)
            } else {
                color = Color.blue.opacity(0.6)
            }

            let rect = CGRect(x: px, y: waveY - barH / 2, width: barW, height: max(barH, 1))
            context.fill(Path(rect), with: .color(color))
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
        let wordGap = fontSize * 0.3
        let lineSpacing = fontSize * 1.5
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

        // For each visible line, compute its horizontal extent and assign a vertical slot
        // to avoid overlap. Words are always placed at their timestamp position.
        struct LineLayout {
            let line: [TimedWord]
            let leftX: CGFloat
            let rightX: CGFloat
            var ySlot: Int
        }

        var visibleLayouts: [LineLayout] = []

        for line in lines {
            guard let firstWord = line.first, let lastWord = line.last else { continue }
            if lastWord.end < visibleLeft || firstWord.start > visibleRight { continue }

            // Compute horizontal extent of this line
            var lineRightX: CGFloat = -.infinity
            var lineLeftX: CGFloat = .infinity
            for word in line {
                let tsX = nowX + CGFloat(word.start - currentTime) * pxPerSec
                let resolvedFont = Font.system(size: fontSize, weight: .bold)
                let text = context.resolve(Text(word.word).font(resolvedFont))
                let textSize = text.measure(in: CGSize(width: W, height: H))
                lineLeftX = min(lineLeftX, tsX)
                lineRightX = max(lineRightX, tsX + textSize.width)
            }

            visibleLayouts.append(LineLayout(line: line, leftX: lineLeftX, rightX: lineRightX, ySlot: 0))
        }

        // Assign vertical slots: greedily place each line in the lowest slot
        // that doesn't overlap horizontally with existing lines in that slot
        for i in 0..<visibleLayouts.count {
            var slot = 0
            while true {
                let overlaps = visibleLayouts[0..<i].contains { other in
                    other.ySlot == slot &&
                    visibleLayouts[i].leftX < other.rightX + wordGap * 2 &&
                    visibleLayouts[i].rightX > other.leftX - wordGap * 2
                }
                if !overlaps { break }
                slot += 1
                if slot > 4 { break } // max 5 vertical slots
            }
            visibleLayouts[i].ySlot = slot
        }

        // Draw each line at its assigned slot
        for layout in visibleLayouts {
            // Slots alternate: 0 = base, 1 = above, 2 = below, 3 = further above, 4 = further below
            let slotOffset: CGFloat
            switch layout.ySlot {
            case 0: slotOffset = 0
            case 1: slotOffset = -lineSpacing
            case 2: slotOffset = lineSpacing
            case 3: slotOffset = -lineSpacing * 2
            case 4: slotOffset = lineSpacing * 2
            default: slotOffset = 0
            }
            let y = baseY + slotOffset

            for word in layout.line {
                let tsX = nowX + CGFloat(word.start - currentTime) * pxPerSec
                let resolvedFont = Font.system(size: fontSize, weight: .bold)

                var text = context.resolve(Text(word.word).font(resolvedFont))
                let textSize = text.measure(in: CGSize(width: W, height: H))
                let x = tsX

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

                // Draw outline then fill
                var outlineText = text
                outlineText.shading = .color(.black)
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
