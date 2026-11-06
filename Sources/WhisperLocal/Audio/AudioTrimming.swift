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
    /// Whether any part of `samples` reaches `threshold`. A take without any is
    /// silence, and Whisper would invent text for it.
    static func containsSignal(
        _ samples: [Float],
        sampleRate: Int = 16_000,
        threshold: Float = 0.01
    ) -> Bool {
        lastLoudEnd(in: samples, sampleRate: sampleRate, threshold: threshold) != nil
    }

    /// Returns `samples` with trailing silence removed. A clip with no signal at
    /// all is returned unchanged; check it with `containsSignal`.
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
        guard let lastLoudEnd = lastLoudEnd(in: samples, sampleRate: sampleRate, threshold: threshold) else {
            return samples
        }

        let keepTail = Int(Double(sampleRate) * keepTailSeconds)
        let cutoff = min(samples.count, lastLoudEnd + keepTail)
        if cutoff >= samples.count { return samples }
        return Array(samples[0..<cutoff])
    }

    /// End index of the last 10 ms window whose RMS reaches `threshold`.
    private static func lastLoudEnd(in samples: [Float], sampleRate: Int, threshold: Float) -> Int? {
        let windowSize = max(1, sampleRate / 100) // 10 ms windows
        var idx = samples.count

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
                return idx
            }
            idx = start
        }
        return nil
    }
}
