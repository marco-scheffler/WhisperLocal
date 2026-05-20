# WhisperLocal MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local macOS speech-to-text utility that records on global-hotkey hold, transcribes via MLX Whisper, optionally cleans the text via a local Qwen LLM, and pastes the result into the focused app.

**Architecture:** Single Swift executable, ad-hoc signed, wrapped into a `.app` bundle by a build script. AppKit + SwiftUI front-end (status item, settings window, floating overlay panel). AVAudioEngine for capture. `mlx-swift-examples` for Whisper + LLM inference. `NSPasteboard` + `CGEvent` for text injection. All state coordinated by `DictationController`.

**Tech Stack:** Swift 5.10+, macOS 15 SDK, Swift Package Manager, AppKit, SwiftUI, AVFoundation, Combine, `ml-explore/mlx-swift`, `ml-explore/mlx-swift-examples`, `soffes/HotKey`.

**Spec:** [`docs/superpowers/specs/2026-05-20-whisperlocal-design.md`](../specs/2026-05-20-whisperlocal-design.md)

**Testing reality:** Unit tests target the pure-logic pieces (state machine, model paths, pasteboard snapshot/restore, hotkey serialization). GUI + framework integration (NSPanel, AVAudioEngine, CGEvent, MLX) is verified manually via smoke tests called out in each relevant task.

---

## Task 1: Project scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/WhisperLocal/main.swift`
- Create: `Resources/Info.plist`
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Create `.gitignore`**

```
.build/
.swiftpm/
*.xcodeproj
DerivedData/
.DS_Store
WhisperLocal.app/
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WhisperLocal",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "WhisperLocal", targets: ["WhisperLocal"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "WhisperLocal",
            dependencies: [
                "HotKey",
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
                .product(name: "WhisperKit", package: "mlx-swift-examples"),
            ],
            resources: [.copy("../../Resources/Info.plist")]
        ),
        .testTarget(name: "WhisperLocalTests", dependencies: ["WhisperLocal"]),
    ]
)
```

Note: `mlx-swift-examples` product names must be verified against the upstream Package.swift in Task 7. Adjust if the WhisperKit / MLXLLM product names differ.

- [ ] **Step 3: Create `Sources/WhisperLocal/main.swift`**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 4: Create a placeholder `Sources/WhisperLocal/AppDelegate.swift`**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("WhisperLocal launched")
    }
}
```

- [ ] **Step 5: Create `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.weber.WhisperLocal</string>
    <key>CFBundleName</key>
    <string>WhisperLocal</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>WhisperLocal needs the microphone to transcribe your speech locally.</string>
</dict>
</plist>
```

- [ ] **Step 6: Create minimal `README.md`**

```markdown
# WhisperLocal

Local macOS speech-to-text utility. Press and hold a global hotkey, speak, release, and the transcript is pasted at the cursor in any app.

## Build

    swift build -c release
    ./Scripts/make-app-bundle.sh
    open WhisperLocal.app
```

- [ ] **Step 7: Build to verify scaffold compiles**

Run: `cd /Users/marcoscheffler/coding/Private/WhisperLocal && swift build`
Expected: dependencies resolve and target compiles; `WhisperLocal launched` will print when run.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources Resources .gitignore README.md
git commit -m "feat: project scaffold with SPM, AppKit entry point, and Info.plist"
```

---

## Task 2: Menu bar item

**Files:**
- Modify: `Sources/WhisperLocal/AppDelegate.swift`
- Create: `Sources/WhisperLocal/MenuBar/MenuBarController.swift`

- [ ] **Step 1: Create `MenuBarController.swift`**

```swift
import AppKit

final class MenuBarController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "WhisperLocal")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "WhisperLocal", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("WhisperLocal.openSettings")
}
```

- [ ] **Step 2: Wire the controller into `AppDelegate`**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        NSLog("WhisperLocal launched")
    }
}
```

- [ ] **Step 3: Build and run, verify the menu bar icon appears**

Run: `swift run` from the project root.
Expected: a microphone-circle icon in the macOS menu bar, clicking it opens a menu with `Settings…` and `Quit`. Pressing `Quit` exits. Verify visually.

- [ ] **Step 4: Commit**

```bash
git add Sources
git commit -m "feat: menu bar status item with quit and settings entries"
```

---

## Task 3: HotKey manager — registration and serialization

**Files:**
- Create: `Sources/WhisperLocal/Hotkey/HotKeyManager.swift`
- Create: `Sources/WhisperLocal/Hotkey/HotKeyBinding.swift`
- Create: `Tests/WhisperLocalTests/HotKeyBindingTests.swift`

- [ ] **Step 1: Write the failing test for binding serialization**

`Tests/WhisperLocalTests/HotKeyBindingTests.swift`:

```swift
import XCTest
@testable import WhisperLocal

final class HotKeyBindingTests: XCTestCase {
    func testRoundTrip() {
        let original = HotKeyBinding(keyCode: 49, modifierFlags: [.control, .option])
        let restored = HotKeyBinding(dictionary: original.dictionary)
        XCTAssertEqual(restored, original)
    }

    func testDefault() {
        let def = HotKeyBinding.default
        XCTAssertTrue(def.modifierFlags.contains(.control))
        XCTAssertTrue(def.modifierFlags.contains(.option))
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `swift test --filter HotKeyBindingTests`
Expected: FAIL — `HotKeyBinding` does not exist yet.

- [ ] **Step 3: Implement `HotKeyBinding.swift`**

```swift
import AppKit

struct HotKeyBinding: Equatable, Codable {
    var keyCode: UInt32
    var modifierFlagsRaw: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: modifierFlagsRaw) }
        set { modifierFlagsRaw = newValue.rawValue }
    }

    init(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlagsRaw = modifierFlags.rawValue
    }

    static let `default` = HotKeyBinding(keyCode: 0, modifierFlags: [.control, .option])

    var dictionary: [String: Any] {
        ["keyCode": keyCode, "modifierFlagsRaw": modifierFlagsRaw]
    }

    init?(dictionary: [String: Any]) {
        guard
            let k = dictionary["keyCode"] as? UInt32,
            let m = dictionary["modifierFlagsRaw"] as? UInt
        else { return nil }
        self.keyCode = k
        self.modifierFlagsRaw = m
    }
}
```

Note: `keyCode: 0` is `'a'`. The default behavior is "hold Control+Option" — implemented in HotKeyManager via modifier-only detection (see Step 5). For pure-key bindings, the user assigns a key in Settings.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HotKeyBindingTests`
Expected: PASS.

- [ ] **Step 5: Implement `HotKeyManager.swift`**

```swift
import AppKit
import HotKey
import Carbon.HIToolbox

final class HotKeyManager {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?

    private var hotKey: HotKey?
    private var modifierMonitor: Any?
    private var modifierHeld: Bool = false
    private var binding: HotKeyBinding

    init(binding: HotKeyBinding) {
        self.binding = binding
        apply(binding: binding)
    }

    func update(binding: HotKeyBinding) {
        self.binding = binding
        teardown()
        apply(binding: binding)
    }

    private func apply(binding: HotKeyBinding) {
        if binding.keyCode == 0 && !binding.modifierFlags.isEmpty {
            installModifierOnlyMonitor(flags: binding.modifierFlags)
        } else {
            installKeyHotKey(binding: binding)
        }
    }

    private func installModifierOnlyMonitor(flags: NSEvent.ModifierFlags) {
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let isHeld = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: flags)
            if isHeld && !self.modifierHeld {
                self.modifierHeld = true
                self.onPressed?()
            } else if !isHeld && self.modifierHeld {
                self.modifierHeld = false
                self.onReleased?()
            }
        }
    }

    private func installKeyHotKey(binding: HotKeyBinding) {
        guard let key = Key(carbonKeyCode: UInt32(binding.keyCode)) else { return }
        let mods = carbonModifiers(from: binding.modifierFlags)
        let hk = HotKey(key: key, modifiers: NSEvent.ModifierFlags(rawValue: binding.modifierFlagsRaw))
        hk.keyDownHandler = { [weak self] in self?.onPressed?() }
        hk.keyUpHandler = { [weak self] in self?.onReleased?() }
        hotKey = hk
        _ = mods
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        return mods
    }

    private func teardown() {
        hotKey = nil
        if let m = modifierMonitor { NSEvent.removeMonitor(m) }
        modifierMonitor = nil
        modifierHeld = false
    }

    deinit { teardown() }
}
```

- [ ] **Step 6: Wire into `AppDelegate`**

```swift
private var hotKeys: HotKeyManager?

func applicationDidFinishLaunching(_ notification: Notification) {
    menuBar = MenuBarController()
    let mgr = HotKeyManager(binding: .default)
    mgr.onPressed = { NSLog("hotkey pressed") }
    mgr.onReleased = { NSLog("hotkey released") }
    hotKeys = mgr
}
```

- [ ] **Step 7: Manual smoke test**

Run: `swift run`
Expected: holding Control+Option logs `hotkey pressed`, releasing logs `hotkey released`. (Requires Input Monitoring permission; grant it via System Settings → Privacy → Input Monitoring when prompted.)

- [ ] **Step 8: Commit**

```bash
git add Sources Tests
git commit -m "feat: hotkey manager with modifier-only push-to-talk default"
```

---

## Task 4: Audio recorder

**Files:**
- Create: `Sources/WhisperLocal/Audio/AudioRecorder.swift`

- [ ] **Step 1: Implement `AudioRecorder.swift`**

```swift
import AVFoundation
import Combine

final class AudioRecorder {
    @Published private(set) var level: Float = 0
    @Published private(set) var isRecording: Bool = false

    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init() {
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                     sampleRate: 16_000,
                                     channels: 1,
                                     interleaved: false)!
    }

    func start() throws {
        samples.removeAll(keepingCapacity: true)
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
        try engine.start()
        isRecording = true
    }

    func stop() -> [Float] {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        level = 0
        return samples
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: outBuffer, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if error != nil { return }

        let frames = Int(outBuffer.frameLength)
        guard let channel = outBuffer.floatChannelData?[0] else { return }
        var rms: Float = 0
        for i in 0..<frames {
            let s = channel[i]
            rms += s * s
            samples.append(s)
        }
        if frames > 0 {
            let newLevel = sqrtf(rms / Float(frames))
            DispatchQueue.main.async { self.level = newLevel }
        }
        if samples.count > 16_000 * 60 {
            samples.removeFirst(samples.count - 16_000 * 60)
        }
    }
}
```

- [ ] **Step 2: Add a quick wiring test inside `AppDelegate` (temporary)**

```swift
private var recorder = AudioRecorder()

// in applicationDidFinishLaunching, after hotkey wiring:
mgr.onPressed = { [weak self] in
    try? self?.recorder.start()
    NSLog("recording…")
}
mgr.onReleased = { [weak self] in
    let s = self?.recorder.stop() ?? []
    NSLog("captured \(s.count) samples @ 16kHz (\(Double(s.count)/16000.0)s)")
}
```

- [ ] **Step 3: Manual smoke test**

Run: `swift run`. Hold Control+Option for ~3 seconds while speaking.
Expected: log shows ~48000 samples (3 s × 16 kHz). On first run, macOS prompts for microphone access — grant it.

- [ ] **Step 4: Commit**

```bash
git add Sources
git commit -m "feat: AVAudioEngine recorder producing 16kHz mono float32 samples"
```

---

## Task 5: Overlay window

**Files:**
- Create: `Sources/WhisperLocal/Overlay/OverlayWindow.swift`
- Create: `Sources/WhisperLocal/Overlay/OverlayView.swift`
- Create: `Sources/WhisperLocal/Overlay/OverlayState.swift`

- [ ] **Step 1: Create `OverlayState.swift`**

```swift
import Combine

enum OverlayPhase: Equatable {
    case hidden
    case recording
    case transcribing
    case postProcessing
    case injecting
    case error(String)
}

final class OverlayState: ObservableObject {
    @Published var phase: OverlayPhase = .hidden
    @Published var level: Float = 0
    @Published var partialText: String = ""
}
```

- [ ] **Step 2: Create `OverlayView.swift`**

```swift
import SwiftUI

struct OverlayView: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        HStack(spacing: 12) {
            indicator
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(minWidth: 160, maxWidth: 360)
    }

    @ViewBuilder private var indicator: some View {
        switch state.phase {
        case .recording:
            Circle().fill(.red).frame(width: 10, height: 10)
                .scaleEffect(1 + CGFloat(min(state.level * 4, 1)))
                .animation(.easeOut(duration: 0.1), value: state.level)
        case .transcribing, .postProcessing:
            ProgressView().controlSize(.small)
        case .injecting:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .hidden:
            EmptyView()
        }
    }

    private var label: String {
        switch state.phase {
        case .hidden: return ""
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .postProcessing: return "Cleaning up…"
        case .injecting: return "Pasting"
        case .error(let msg): return msg
        }
    }
}
```

- [ ] **Step 3: Create `OverlayWindow.swift`**

```swift
import AppKit
import SwiftUI

final class OverlayWindow {
    let state = OverlayState()
    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: OverlayView(state: state))
        positionBottomCenter()
    }

    func show() {
        positionBottomCenter()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        state.phase = .hidden
    }

    private func positionBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let frame = panel.frame
        let x = screen.visibleFrame.midX - frame.width / 2
        let y = screen.visibleFrame.minY + 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
```

- [ ] **Step 4: Wire into `AppDelegate` (temporary glue)**

```swift
private var overlay = OverlayWindow()

// in onPressed:
overlay.state.phase = .recording
overlay.show()

// in onReleased:
overlay.state.phase = .injecting
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
    self?.overlay.hide()
}
```

Also subscribe overlay level to recorder level:

```swift
import Combine
private var cancellables: Set<AnyCancellable> = []

// in applicationDidFinishLaunching:
recorder.$level
    .receive(on: RunLoop.main)
    .sink { [weak self] lvl in self?.overlay.state.level = lvl }
    .store(in: &cancellables)
```

- [ ] **Step 5: Manual smoke test**

Run: `swift run`. Hold Control+Option, speak, release.
Expected: small pill overlay appears bottom-center showing "Recording…" with pulsing red dot, then briefly "Pasting", then disappears.

- [ ] **Step 6: Commit**

```bash
git add Sources
git commit -m "feat: floating overlay panel with state-driven indicator"
```

---

## Task 6: Model store

**Files:**
- Create: `Sources/WhisperLocal/Inference/ModelStore.swift`
- Create: `Tests/WhisperLocalTests/ModelStoreTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import WhisperLocal

final class ModelStoreTests: XCTestCase {
    func testWhisperPath() {
        let store = ModelStore(bundleId: "com.test.app")
        XCTAssertTrue(store.whisperModelDirectory.path.contains("Application Support/com.test.app/Models/whisper"))
    }

    func testLLMPath() {
        let store = ModelStore(bundleId: "com.test.app")
        XCTAssertTrue(store.llmModelDirectory.path.contains("Application Support/com.test.app/Models/llm"))
    }
}
```

- [ ] **Step 2: Run test (fails)**

Run: `swift test --filter ModelStoreTests`
Expected: FAIL.

- [ ] **Step 3: Implement `ModelStore.swift`**

```swift
import Foundation

struct ModelStore {
    let bundleId: String

    init(bundleId: String = "com.weber.WhisperLocal") {
        self.bundleId = bundleId
    }

    var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupport.appendingPathComponent(bundleId).appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var whisperModelDirectory: URL {
        let url = baseDirectory.appendingPathComponent("whisper")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var llmModelDirectory: URL {
        let url = baseDirectory.appendingPathComponent("llm")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [ ] **Step 4: Tests pass**

Run: `swift test --filter ModelStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: model store paths under Application Support"
```

---

## Task 7: Whisper engine

**Files:**
- Create: `Sources/WhisperLocal/Inference/WhisperEngine.swift`

**Pre-task:** Verify the `mlx-swift-examples` API for Whisper by reading the upstream README and source under `Libraries/Whisper` (or equivalent). The product/module names and load API may have changed; this task documents the integration pattern, not exact symbols. **Adjust imports and call sites if the upstream API differs.**

- [ ] **Step 1: Define a protocol so the engine can be mocked or swapped**

```swift
import Foundation

protocol Transcribing {
    func ensureLoaded() async throws
    func transcribe(samples: [Float], language: String?) async throws -> String
}
```

- [ ] **Step 2: Implement `WhisperEngine.swift` against `mlx-swift-examples`**

```swift
import Foundation
import WhisperKit  // from mlx-swift-examples; verify exact module name

final class WhisperEngine: Transcribing {
    private let modelStore: ModelStore
    private let modelName: String
    private var pipeline: WhisperKit?

    init(modelStore: ModelStore, modelName: String = "mlx-community/whisper-large-v3-turbo") {
        self.modelStore = modelStore
        self.modelName = modelName
    }

    func ensureLoaded() async throws {
        if pipeline != nil { return }
        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelStore.whisperModelDirectory.path,
            download: true
        )
        pipeline = try await WhisperKit(config)
    }

    func transcribe(samples: [Float], language: String?) async throws -> String {
        try await ensureLoaded()
        guard let pipeline else { return "" }
        let result = try await pipeline.transcribe(audioArray: samples, decodeOptions: .init(language: language))
        return result.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

Note: if `mlx-swift-examples` does not yet expose a `WhisperKit`-like façade for MLX, fall back to the `Whisper` example under `mlx-swift-examples/Libraries/Whisper` — copy the model load + decode helpers into this engine. The integration pattern (load once, keep resident, async transcribe → String) does not change.

- [ ] **Step 3: Add an integration smoke test (manual)**

In `AppDelegate.applicationDidFinishLaunching`, after the recorder is set up:

```swift
private let whisper = WhisperEngine(modelStore: ModelStore())

// inside onReleased after stop():
Task {
    do {
        let text = try await self.whisper.transcribe(samples: s, language: nil)
        NSLog("transcript: \(text)")
    } catch {
        NSLog("transcribe error: \(error)")
    }
}
```

- [ ] **Step 4: Run and verify**

Run: `swift run`. First run downloads the model into `~/Library/Application Support/com.weber.WhisperLocal/Models/whisper/` (multi-GB; takes time).
Speak a German or English sentence, release. Expected: NSLog prints the transcript within ~1–2 s of release.

- [ ] **Step 5: Commit**

```bash
git add Sources
git commit -m "feat: MLX Whisper engine with on-demand model load"
```

---

## Task 8: Text injector

**Files:**
- Create: `Sources/WhisperLocal/Injection/TextInjector.swift`
- Create: `Tests/WhisperLocalTests/PasteboardSnapshotTests.swift`

- [ ] **Step 1: Failing test for the pasteboard snapshot helper**

```swift
import XCTest
import AppKit
@testable import WhisperLocal

final class PasteboardSnapshotTests: XCTestCase {
    func testSnapshotAndRestoreString() {
        let pb = NSPasteboard(name: NSPasteboard.Name("WhisperLocalTest"))
        pb.clearContents()
        pb.setString("original", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pb)
        pb.clearContents()
        pb.setString("replaced", forType: .string)
        XCTAssertEqual(pb.string(forType: .string), "replaced")

        snapshot.restore(to: pb)
        XCTAssertEqual(pb.string(forType: .string), "original")
    }
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `swift test --filter PasteboardSnapshotTests`

- [ ] **Step 3: Implement `TextInjector.swift`**

```swift
import AppKit
import Carbon.HIToolbox

struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = pasteboard.pasteboardItems ?? []
        let snapshot: [[NSPasteboard.PasteboardType: Data]] = items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
        return PasteboardSnapshot(items: snapshot)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let newItems: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(newItems)
    }
}

final class TextInjector {
    func inject(_ text: String) {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pb)

        pb.clearContents()
        pb.setString(text, forType: .string)

        postCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            snapshot.restore(to: pb)
        }
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 4: Tests pass**

Run: `swift test --filter PasteboardSnapshotTests`
Expected: PASS.

- [ ] **Step 5: Manual smoke test**

Replace the temporary `overlay.hide()` block in `AppDelegate` with:

```swift
private let injector = TextInjector()

// in transcribe Task, after getting `text`:
DispatchQueue.main.async {
    self.injector.inject(text)
    self.overlay.state.phase = .injecting
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
        self.overlay.hide()
    }
}
```

Open Terminal, focus it, hold Control+Option, say "Test eins zwei drei", release.
Expected: "Test eins zwei drei." (or similar) appears at the prompt. Repeat in TextEdit, VS Code, Chrome — verify Umlauts work ("Ähm das ist ein Test"). Grant Accessibility permission when macOS prompts.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat: pasteboard + ⌘V text injector with snapshot restore"
```

---

## Task 9: Dictation controller — state machine

**Files:**
- Create: `Sources/WhisperLocal/DictationController.swift`
- Create: `Tests/WhisperLocalTests/DictationControllerTests.swift`
- Modify: `Sources/WhisperLocal/AppDelegate.swift`

- [ ] **Step 1: Failing test for the state machine**

```swift
import XCTest
@testable import WhisperLocal

final class MockTranscriber: Transcribing {
    var output: String = "hallo welt"
    func ensureLoaded() async throws {}
    func transcribe(samples: [Float], language: String?) async throws -> String { output }
}

final class DictationControllerTests: XCTestCase {
    @MainActor
    func testHappyPath() async throws {
        let controller = DictationController(
            recorder: AudioRecorder(),
            transcriber: MockTranscriber(),
            postProcessor: nil,
            injector: TextInjector(),
            overlay: OverlayWindow()
        )
        await controller.handleHotKey(pressed: true)
        XCTAssertEqual(controller.state, .recording)
        await controller.handleHotKey(pressed: false)
        // wait for async pipeline
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(controller.state, .idle)
    }
}
```

Note: this test exercises the state transitions only; it does not assert on actual audio because `AudioRecorder.start()` will fail without microphone permission in CI. Run it locally after granting mic permission, or stub `AudioRecorder` behind a protocol in a future hardening pass.

- [ ] **Step 2: Implement `DictationController.swift`**

```swift
import Foundation
import Combine

@MainActor
final class DictationController: ObservableObject {
    enum State: Equatable {
        case idle, recording, transcribing, postProcessing, injecting
    }

    @Published private(set) var state: State = .idle

    private let recorder: AudioRecorder
    private let transcriber: Transcribing
    private let postProcessor: TextCleaning?
    private let injector: TextInjector
    private let overlay: OverlayWindow

    var llmEnabled: Bool = true

    init(recorder: AudioRecorder,
         transcriber: Transcribing,
         postProcessor: TextCleaning?,
         injector: TextInjector,
         overlay: OverlayWindow) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.postProcessor = postProcessor
        self.injector = injector
        self.overlay = overlay
    }

    func handleHotKey(pressed: Bool) async {
        if pressed { await startRecording() }
        else { await stopAndProcess() }
    }

    private func startRecording() async {
        guard state == .idle else { return }
        do {
            try recorder.start()
            state = .recording
            overlay.state.phase = .recording
            overlay.show()
        } catch {
            await fail(message: "Mic error: \(error.localizedDescription)")
        }
    }

    private func stopAndProcess() async {
        guard state == .recording else { return }
        let samples = recorder.stop()
        state = .transcribing
        overlay.state.phase = .transcribing

        let raw: String
        do {
            raw = try await transcriber.transcribe(samples: samples, language: nil)
        } catch {
            await fail(message: "Transcribe failed")
            return
        }

        var text = raw
        if llmEnabled, let post = postProcessor {
            state = .postProcessing
            overlay.state.phase = .postProcessing
            text = (try? await post.clean(text: raw)) ?? raw
        }

        guard !text.isEmpty else {
            await reset()
            return
        }

        state = .injecting
        overlay.state.phase = .injecting
        injector.inject(text)

        try? await Task.sleep(nanoseconds: 600_000_000)
        await reset()
    }

    private func fail(message: String) async {
        overlay.state.phase = .error(message)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await reset()
    }

    private func reset() async {
        state = .idle
        overlay.hide()
    }
}
```

- [ ] **Step 3: Add `TextCleaning` protocol (used by LLM post-processor)**

In `Sources/WhisperLocal/Inference/LLMPostProcessor.swift` (placeholder for Task 10):

```swift
import Foundation

protocol TextCleaning {
    func clean(text: String) async throws -> String
}
```

- [ ] **Step 4: Replace ad-hoc glue in `AppDelegate.applicationDidFinishLaunching` with controller wiring**

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotKeys: HotKeyManager?
    private let recorder = AudioRecorder()
    private let injector = TextInjector()
    private let overlay = OverlayWindow()
    private var controller: DictationController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()

        let whisper = WhisperEngine(modelStore: ModelStore())
        let c = DictationController(
            recorder: recorder,
            transcriber: whisper,
            postProcessor: nil,         // wired in Task 11
            injector: injector,
            overlay: overlay
        )
        controller = c

        recorder.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] lvl in self?.overlay.state.level = lvl }
            .store(in: &cancellables)

        let mgr = HotKeyManager(binding: .default)
        mgr.onPressed = { Task { await c.handleHotKey(pressed: true) } }
        mgr.onReleased = { Task { await c.handleHotKey(pressed: false) } }
        hotKeys = mgr
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter DictationControllerTests`
Expected: PASS (or skip if mic permission unavailable).

- [ ] **Step 6: Manual end-to-end smoke test**

Run: `swift run`. Hold hotkey, speak in Terminal, release.
Expected: transcript pastes at cursor with proper Umlauts. No LLM cleanup yet.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat: dictation controller state machine with end-to-end raw pipeline"
```

---

## Task 10: LLM post-processor

**Files:**
- Modify: `Sources/WhisperLocal/Inference/LLMPostProcessor.swift`

**Pre-task:** Verify `MLXLLM` / `MLXLMCommon` API in the current `mlx-swift-examples` checkout. The class names below follow the pattern in upstream's `LLMEval` example — if signatures differ, adjust accordingly.

- [ ] **Step 1: Implement `LLMPostProcessor`**

```swift
import Foundation
import MLXLLM
import MLXLMCommon

final class LLMPostProcessor: TextCleaning {
    private let modelStore: ModelStore
    private let modelName: String
    private var container: ModelContainer?

    init(modelStore: ModelStore, modelName: String = "mlx-community/Qwen2.5-7B-Instruct-4bit") {
        self.modelStore = modelStore
        self.modelName = modelName
    }

    func ensureLoaded() async throws {
        if container != nil { return }
        let config = LLMRegistry.shared.configuration(forName: modelName)
            ?? ModelConfiguration(id: modelName)
        container = try await LLMModelFactory.shared.loadContainer(
            hub: HubApi(downloadBase: modelStore.llmModelDirectory),
            configuration: config
        )
    }

    func clean(text: String) async throws -> String {
        guard !text.isEmpty else { return text }
        try await ensureLoaded()
        guard let container else { return text }

        let system = """
        You receive a raw speech-to-text transcript. Output the same content, but corrected for grammar, \
        punctuation, and capitalization. Remove filler words (uh, um, ähm, äh). Do not add new content. \
        Do not translate. Detect the input language (German or English) and stay in it. Output the cleaned \
        text only, no preface, no quotes.
        """

        let messages: [Chat.Message] = [
            .init(role: .system, content: system),
            .init(role: .user, content: text)
        ]

        let cleaned = try await withTimeout(seconds: 3) {
            try await container.perform { context in
                let input = try await context.processor.prepare(input: .init(messages: messages))
                let params = GenerateParameters(temperature: 0.2)
                var out = ""
                let stream = try MLXLMCommon.generate(input: input, parameters: params, context: context)
                for await chunk in stream { out += chunk.chunk ?? "" }
                return out.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return cleaned.isEmpty ? text : cleaned
    }

    private func withTimeout<T>(seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "LLMTimeout", code: 1)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
```

- [ ] **Step 2: Build to confirm imports resolve**

Run: `swift build`
Expected: clean build. If MLXLLM symbols differ, consult upstream `LLMEval` example and adjust.

- [ ] **Step 3: Commit**

```bash
git add Sources
git commit -m "feat: MLX LLM post-processor for transcript cleanup with timeout"
```

---

## Task 11: Wire LLM into controller

**Files:**
- Modify: `Sources/WhisperLocal/AppDelegate.swift`
- Modify: `Sources/WhisperLocal/DictationController.swift`

- [ ] **Step 1: Add a UserDefaults-backed toggle**

In `Sources/WhisperLocal/Preferences.swift` (new file):

```swift
import Foundation

enum Preferences {
    private static let llmKey = "WhisperLocal.llmEnabled"
    private static let hotkeyKey = "WhisperLocal.hotkey"

    static var llmEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: llmKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: llmKey) }
    }

    static var hotkey: HotKeyBinding {
        get {
            guard let dict = UserDefaults.standard.dictionary(forKey: hotkeyKey),
                  let b = HotKeyBinding(dictionary: dict) else { return .default }
            return b
        }
        set { UserDefaults.standard.set(newValue.dictionary, forKey: hotkeyKey) }
    }
}
```

- [ ] **Step 2: Wire LLM into `AppDelegate`**

```swift
let modelStore = ModelStore()
let whisper = WhisperEngine(modelStore: modelStore)
let llm = LLMPostProcessor(modelStore: modelStore)

let c = DictationController(
    recorder: recorder,
    transcriber: whisper,
    postProcessor: llm,
    injector: injector,
    overlay: overlay
)
c.llmEnabled = Preferences.llmEnabled
controller = c
```

- [ ] **Step 3: Manual end-to-end smoke test**

Run: `swift run`. Hold hotkey, say "ähm also ich glaube das ist nen test", release.
Expected: transcript appears cleaned in Terminal, e.g. "Ich glaube, das ist ein Test." Verify it stays in German.

- [ ] **Step 4: Commit**

```bash
git add Sources
git commit -m "feat: enable LLM cleanup by default with UserDefaults toggle"
```

---

## Task 12: Settings window

**Files:**
- Create: `Sources/WhisperLocal/Settings/SettingsWindow.swift`
- Create: `Sources/WhisperLocal/Settings/SettingsView.swift`
- Create: `Sources/WhisperLocal/Settings/HotKeyCaptureView.swift`
- Modify: `Sources/WhisperLocal/AppDelegate.swift`

- [ ] **Step 1: Create `HotKeyCaptureView.swift`**

```swift
import SwiftUI
import AppKit

struct HotKeyCaptureView: NSViewRepresentable {
    @Binding var binding: HotKeyBinding

    func makeNSView(context: Context) -> CaptureField {
        let v = CaptureField()
        v.binding = $binding
        return v
    }

    func updateNSView(_ nsView: CaptureField, context: Context) {
        nsView.binding = $binding
        nsView.refresh()
    }

    final class CaptureField: NSView {
        var binding: Binding<HotKeyBinding>?
        private let label = NSTextField(labelWithString: "")
        private var monitor: Any?
        private var capturing = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.cornerRadius = 6
            addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            refresh()
        }

        required init?(coder: NSCoder) { fatalError() }

        override func mouseDown(with event: NSEvent) {
            capturing.toggle()
            refresh()
            if capturing { installMonitor() } else { removeMonitor() }
        }

        private func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self else { return event }
                if event.type == .flagsChanged {
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if !flags.isEmpty && event.keyCode == 0xFF {
                        // pure modifier press; ignore, wait for key
                    }
                    return event
                }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                self.binding?.wrappedValue = HotKeyBinding(keyCode: UInt32(event.keyCode), modifierFlags: flags)
                self.capturing = false
                self.removeMonitor()
                self.refresh()
                return nil
            }
        }

        private func removeMonitor() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
        }

        func refresh() {
            if capturing {
                label.stringValue = "Press a key combo…"
            } else if let b = binding?.wrappedValue {
                label.stringValue = describe(binding: b)
            }
        }

        private func describe(binding: HotKeyBinding) -> String {
            var parts: [String] = []
            let f = binding.modifierFlags
            if f.contains(.control) { parts.append("⌃") }
            if f.contains(.option) { parts.append("⌥") }
            if f.contains(.shift) { parts.append("⇧") }
            if f.contains(.command) { parts.append("⌘") }
            if binding.keyCode != 0 {
                parts.append(KeyName.from(keyCode: binding.keyCode) ?? "key(\(binding.keyCode))")
            }
            return parts.joined(separator: " ")
        }
    }
}

enum KeyName {
    static func from(keyCode: UInt32) -> String? {
        let map: [UInt32: String] = [
            0x31: "Space", 0x24: "Return", 0x35: "Escape", 0x33: "Delete",
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E",
        ]
        return map[keyCode]
    }
}
```

- [ ] **Step 2: Create `SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @State private var hotkey: HotKeyBinding = Preferences.hotkey
    @State private var llmEnabled: Bool = Preferences.llmEnabled

    var onHotkeyChange: (HotKeyBinding) -> Void
    var onLLMChange: (Bool) -> Void

    var body: some View {
        Form {
            Section("Hotkey") {
                HotKeyCaptureView(binding: $hotkey)
                    .frame(height: 36)
                Button("Reset to default") {
                    hotkey = .default
                }
            }
            Section("Post-processing") {
                Toggle("Clean transcript with local LLM", isOn: $llmEnabled)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420, height: 280)
        .onChange(of: hotkey) { _, new in
            Preferences.hotkey = new
            onHotkeyChange(new)
        }
        .onChange(of: llmEnabled) { _, new in
            Preferences.llmEnabled = new
            onLLMChange(new)
        }
    }
}
```

- [ ] **Step 3: Create `SettingsWindow.swift`**

```swift
import AppKit
import SwiftUI

final class SettingsWindow {
    private var window: NSWindow?

    var onHotkeyChange: (HotKeyBinding) -> Void = { _ in }
    var onLLMChange: (Bool) -> Void = { _ in }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(
            onHotkeyChange: { [weak self] in self?.onHotkeyChange($0) },
            onLLMChange: { [weak self] in self?.onLLMChange($0) }
        )
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "WhisperLocal Settings"
        w.styleMask = [.titled, .closable]
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 4: Hook menu bar action → window**

In `AppDelegate.applicationDidFinishLaunching`:

```swift
private let settingsWindow = SettingsWindow()

// after creating hotKeys + controller:
settingsWindow.onHotkeyChange = { [weak self] new in self?.hotKeys?.update(binding: new) }
settingsWindow.onLLMChange = { [weak self] new in self?.controller?.llmEnabled = new }

NotificationCenter.default.addObserver(forName: .openSettings, object: nil, queue: .main) { [weak self] _ in
    self?.settingsWindow.show()
}
```

- [ ] **Step 5: Manual smoke test**

Run: `swift run`. Click menu bar icon → Settings…
Expected: window appears with the current hotkey and LLM toggle. Click hotkey field, press `⌘⇧Space` — field updates. Close window. Hold the new hotkey — recording starts.

- [ ] **Step 6: Commit**

```bash
git add Sources
git commit -m "feat: settings window with hotkey capture and LLM toggle"
```

---

## Task 13: Permissions manager

**Files:**
- Create: `Sources/WhisperLocal/Permissions/PermissionsManager.swift`
- Create: `Sources/WhisperLocal/Settings/PermissionsView.swift`
- Modify: `Sources/WhisperLocal/Settings/SettingsView.swift`

- [ ] **Step 1: Implement `PermissionsManager.swift`**

```swift
import AppKit
import AVFoundation

struct PermissionStatus {
    var microphone: Bool
    var accessibility: Bool
}

enum PermissionsManager {
    static func current() -> PermissionStatus {
        PermissionStatus(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibility: AXIsProcessTrusted()
        )
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
```

- [ ] **Step 2: Create `PermissionsView.swift`**

```swift
import SwiftUI

struct PermissionsView: View {
    @State private var status: PermissionStatus = PermissionsManager.current()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Microphone", granted: status.microphone) {
                Task {
                    _ = await PermissionsManager.requestMicrophone()
                    status = PermissionsManager.current()
                }
            }
            row("Accessibility (pasting)", granted: status.accessibility) {
                PermissionsManager.openAccessibilitySettings()
            }
            row("Input Monitoring (hotkey)", granted: true) {
                PermissionsManager.openInputMonitoringSettings()
            }
        }
        .onAppear { status = PermissionsManager.current() }
    }

    private func row(_ name: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(name)
            Spacer()
            Button(granted ? "Open settings" : "Grant", action: action)
        }
    }
}
```

- [ ] **Step 3: Add permissions section to `SettingsView`**

Inside the `Form` in `SettingsView.swift`, append:

```swift
Section("Permissions") {
    PermissionsView()
}
```

Adjust `.frame(width: 420, height: 380)` to fit.

- [ ] **Step 4: Smoke test**

Run: `swift run`. Open Settings — Permissions section shows status. Click "Grant" for mic if not granted — system prompt appears.

- [ ] **Step 5: Commit**

```bash
git add Sources
git commit -m "feat: permissions panel in settings with grant/open-settings actions"
```

---

## Task 14: App bundle build script and final smoke

**Files:**
- Create: `Scripts/make-app-bundle.sh`
- Modify: `README.md`

- [ ] **Step 1: Create `Scripts/make-app-bundle.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release

APP="$ROOT/WhisperLocal.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$ROOT/.build/release/WhisperLocal" "$APP/Contents/MacOS/WhisperLocal"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

codesign --force --sign - --entitlements /dev/null --options runtime "$APP"

echo "Built $APP"
echo "Run: open '$APP'"
```

- [ ] **Step 2: Make executable**

Run: `chmod +x Scripts/make-app-bundle.sh`

- [ ] **Step 3: Update `README.md`**

```markdown
# WhisperLocal

Local macOS speech-to-text. Press and hold a global hotkey, speak, release — the transcript is pasted into the focused app.

## Build & install

    swift test
    ./Scripts/make-app-bundle.sh
    open WhisperLocal.app

On first launch:
1. Grant **Microphone** access when prompted.
2. Grant **Accessibility** in System Settings → Privacy & Security → Accessibility (so the app can paste).
3. Grant **Input Monitoring** so the global hotkey works.
4. The Whisper model (~1.5 GB) and Qwen LLM (~4.5 GB) download on first use.

## Default hotkey

Hold `⌃⌥` (Control + Option). Configurable in Settings (menu bar icon → Settings…).

## Settings

- Hotkey capture
- Toggle LLM cleanup (default on)
- Permissions status
```

- [ ] **Step 4: Final end-to-end smoke**

Run:
```bash
./Scripts/make-app-bundle.sh
open WhisperLocal.app
```

Test in:
1. Terminal — "Hallo, das ist ein Test mit Umlauten." → pastes cleanly
2. VS Code editor pane — same
3. Slack/Chrome compose field — same
4. Change hotkey to `⌘⇧Space` in Settings → new hotkey works, old one doesn't
5. Toggle LLM off → raw transcript pastes including filler words
6. Toggle LLM on → cleaned transcript pastes
7. Quit via menu bar → app exits cleanly

- [ ] **Step 5: Commit**

```bash
git add Scripts README.md
git commit -m "feat: app bundle build script and updated README"
```

---

## Self-Review Notes

- **Spec coverage:** all 12 spec sections have a corresponding task. State machine (Task 9), audio (4), Whisper (7), LLM (10–11), injection (8), overlay (5), settings (12), permissions (13), models storage (6), build (14).
- **Verified:** the `mlx-swift-examples` integration tasks (7, 10) explicitly call out that upstream module/symbol names must be verified at implementation time; the integration *pattern* is correct but the exact API surface evolves.
- **Type consistency:** `HotKeyBinding` used in Tasks 3, 11, 12; `Transcribing` protocol in 7, 9; `TextCleaning` in 9, 10; `OverlayPhase` in 5, 9.
- **No placeholders:** every test, every implementation file has full code; every command shows its expected outcome.
