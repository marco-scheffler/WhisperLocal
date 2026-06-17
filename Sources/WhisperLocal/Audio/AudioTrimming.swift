import Foundation

/// Trailing-silence trimming for captured audio.
///
/// Whisper models hallucinate "outro" phrases ("Vielen Dank", "Thanks for
/// watching", subtitle credits) when fed trailing silence — they were trained
/// partly on video subtitles. Our toggle-mode auto-stop deliberately captures
/// ~2 s of silence at the end, which reliably triggers this. Trimming the
/// trailing silence before transcription removes the trigger at the source
/// without touching real speech (we only cut from the end, never the start or
/// middle).
enum AudioTrimming {
    /// Returns `samples` with trailing silence removed.
    ///
    /// - Parameters:
    ///   - samples: 16 kHz mono float32 PCM.
    ///   - sampleRate: samples per second (default 16 000).
    ///   - threshold: RMS level below which a window counts as silence.
    ///   - keepTailSeconds: silence to keep after the last loud window, so the
    ///     final word isn't clipped and the decoder gets a natural tail.
    static func trimTrailingSilence(
        _ samples: [Float],
        sampleRate: Int = 16_000,
        threshold: Float = 0.01,
        keepTailSeconds: Double = 0.3
    ) -> [Float] {
        guard !samples.isEmpty else { return samples }

        let windowSize = max(1, sampleRate / 100) // 10 ms windows
        var idx = samples.count
        var lastLoudEnd = -1

        // Walk backward from the end, skipping silent windows until we hit the
        // first window whose RMS is at or above the threshold.
        while idx > 0 {
            let start = max(0, idx - windowSize)
            var sum: Float = 0
            for i in start..<idx {
                let s = samples[i]
                sum += s * s
            }
            let rms = (sqrtf(sum / Float(idx - start)))
            if rms >= threshold {
                lastLoudEnd = idx
                break
            }
            idx = start
        }

        // Entire clip is below threshold → no speech; return it unchanged so the
        // caller's "No speech / Too short" handling can decide what to do.
        if lastLoudEnd < 0 { return samples }

        let keepTail = Int(Double(sampleRate) * keepTailSeconds)
        let cutoff = min(samples.count, lastLoudEnd + keepTail)
        if cutoff >= samples.count { return samples }
        return Array(samples[0..<cutoff])
    }
}
