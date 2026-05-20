# WhisperLocal

Local macOS speech-to-text. Press and hold a global hotkey, speak, release — the transcript is pasted into the focused app. Uses Apple Silicon-optimized Whisper (via WhisperKit / CoreML) for transcription and Apple's on-device language model (FoundationModels / Apple Intelligence) for grammar and filler-word cleanup. No cloud calls.

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon (Apple Intelligence required for LLM cleanup)
- ~600 MB free disk for the Whisper model

## Build

    swift test
    ./Scripts/make-app-bundle.sh
    open WhisperLocal.app

## First launch

Grant the following permissions when prompted:

1. **Microphone** — for recording
2. **Accessibility** — so the app can paste ⌘V into the focused window. Open System Settings → Privacy & Security → Accessibility and add `WhisperLocal.app`.
3. **Input Monitoring** — for the global hotkey. System Settings → Privacy & Security → Input Monitoring → add `WhisperLocal.app`.

The Whisper model (~600 MB) downloads automatically on first transcription. Subsequent launches reuse the cached model.

## Default hotkey

Hold `⌃⌥` (Control + Option). Configurable via menu bar icon → Settings…

## Settings

- **Hotkey** — click the field, press your desired combo
- **Post-processing** — toggle Apple Intelligence cleanup (default on)
- **Permissions** — status indicators with shortcuts to System Settings

## Architecture

| Layer | Component |
|---|---|
| Capture | `AudioRecorder` (AVAudioEngine → 16 kHz mono float32) |
| Hotkey | `HotKeyManager` (modifier-only push-to-talk via NSEvent global monitor) |
| STT | `WhisperEngine` (WhisperKit, large-v3 multilingual) |
| Cleanup | `LLMPostProcessor` (FoundationModels / Apple Intelligence, 3 s timeout) |
| Injection | `TextInjector` (Pasteboard + CGEvent ⌘V + snapshot restore) |
| Orchestration | `DictationController` (@MainActor state machine) |
| UI | `OverlayWindow` (NSPanel + SwiftUI), `SettingsWindow`, `MenuBarController` |

## Development

    swift build
    swift test
