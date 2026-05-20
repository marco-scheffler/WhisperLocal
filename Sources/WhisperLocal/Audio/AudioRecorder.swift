@preconcurrency import AVFoundation
import Combine
import os.lock

/// Records microphone audio and resamples it to 16 kHz mono float32 — the
/// native format expected by Whisper.
///
/// ## Thread safety (Swift 6 strict concurrency)
/// - `start()` / `stop()` are called from the main actor.
/// - The AVAudioEngine tap closure runs on an arbitrary background thread.
/// - `samples` is protected by `samplesLock` (os_unfair_lock).
/// - `level` and `isRecording` are `@Published`; writes are dispatched to the
///   main thread via `DispatchQueue.main.async` so subscribers on the main
///   actor see consistent values.
final class AudioRecorder: @unchecked Sendable {
    @Published private(set) var level: Float = 0
    @Published private(set) var isRecording: Bool = false

    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var samplesLock = os_unfair_lock_s()
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    }

    func start() throws {
        os_unfair_lock_lock(&samplesLock)
        samples.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&samplesLock)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        try engine.start()

        DispatchQueue.main.async { [weak self] in
            self?.isRecording = true
        }
    }

    /// Stops recording and returns a copy of all captured samples.
    func stop() -> [Float] {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        os_unfair_lock_lock(&samplesLock)
        let captured = samples
        os_unfair_lock_unlock(&samplesLock)

        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.level = 0
        }

        return captured
    }

    // MARK: - Private

    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let outCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate
        ) + 64

        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outCapacity
        ) else { return }

        // AVAudioConverter calls the input block synchronously and at most
        // twice per convert call. Wrapping `consumed` in a class box avoids
        // the Swift 6 "mutation of captured var in concurrently-executing code"
        // warning that arises because the block type is @Sendable.
        final class Box: @unchecked Sendable { var value = false }
        let consumedBox = Box()
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if consumedBox.value {
                status.pointee = .endOfStream
                return nil
            }
            consumedBox.value = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil else { return }

        let frames = Int(outBuffer.frameLength)
        guard frames > 0, let channel = outBuffer.floatChannelData?[0] else { return }

        var rms: Float = 0
        let newSamples = UnsafeBufferPointer(start: channel, count: frames)
        for s in newSamples {
            rms += s * s
        }
        let newLevel = sqrtf(rms / Float(frames))

        os_unfair_lock_lock(&samplesLock)
        samples.append(contentsOf: newSamples)
        // Cap at 60 seconds of audio to bound memory usage.
        let maxSamples = 16_000 * 60
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        os_unfair_lock_unlock(&samplesLock)

        DispatchQueue.main.async { [weak self] in
            self?.level = newLevel
        }
    }
}
