import AVFoundation

enum WaveformAmplitudeScale: String, CaseIterable {
    case linear = "Linear"
    case logarithmic = "Logarithmic"

    func displayAmplitude(for peak: Float) -> Float {
        switch self {
        case .linear:
            return peak
        case .logarithmic:
            // Map -60...0 dBFS to the available height, keeping silence at the baseline.
            let decibels = 20 * log10(max(0.001, peak))
            return min(1, max(0, (decibels + 60) / 60))
        }
    }
}

struct AudioWaveform: Sendable {
    let peaks: [Float]
    let secondsPerPeak: Double
    let duration: Double

    static func load(url: URL) throws -> AudioWaveform {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else {
            throw IntroEditorError.invalid("The audio format cannot be decoded into a waveform.")
        }
        let framesPerPeak = max(1, Int(format.sampleRate / 100))
        var peaks: [Float] = []
        var peak: Float = 0
        var framesInPeak = 0
        var totalFrames = 0
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
                throw IntroEditorError.invalid("The audio decoder stopped before the end of the recording.")
            }
            for frame in 0..<Int(buffer.frameLength) {
                for channel in 0..<Int(format.channelCount) {
                    peak = max(peak, abs(channels[channel][frame]))
                }
                framesInPeak += 1
                if framesInPeak == framesPerPeak {
                    peaks.append(min(1, peak))
                    peak = 0
                    framesInPeak = 0
                }
            }
            totalFrames += Int(buffer.frameLength)
        }
        if framesInPeak > 0 { peaks.append(min(1, peak)) }
        guard !peaks.isEmpty else { throw IntroEditorError.invalid("This recording contains no audio samples.") }
        return AudioWaveform(
            peaks: peaks, secondsPerPeak: Double(framesPerPeak) / format.sampleRate,
            duration: Double(totalFrames) / format.sampleRate
        )
    }
}
