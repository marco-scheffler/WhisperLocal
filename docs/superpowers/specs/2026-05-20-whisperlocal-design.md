# WhisperLocal — Design Spec

**Date:** 2026-05-20
**Status:** Approved (brainstorming phase)
**Target:** macOS 15+, Apple Silicon (developed against M5 Max / 64 GB)

## 1. Goal

A local, offline speech-to-text utility for macOS, modeled after [whisperbar.pro](https://whisperbar.pro).
The user presses a global hotkey, speaks, releases the hotkey, and the transcript is inserted into the
currently focused application (any app, including the terminal). Optional local LLM cleanup runs before
insertion. No cloud, no network at runtime after model download.

## 2. Non-Goals (MVP)

- Custom vocabulary / prompt templates
- Transcript history or log persistence
- Multiple hotkey profiles
- App-specific behavior (e.g. different prompts per app)
- Notarization / public distribution — ad-hoc signed local build only
- Streaming partial transcription (full-decode is fast enough on M5 Max)

## 3. User Stories

1. As the user, I press and hold a global hotkey, speak, release the hotkey, and the text appears at
   my cursor — inside Terminal, VS Code, Slack, browser, anywhere.
2. As the user, I see a floating overlay during recording that shows the audio level so I know the
   mic is live.
3. As the user, I can change the hotkey in a Settings window.
4. As the user, I can toggle LLM cleanup on/off in Settings; when on, the transcript is rewritten
   into clean German/English before insertion.
5. As the user, on first launch I am guided through granting microphone, accessibility, and input
   monitoring permissions.

## 4. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  AppDelegate (LSUIElement = true, no Dock icon)              │
│                                                              │
│  ├── MenuBarController          NSStatusItem + dropdown menu │
│  ├── HotKeyManager              soffes/HotKey, configurable  │
│  ├── PermissionsManager         Mic / Accessibility / Input  │
│  ├── SettingsWindow             SwiftUI, hotkey capture +    │
│  │                              LLM toggle + model selection │
│  └── DictationController        State machine, glue          │
│      ├── AudioRecorder          AVAudioEngine, 16k mono f32  │
│      ├── WhisperEngine          mlx-swift-examples Whisper   │
│      ├── LLMPostProcessor       mlx-swift-examples LLM       │
│      ├── TextInjector           NSPasteboard + CGEvent ⌘V    │
│      └── OverlayWindow          NSPanel, .floating level     │
└──────────────────────────────────────────────────────────────┘
```

### State Machine

```
                ┌──────────┐
                │   idle   │◄────────────────────┐
                └────┬─────┘                     │
       hotkey down   │                           │
                     ▼                           │
              ┌────────────┐                     │
              │ recording  │                     │
              └────┬───────┘                     │
       hotkey up   │                             │
                   ▼                             │
            ┌──────────────┐                     │
            │ transcribing │                     │
            └────┬─────────┘                     │
                 │                               │
       LLM on?   ├── yes ──► post_processing ──┐ │
                 │                              ▼│
                 └── no ──────────────────► injecting
```

Failure transitions: any error → `idle` with a transient error indicator in the overlay (red dot + tooltip).

## 5. Component Details

### 5.1 AudioRecorder
- `AVAudioEngine` with input node tap.
- Format: 16 kHz mono float32 (Whisper's native format — no resample).
- Buffers appended into a `[Float]` ring buffer up to 60 seconds; beyond that, oldest samples dropped.
- Publishes RMS level @ 30 Hz to the overlay via Combine.
- Stop returns the captured `[Float]` buffer.

### 5.2 HotKeyManager
- Wraps [`soffes/HotKey`](https://github.com/soffes/HotKey).
- Defaults: hold `⌃⌥` (Control + Option) as push-to-talk.
- Persisted in `UserDefaults` as `(keyCode, modifierFlags)`.
- Reconfigurable from Settings via a capture field.
- Emits `.pressed` and `.released` events to `DictationController`.

### 5.3 WhisperEngine
- Backed by [`ml-explore/mlx-swift-examples`](https://github.com/ml-explore/mlx-swift-examples) Whisper module.
- Default model: `mlx-community/whisper-large-v3-turbo` (downloaded on first launch).
- Loaded into memory at app start (warm-up takes ~5 s, then inference is sub-second for typical utterances).
- API: `func transcribe(_ samples: [Float], language: String?) async throws -> String`
- Language: `nil` (auto-detect German/English).

### 5.4 LLMPostProcessor
- Backed by `mlx-swift-examples` LLM module.
- Default model: `mlx-community/Qwen2.5-7B-Instruct-4bit`.
- Loaded on demand (only if toggle is on); kept resident once loaded.
- System prompt (German + English, language-detected from input):
  > "You receive a raw speech-to-text transcript. Output the same content, but corrected for
  > grammar, punctuation, and capitalization. Remove filler words (uh, um, ähm). Do not add new
  > content. Do not translate. Output the cleaned text only, no preface."
- Max output tokens: 1.5× input token count + 32.
- Timeout: 3 s — on timeout, fall back to raw transcript.

### 5.5 TextInjector
1. Snapshot current `NSPasteboard.general` contents (all types).
2. Write transcript as `.string` to pasteboard.
3. Post `CGEvent` `cmd-v` key down + key up to the system event tap.
4. After 500 ms, restore the snapshotted pasteboard contents.

This is the only reliable method for Terminal + Unicode + Umlauts. CGEvent direct keystroke
simulation fails on Terminal for many characters.

### 5.6 OverlayWindow
- `NSPanel` subclass with `styleMask = [.borderless, .nonactivatingPanel]`, `level = .floating`,
  `isMovableByWindowBackground = true`.
- Positioned bottom-center by default; remembers last position.
- Hosts a SwiftUI view that observes `DictationController.state` and `AudioRecorder.level`.
- Shows: pulse + level meter (recording), spinner (transcribing/post-processing), green tick
  (injecting), red dot + error message (error).

### 5.7 SettingsWindow
- SwiftUI window opened from menu bar item.
- Sections:
  - **Hotkey**: capture field showing current combo, "Reset to default" button.
  - **Models**: Whisper model picker (large-v3-turbo / large-v3 / medium), LLM model picker, "Download" button per model.
  - **Post-processing**: toggle "Clean transcript with LLM" (default ON per user request).
  - **Permissions**: status indicators for Mic / Accessibility / Input Monitoring, with "Open System Settings" buttons.

### 5.8 PermissionsManager
- Checks each permission on launch.
- If any are missing, opens a SwiftUI onboarding sheet that walks the user through granting them
  one by one, with the relevant `x-apple.systempreferences:` URLs.

## 6. Data & Storage

```
~/Library/Application Support/WhisperLocal/
├── Models/
│   ├── whisper-large-v3-turbo/      (~1.5 GB)
│   └── Qwen2.5-7B-Instruct-4bit/    (~4.5 GB)
└── Preferences via UserDefaults (suite: com.weber.WhisperLocal)
```

## 7. Project Layout

```
WhisperLocal/
├── Package.swift                       # SPM, executable target
├── Sources/WhisperLocal/
│   ├── App.swift                       # @main NSApplicationDelegate adapter
│   ├── AppDelegate.swift
│   ├── DictationController.swift
│   ├── MenuBar/
│   │   └── MenuBarController.swift
│   ├── Hotkey/
│   │   └── HotKeyManager.swift
│   ├── Audio/
│   │   └── AudioRecorder.swift
│   ├── Inference/
│   │   ├── WhisperEngine.swift
│   │   ├── LLMPostProcessor.swift
│   │   └── ModelStore.swift
│   ├── Injection/
│   │   └── TextInjector.swift
│   ├── Overlay/
│   │   ├── OverlayWindow.swift
│   │   └── OverlayView.swift
│   ├── Settings/
│   │   ├── SettingsWindow.swift
│   │   ├── HotKeyCaptureView.swift
│   │   └── PermissionsView.swift
│   └── Permissions/
│       └── PermissionsManager.swift
├── Resources/
│   └── Info.plist                      # LSUIElement, NSMicrophoneUsageDescription, etc.
├── Tests/WhisperLocalTests/
│   ├── TextInjectorTests.swift
│   └── DictationControllerTests.swift
├── Scripts/
│   └── make-app-bundle.sh              # wrap binary in .app for Finder launch
├── README.md
└── docs/superpowers/specs/...
```

## 8. Dependencies

| Package | Purpose |
|---|---|
| [`ml-explore/mlx-swift`](https://github.com/ml-explore/mlx-swift) | MLX core for Swift |
| [`ml-explore/mlx-swift-examples`](https://github.com/ml-explore/mlx-swift-examples) | Whisper + LLM implementations |
| [`soffes/HotKey`](https://github.com/soffes/HotKey) | Global hotkey registration |

All other functionality uses Apple frameworks: AppKit, SwiftUI, AVFoundation, Combine, Carbon (via HotKey).

## 9. Permissions (Info.plist)

- `NSMicrophoneUsageDescription` — "WhisperLocal needs the microphone to transcribe your speech locally."
- `LSUIElement` = `true` (no Dock icon).
- Accessibility & Input Monitoring are TCC permissions, granted via System Settings after first attempted use.

## 10. Build & Run

```bash
swift build -c release
./Scripts/make-app-bundle.sh    # produces WhisperLocal.app
open WhisperLocal.app
```

- Ad-hoc signed (`codesign --sign -`).
- No notarization. Gatekeeper bypass via right-click → Open on first launch.

## 11. Risks & Open Questions

| Risk | Mitigation |
|---|---|
| `mlx-swift-examples` Whisper API may evolve | Pin to specific commit; isolate behind `WhisperEngine` protocol so we can swap. |
| CGEvent paste fails in some apps (e.g., sandboxed editors) | Detect injection failure via app focus check; fall back to leaving text in pasteboard + showing notification. |
| Both models resident ≈ 6 GB RAM — fine on 64 GB but heavy on lower machines | Out of scope (target hardware: M5 Max 64 GB). |
| First-launch model download is multi-GB | Progress UI in onboarding sheet. |
| Input Monitoring permission required for global hotkey on recent macOS | PermissionsManager detects + guides. |

## 12. Success Criteria (MVP)

1. Press-and-hold `⌃⌥`, speak 5 seconds of German, release → cleaned transcript appears at cursor
   in Terminal within < 2 s end-to-end on M5 Max.
2. Same flow in VS Code, Slack, Chrome, TextEdit — all work with Umlauts intact.
3. Hotkey can be changed in Settings and persists across launches.
4. LLM toggle in Settings disables post-processing; raw transcript is injected.
5. App survives 100 consecutive dictations without leaking memory > 100 MB beyond resident model size.
