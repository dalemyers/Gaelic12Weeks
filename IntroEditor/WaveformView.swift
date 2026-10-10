import SwiftUI

struct WaveformView: View {
    let waveform: AudioWaveform
    let position: Double
    let introEnd: Double?
    let isPlaying: Bool
    @Binding var amplitudeScale: WaveformAmplitudeScale
    let seek: (Double) -> Void
    @State private var windowSeconds: Double = 15
    @State private var start: Double = 0

    private var span: Double { min(windowSeconds == 0 ? waveform.duration : windowSeconds, waveform.duration) }
    private var end: Double { min(start + span, waveform.duration) }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Waveform", systemImage: "waveform").font(.headline)
                Spacer()
                Picker("Amplitude", selection: $amplitudeScale) {
                    ForEach(WaveformAmplitudeScale.allCases, id: \.self) { scale in
                        Text(scale.rawValue).tag(scale)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .accessibilityIdentifier("waveformAmplitudeScale")
                .help("Linear amplitude or logarithmic amplitude from -60 to 0 dBFS. Audio playback is unchanged.")
            }
            HStack {
                Picker("Visible range", selection: $windowSeconds) {
                    Text("5 sec").tag(5.0)
                    Text("15 sec").tag(15.0)
                    Text("30 sec").tag(30.0)
                    Text("Full clip").tag(0.0)
                }
                .frame(width: 230)
                .accessibilityIdentifier("waveformZoom")
                Button { start = max(0, start - span / 2) } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Earlier waveform")
                .disabled(start <= 0)
                Button { start = min(max(0, waveform.duration - span), start + span / 2) } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Later waveform")
                .disabled(end >= waveform.duration)
                Button("Follow playhead") { follow() }
            }
            Canvas { context, size in
                let width = max(1, Int(size.width))
                let middle = size.height / 2
                var path = Path()
                for pixel in 0..<width {
                    let lower = max(0, Int((start + Double(pixel) / Double(width) * span) / waveform.secondsPerPeak))
                    let upper = min(
                        waveform.peaks.count,
                        max(lower + 1, Int((start + Double(pixel + 1) / Double(width) * span) / waveform.secondsPerPeak))
                    )
                    guard lower < upper else { continue }
                    let peak = waveform.peaks[lower..<upper].max() ?? 0
                    let height = max(1, CGFloat(amplitudeScale.displayAmplitude(for: peak)) * (middle - 16))
                    path.move(to: CGPoint(x: CGFloat(pixel), y: middle - height))
                    path.addLine(to: CGPoint(x: CGFloat(pixel), y: middle + height))
                }
                context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1)
                if let introEnd, introEnd >= start, introEnd <= end {
                    marker(at: introEnd, color: .orange, label: "SPLIT", context: &context, size: size)
                }
                if position >= start, position <= end {
                    marker(at: position, color: .teal, label: "PLAY", context: &context, size: size)
                }
            }
            .frame(height: 200)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .overlay {
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let fraction = min(1, max(0, value.location.x / max(1, geometry.size.width)))
                            seek(start + fraction * span)
                        })
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Audio waveform")
            .accessibilityValue("\(amplitudeScale.rawValue) amplitude. Playhead \(IntroEditorModel.time(position))")
            .accessibilityHint("Use the playback position slider to seek precisely.")
            .accessibilityIdentifier("audioWaveform")
            HStack {
                Text(IntroEditorModel.time(start))
                Spacer()
                Text("Click or drag to seek · Teal: playhead · Orange: saved split")
                Spacer()
                Text(IntroEditorModel.time(end))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .onChange(of: windowSeconds) { _, _ in follow() }
        .onChange(of: position) { _, value in
            if value < start || value > end || (isPlaying && value >= end - 0.1) { follow() }
        }
    }

    private func follow() {
        start = max(0, min(position - span * 0.2, waveform.duration - span))
    }

    private func marker(
        at seconds: Double, color: Color, label: String, context: inout GraphicsContext, size: CGSize
    ) {
        let x = (seconds - start) / max(span, 0.001) * size.width
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(line, with: .color(color), lineWidth: 2)
        context.draw(
            Text(label).font(.caption2.bold()).foregroundStyle(color),
            at: CGPoint(x: min(max(22, x), size.width - 22), y: label == "PLAY" ? size.height - 10 : 10)
        )
    }
}

#if DEBUG
#Preview {
    WaveformView(
        waveform: AudioWaveform(
            peaks: (0..<1_500).map { Float(abs(sin(Double($0) * 0.17)) * 0.7) },
            secondsPerPeak: 0.01, duration: 15
        ),
        position: 4, introEnd: 3.25, isPlaying: false, amplitudeScale: .constant(.linear), seek: { _ in }
    )
    .padding()
    .frame(width: 750)
}
#endif
