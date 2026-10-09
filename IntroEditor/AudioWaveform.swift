import AVFoundation

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
