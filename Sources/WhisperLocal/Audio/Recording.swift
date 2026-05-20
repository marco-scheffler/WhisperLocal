import Foundation
import Combine

/// Abstraction over microphone capture so `DictationController` can be tested
/// without real hardware or OS permissions.
protocol Recording: AnyObject, Sendable {
    /// Combine publisher for the current audio level (0…1), updated on the main thread.
    var levelPublisher: AnyPublisher<Float, Never> { get }

    /// Start capturing audio. Throws if the hardware is unavailable or
    /// permission was denied.
    func start() throws

    /// Stop capturing and return all collected samples in 16 kHz mono float32.
    func stop() -> [Float]
}
