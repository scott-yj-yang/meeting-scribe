import SwiftUI

/// Three-bar waveform visualization. Bars grow/shrink based on `level`.
/// Pass a `@State` or published Float in 0...1. Idle state animates gently.
struct WaveformBars: View {
    let level: Float
    let tint: Color

    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint)
                    .frame(width: 3, height: barHeight(for: i))
                    .animation(.easeInOut(duration: 0.15), value: level)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        // Base height 4-16pt depending on level, with per-bar offset so they don't move in unison
        let base: CGFloat = 4
        let max: CGFloat = 16
        let offsets: [Float] = [0.0, 0.33, 0.66]
        let wobble = (sinf((Float(phase) + offsets[index]) * .pi * 2) + 1) / 2  // 0...1
        let driven = level * 0.7 + wobble * 0.3
        return base + CGFloat(driven) * (max - base)
    }
}
