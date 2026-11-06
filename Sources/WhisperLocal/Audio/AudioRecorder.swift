@preconcurrency import AVFoundation
import Combine

/// Records microphone audio as 16 kHz mono float32 — the native format expected
/// by Whisper.
///
/// ## Why AVCaptureSession
/// `AVAudioEngine.inputNode` always starts from an aggregate of the system's
/// default input and output, and a selected device is only an override on top of
/// it. With Bluetooth headphones as the default that override loses: merely
/// touching the node forces them from A2DP to HFP, the engine blocks for up to
/// 3 s waiting for that format change, and it can re-attach itself to the
/// aggregate after `start()` so no buffer ever arrives from the selected device.
/// A capture session opens exactly the requested device and leaves every other
/// one alone. It also resamples for us, and it does not stop when the system's
/// audio configuration changes.
///
/// A device that disappears during a take simply stops delivering buffers. What
/// was captured is kept and the take ends on the silence timeout or the hotkey.
///
/// ## Thread safety (Swift 6 strict concurrency)
/// - `start()` / `stop()` are called from the main actor.
/// - Buffers arrive on `captureQueue`, which owns all take state: `samples`,
///   `peakLevel`, `bufferCount` and `droppedBufferCount`.
/// - `level` is `@Published`; writes are dispatched to the main thread.
final class AudioRecorder: NSObject, @unchecked Sendable, Recording {
    @Published private(set) var level: Float = 0

    var levelPublisher: AnyPublisher<Float, Never> {
        $level.eraseToAnyPublisher()
    }

    /// Set the input device UID to use. Pass `nil` to follow the system default.
    /// Must be set before `start()` is called; changing while running has no effect
    /// until the next `start()`.
    var inputDeviceUID: String?

    private static let sampleRate = 16_000
    /// Cap at 60 seconds of audio to bound memory usage.
    private static let maxSamples = sampleRate * 60

    private let captureQueue = DispatchQueue(label: "io.github.marco-scheffler.WhisperLocal.capture")
    private var session: AVCaptureSession?
    private var runtimeErrorObserver: NSObjectProtocol?

    private var samples: [Float] = []
    private var peakLevel: Float = 0
    private var bufferCount = 0
    private var droppedBufferCount = 0

    /// Blocks until audio is flowing, so whatever the caller shows next (the
    /// recording overlay) is accurate, and hotkey events that arrive meanwhile
    /// stay in order.
    func start() throws {
        captureQueue.sync {
            samples.removeAll(keepingCapacity: true)
            peakLevel = 0
            bufferCount = 0
            droppedBufferCount = 0
        }

        let device = try resolveInputDevice()
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            Log.info("AudioRecorder:ERROR — cannot open \(device.localizedName): \(error.localizedDescription)")
            throw error
        }

        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(self, queue: captureQueue)

        let session = AVCaptureSession()
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            Log.info("AudioRecorder:ERROR — capture session rejected \(device.localizedName)")
            throw Self.error(code: 2, "Audio input setup failed for \(device.localizedName)")
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: .main
        ) { notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            Log.info("AudioRecorder:capture runtime error: \(error?.localizedDescription ?? "unknown")")
        }

        session.startRunning()
        guard session.isRunning else {
            removeRuntimeErrorObserver()
            Log.info("AudioRecorder:ERROR — capture session did not start")
            throw Self.error(code: 3, "Could not start recording from \(device.localizedName)")
        }
        self.session = session
        Log.info("AudioRecorder:capturing from \(device.localizedName)")
    }

    /// Stops recording and returns a copy of all captured samples.
    func stop() -> [Float] {
        session?.stopRunning()
        session = nil
        removeRuntimeErrorObserver()

        // Runs after any buffer still queued, so the end of the take is included.
        let (captured, peak, buffers, dropped) = captureQueue.sync {
            (samples, peakLevel, bufferCount, droppedBufferCount)
        }
        Log.info("AudioRecorder:stop — buffers=\(buffers) samples=\(captured.count) peakLevel=\(String(format: "%.4f", peak)) dropped=\(dropped)")

        DispatchQueue.main.async { [weak self] in
            self?.level = 0
        }

        return captured
    }

    // MARK: - Private

    private func resolveInputDevice() throws -> AVCaptureDevice {
        if let uid = inputDeviceUID {
            if let device = AVCaptureDevice(uniqueID: uid) {
                return device
            }
            Log.info("AudioRecorder:device uid=\(uid) not available — falling back to default")
        }
        let defaultDevice = AudioDeviceManager.defaultInputDeviceUID().flatMap(AVCaptureDevice.init(uniqueID:))
        guard let device = defaultDevice ?? AVCaptureDevice.default(for: .audio) else {
            Log.info("AudioRecorder:ERROR — no input device. Check System Settings → Sound → Input.")
            throw Self.error(code: 1, "No active input device (check System Settings → Sound → Input)")
        }
        return device
    }

    private func removeRuntimeErrorObserver() {
        if let observer = runtimeErrorObserver {
            NotificationCenter.default.removeObserver(observer)
            runtimeErrorObserver = nil
        }
    }

    private static func error(code: Int, _ description: String) -> NSError {
        NSError(domain: "WhisperLocal.AudioRecorder", code: code, userInfo: [
            NSLocalizedDescriptionKey: description
        ])
    }
}

extension AudioRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    /// Called on `captureQueue` with buffers in the format set in `audioSettings`.
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        bufferCount += 1

        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, let block = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            droppedBufferCount += 1
            return
        }

        var buffer = [Float](repeating: 0, count: frames)
        let status = buffer.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else {
            droppedBufferCount += 1
            return
        }

        var sum: Float = 0
        for sample in buffer {
            sum += sample * sample
        }
        let newLevel = sqrtf(sum / Float(frames))
        peakLevel = max(peakLevel, newLevel)

        // Drop the overflow rather than the start, so a take that runs long
        // loses its end — the part `DictationController`'s duration cap would
        // cut off anyway — instead of silently losing its beginning.
        samples.append(contentsOf: buffer.prefix(max(0, Self.maxSamples - samples.count)))

        DispatchQueue.main.async { [weak self] in
            self?.level = newLevel
        }
    }
}
