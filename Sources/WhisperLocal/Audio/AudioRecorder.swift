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
///
/// ## Input device selection and formats
/// Selecting an input device means setting `kAudioOutputUnitProperty_CurrentDevice`
/// on the input node's AUHAL. That updates `inputNode.inputFormat(forBus:)`
/// immediately but leaves `inputNode.outputFormat(forBus:)` reporting the
/// previous device forever. Installing a tap with the stale format makes AVFAudio
/// raise an Objective-C exception that kills the process; passing `format: nil`
/// resolves to the same stale value and fails `engine.start()` with
/// `kAudioUnitErr_FormatNotSupported` (-10868). So: always tap with
/// `inputFormat(forBus:)`, and rebuild the engine per session so no graph state
/// survives a device change.
final class AudioRecorder: @unchecked Sendable, Recording {
    @Published private(set) var level: Float = 0

    var levelPublisher: AnyPublisher<Float, Never> {
        $level.eraseToAnyPublisher()
    }
    @Published private(set) var isRecording: Bool = false

    private var engine = AVAudioEngine()
    private var samples: [Float] = []
    private var samplesLock = os_unfair_lock_s()
    private let targetFormat: AVAudioFormat
    /// Built lazily from the first tap buffer, and rebuilt if the hardware
    /// switches format mid-session. Only touched from the tap thread.
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
        converter = nil

        // Discard any graph state left over from the previous session — it may
        // reference a device or format that is no longer current.
        engine = AVAudioEngine()
        let input = engine.inputNode

        if let uid = inputDeviceUID {
            do {
                try AudioDeviceManager.setInput(engine: engine, deviceUID: uid)
                Log.info("AudioRecorder:routed input to device uid=\(uid)")
            } catch {
                Log.info("AudioRecorder:failed to route to uid=\(uid) (\(error)) — falling back to default")
            }
        }

        // `inputFormat(forBus:)` — NOT `outputFormat(forBus:)`. Only the former
        // tracks the hardware after `setInput` switched the AUHAL's device;
        // measured on a 44100 Hz → 48000 Hz switch, `outputFormat` keeps
        // reporting the old device indefinitely. Installing a tap with that
        // stale format is what used to raise the fatal AVFAudio exception, and
        // `format: nil` is no safer — it resolves to the same stale value.
        let inputFormat = input.inputFormat(forBus: 0)
        Log.info("AudioRecorder:input format sampleRate=\(inputFormat.sampleRate) channels=\(inputFormat.channelCount) commonFormat=\(inputFormat.commonFormat.rawValue)")

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Log.info("AudioRecorder:ERROR — input format has zero sample rate or channels. Check default audio input device in System Settings → Sound → Input.")
            throw NSError(domain: "WhisperLocal.AudioRecorder", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No active input device (check System Settings → Sound → Input)"
            ])
        }

        // The converter is still built from the first buffer we actually
        // receive rather than from `inputFormat`, so a device that changes
        // between here and the first callback cannot desync it.
        do {
            try ObjCException.catching {
                input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                    self?.process(buffer: buffer)
                }
                engine.prepare()
            }
        } catch {
            Log.info("AudioRecorder:ERROR — installTap raised: \(error.localizedDescription)")
            throw NSError(domain: "WhisperLocal.AudioRecorder", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Audio input setup failed (\(error.localizedDescription))"
            ])
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            Log.info("AudioRecorder:ERROR — engine.start() failed: \(error.localizedDescription)")
            throw error
        }
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

    /// Returns a converter from `inputFormat` to `targetFormat`, reusing the
    /// existing one unless the incoming format changed.
    private func converter(for inputFormat: AVAudioFormat) -> AVAudioConverter? {
        if let existing = converter, existing.inputFormat == inputFormat {
            return existing
        }
        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            Log.info("AudioRecorder:ERROR — AVAudioConverter init failed (from \(inputFormat) to \(targetFormat))")
            return nil
        }
        Log.info("AudioRecorder:converter \(inputFormat.sampleRate) Hz / \(inputFormat.channelCount) ch → 16000 Hz / 1 ch")
        converter = conv
        return conv
    }

    private func process(buffer: AVAudioPCMBuffer) {
        tapCallbackCount += 1
        if tapCallbackCount == 1 {
            Log.info("AudioRecorder:first tap callback — frameLength=\(buffer.frameLength) format=\(buffer.format)")
        }
        guard buffer.format.sampleRate > 0, let converter = converter(for: buffer.format) else {
            conversionErrorCount += 1
            return
        }

        let outCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate
        ) + 64

        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outCapacity
        ) else { return }

        // AVAudioConverter calls the input block synchronously. For streaming
        // resampling we must signal `.noDataNow` (not `.endOfStream`) after the
        // current buffer is consumed — otherwise the converter enters a "done"
        // state and every subsequent convert() returns zero frames.
        final class Box: @unchecked Sendable { var value = false }
        let consumedBox = Box()
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if consumedBox.value {
                status.pointee = .noDataNow
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
