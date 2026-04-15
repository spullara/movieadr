import SwiftUI

/// Horizontal bar that shows the current microphone input level during recording.
struct RecordingLevelMeterView: View {
    let level: Float  // 0.0 to 1.0
    let isRecording: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.2))

                // Level bar
                RoundedRectangle(cornerRadius: 3)
                    .fill(levelColor)
                    .frame(width: geo.size.width * CGFloat(level))
                    .animation(.linear(duration: 0.05), value: level)
            }
        }
        .frame(height: 6)
        .opacity(isRecording ? 1 : 0.3)
    }

    private var levelColor: Color {
        if level > 0.9 {
            return .red
        } else if level > 0.7 {
            return .yellow
        } else {
            return .green
        }
    }
}
