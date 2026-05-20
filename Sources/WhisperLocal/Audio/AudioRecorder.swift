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
final class AudioRecorder: @unchecked Sendable, Recording {
    @Published private(set) var level: Float = 0

    var levelPublisher: AnyPublisher<Float, Never> {
        $level.eraseToAnyPublisher()
    }
    @Published private(set) var isRecording: Bool = false

    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var samplesLock = os_unfair_lock_s()
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var tapCallbackCount: Int = 0
    private var conversionErrorCount: Int = 0

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    }

    /// Set the input device UID to use. Pass `nil` to follow the system default.
    /// Must be set before `start()` is called; changing while running has no effect
    /// until the next `start()`.
    var inputDeviceUID: String?

    func start() throws {
        os_unfair_lock_lock(&samplesLock)
        samples.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&samplesLock)
        tapCallbackCount = 0
        conversionErrorCount = 0

        let input = engine.inputNode

        if let uid = inputDeviceUID {
            do {
                try AudioDeviceManager.setInput(engine: engine, deviceUID: uid)
                Log.info("AudioRecorder:routed input to device uid=\(uid)")
            } catch {
                Log.info("AudioRecorder:failed to route to uid=\(uid) (\(error)) — falling back to default")
            }
        }

        let inputFormat = input.outputFormat(forBus: 0)
        Log.info("AudioRecorder:input format sampleRate=\(inputFormat.sampleRate) channels=\(inputFormat.channelCount) commonFormat=\(inputFormat.commonFormat.rawValue)")

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Log.info("AudioRecorder:ERROR — input format has zero sample rate or channels. Check default audio input device in System Settings → Sound → Input.")
            throw NSError(domain: "WhisperLocal.AudioRecorder", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No active input device (check System Settings → Sound → Input)"
            ])
        }

        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            Log.info("AudioRecorder:ERROR — AVAudioConverter init failed (from \(inputFormat) to \(targetFormat))")
            throw NSError(domain: "WhisperLocal.AudioRecorder", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Audio converter init failed"
            ])
        }
        converter = conv

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
        Log.info("AudioRecorder:engine started, isRunning=\(engine.isRunning)")

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

        Log.info("AudioRecorder:stop — taps=\(tapCallbackCount) samples=\(captured.count) convErrors=\(conversionErrorCount)")

        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.level = 0
        }

        return captured
    }

    // MARK: - Private

    private func process(buffer: AVAudioPCMBuffer) {
        tapCallbackCount += 1
        if tapCallbackCount == 1 {
            Log.info("AudioRecorder:first tap callback — frameLength=\(buffer.frameLength) format=\(buffer.format)")
        }
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

        guard error == nil else {
            conversionErrorCount += 1
            if conversionErrorCount == 1 {
                Log.info("AudioRecorder:first conversion error: \(error!.localizedDescription)")
            }
            return
        }

        let frames = Int(outBuffer.frameLength)
        guard frames > 0, let channel = outBuffer.floatChannelData?[0] else {
            conversionErrorCount += 1
            if conversionErrorCount == 1 {
                Log.info("AudioRecorder:conversion produced 0 frames (input frameLength=\(buffer.frameLength))")
            }
            return
        }

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
