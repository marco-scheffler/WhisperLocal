# WhisperLocal

> 🎤 **Local-first speech-to-text for macOS.** Press a hotkey, speak, and the transcript appears at your cursor — in any app, including the terminal. 100% on-device. Zero cloud calls.

Powered by [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (Apple Silicon-optimized Whisper via CoreML) and Apple's [FoundationModels](https://developer.apple.com/documentation/foundationmodels) (Apple Intelligence on-device LLM for grammar and filler cleanup).

---

## Features

- **System-wide dictation** — works in Terminal, VS Code, Slack, Mail, Notes, browser fields, anywhere `⌘V` works
- **Toggle or push-to-talk** — tap to start, tap again or just stay silent for 2 s to stop. Configurable.
- **German + English** with on-the-fly auto-detection
- **Optional on-device LLM cleanup** removes "ähm", fixes punctuation and capitalization
- **Audio device picker** — choose mic in-app (built-in, USB, Bluetooth)
- **Live model download progress** in a floating overlay
- **Configurable global hotkey**, modifier-only or key+modifier combos
- **In-app log viewer** for easy debugging — no Console.app needed
- **Dynamic menu bar icon** that reflects the current state
- **Launch at login** — auto-start after reboot
- **No cloud, no telemetry, no account** — runs entirely on your Mac

## Requirements

- macOS 15 (Sequoia) or later — macOS 26 (Tahoe) recommended for the LLM cleanup
- Apple Silicon (M1 or later). Tested on M5 Max.
- ~600 MB free disk for the Whisper model (downloaded on first launch)
- Apple Intelligence enabled (System Settings → Apple Intelligence & Siri) for the LLM cleanup. Optional — the app falls back to raw transcripts if unavailable.

## Installation

### Quick install (recommended)

```bash
git clone https://github.com/WEBER-marcoscheffler/WhisperLocal.git
cd WhisperLocal

# One-time: create a stable code-signing cert so macOS keeps permissions
# across rebuilds (TCC binds permissions to the signing identity).
./Scripts/create-dev-cert.sh

# Build, sign, and copy WhisperLocal.app to /Applications
./Scripts/install.sh

open /Applications/WhisperLocal.app
```

On first launch, grant the three permissions when prompted:

1. **Microphone** — for capturing audio
2. **Accessibility** — so the app can paste `⌘V` into the focused window. System Settings → Privacy & Security → Accessibility → enable `WhisperLocal`.
3. **Input Monitoring** — for the global hotkey. System Settings → Privacy & Security → Input Monitoring → enable `WhisperLocal`.

Quit and reopen WhisperLocal once after granting Accessibility & Input Monitoring so it picks up the new permissions.

The Whisper model (~600 MB) downloads in the background on first launch. You can watch progress in the overlay or under Settings → Whisper model.

### Run from source without installing

```bash
swift run
```

This builds and starts the app from the project directory. Useful for development.

## Usage

1. **Hold or tap** the hotkey (default `⌥⌘`, hold; configurable in Settings).
2. **Speak.** The floating overlay shows the live audio level.
3. **Stop:**
   - **Toggle mode (default):** tap the hotkey again, or stay silent for 2 seconds — auto-stop kicks in.
   - **Push-to-talk mode:** release the hotkey.
4. The transcript is cleaned (if LLM is enabled) and pasted at the cursor.

### Hotkeys

Open Settings (menu bar icon → Settings…) → **Hotkey** → click the field → press your desired combo.

Two flavors are supported:

| Type | Example | When pressed/released |
|---|---|---|
| Modifier-only | `⌥⌘`, `⌃⌥` | Hold all modifiers down → triggers; release any → ends |
| Key + modifier | `⌘⇧Space`, `F13` | Tap the key → triggers |

## Settings

Click the menu bar icon → Settings…

| Section | What it does |
|---|---|
| **Whisper model** | Live status of the on-device Whisper model (downloading / loading / ready) |
| **Microphone** | Pick a specific input device or follow the system default |
| **Language** | Auto-detect / German / English |
| **Hotkey** | Capture a new combo + choose Push-to-talk or Toggle mode |
| **Post-processing** | Toggle the FoundationModels LLM cleanup (default on) |
| **Startup** | Launch at login (uses `SMAppService`) |
| **Permissions** | Live status of Mic / Accessibility / Input Monitoring |
| **Logs** | In-app log viewer — last 500 entries, with Copy and Clear |

## Privacy

- **Nothing leaves your Mac.** The Whisper model runs locally via CoreML. The optional LLM cleanup uses Apple's on-device FoundationModels. Audio is never sent to a server.
- **No analytics, no crash reporting, no network calls** at runtime after the initial model download from HuggingFace.
- The Whisper model is downloaded once from `argmaxinc/whisperkit-coreml` on HuggingFace and cached in `~/Library/Application Support/io.github.weber-marcoscheffler.WhisperLocal/Models/`.
- No third-party SDKs.

## Architecture

| Layer | Component | Responsibility |
|---|---|---|
| Capture | `AudioRecorder` | AVAudioEngine → 16 kHz mono float32, with selectable CoreAudio input device |
| Hotkey | `HotKeyManager` | `soffes/HotKey` for combos, global `NSEvent.flagsChanged` monitor for modifier-only |
| STT | `WhisperEngine` | WhisperKit large-v3 multilingual model via CoreML; downloads to Application Support |
| Cleanup | `LLMPostProcessor` | Apple `FoundationModels` (Apple Intelligence) with 3 s timeout fallback |
| Injection | `TextInjector` | `NSPasteboard` write → `CGEvent` ⌘V → snapshot restore (so we don't trample your clipboard) |
| Orchestration | `DictationController` | `@MainActor` state machine: idle → recording → transcribing → (post-processing) → injecting |
| UI | `OverlayWindow`, `SettingsWindow`, `MenuBarController` | Floating NSPanel + SwiftUI, settings window, menu bar status item |

## Development

```bash
swift build               # debug build
swift test                # 11 unit tests
swift run                 # launch the app from source
./Scripts/make-app-bundle.sh   # produce a signed WhisperLocal.app
./Scripts/install.sh           # build + install to /Applications
./Scripts/generate-icon.sh     # regenerate the app icon
```

### Project layout

```
WhisperLocal/
├── Package.swift
├── Sources/WhisperLocal/
│   ├── App.swift / AppDelegate.swift
│   ├── DictationController.swift     # state machine
│   ├── Audio/                        # AudioRecorder, AudioDeviceManager
│   ├── Hotkey/                       # HotKeyManager, HotKeyBinding
│   ├── Inference/                    # WhisperEngine, LLMPostProcessor, ModelStore
│   ├── Injection/                    # TextInjector
│   ├── MenuBar/                      # MenuBarController
│   ├── Overlay/                      # OverlayWindow, OverlayView, OverlayState
│   ├── Permissions/                  # PermissionsManager
│   ├── Settings/                     # SettingsView, HotKeyCaptureView, LogView, …
│   ├── LoginItem.swift               # SMAppService wrapper
│   ├── Logging.swift                 # LogStore + Log helper
│   └── Preferences.swift             # UserDefaults wrapper
├── Resources/
│   ├── Info.plist
│   └── AppIcon.icns
├── Scripts/
│   ├── GenerateIcon.swift            # programmatic icon source
│   ├── generate-icon.sh
│   ├── create-dev-cert.sh
│   ├── make-app-bundle.sh
│   └── install.sh
└── Tests/WhisperLocalTests/
```

### Re-skinning the icon

Edit `Scripts/GenerateIcon.swift` (it draws via AppKit), then:
```bash
./Scripts/generate-icon.sh
./Scripts/install.sh
```

## Troubleshooting

| Symptom | What to check |
|---|---|
| "Too short — hold longer" | Hold the hotkey for at least 0.5 s. If you held longer and still see this, look at Settings → Logs for `AudioRecorder` entries — likely the wrong input device. |
| "No speech detected" | Whisper transcribed silence. Try Settings → Language → German (instead of Auto). |
| `transcribe failed: CancellationError()` | Old bug, fixed in 0.1.0+. Update. |
| Text comes out in English when you spoke German | Settings → Language → German. Auto-detect can pick wrong on short utterances. |
| Permissions reset on every rebuild | You're signing ad-hoc. Run `./Scripts/create-dev-cert.sh` once. |
| App not launching at login | System Settings → General → Login Items & Extensions → approve `WhisperLocal`. |

## Notarized releases (maintainers only)

For public releases the app is signed with a **Developer ID Application** certificate and notarized by Apple so Gatekeeper opens it without warnings.

### One-time setup

1. Apple Developer Program membership ($99/year). Sign up at <https://developer.apple.com/programs/>.
2. Download a **Developer ID Application** certificate from <https://developer.apple.com/account/resources/certificates> and double-click the `.cer` to install into your login keychain.
3. Create an **app-specific password** at <https://account.apple.com/account/manage> → Sign-In & Security → App-Specific Passwords. Name it `whisperlocal-notarize`. Save the 16-character password.
4. Look up your Team ID at <https://developer.apple.com/account> → Membership (10-character alphanumeric).
5. Store credentials so `notarytool` can run unattended:
   ```bash
   xcrun notarytool store-credentials whisperlocal-notarize \
       --apple-id "you@example.com" \
       --team-id  "ABCDE12345" \
       --password "abcd-efgh-ijkl-mnop"
   ```

### Cutting a notarized release

```bash
./Scripts/release.sh v0.1.1
```

This does the full pipeline:
1. Bumps `CFBundleShortVersionString` to `0.1.1` in `Info.plist`
2. Builds with hardened runtime + Developer ID signature + entitlements
3. Uploads to Apple's notarization service and waits for the verdict (typically 1–5 minutes)
4. Staples the notarization ticket onto the app bundle
5. Tags `v0.1.1`, pushes the tag, creates a GitHub release with the notarized zip attached

### Daily development still uses `WhisperLocal Dev`

`make-app-bundle.sh` picks the strongest signing identity it finds:

1. `$SIGN_IDENTITY` env var if set (used by `release.sh`)
2. `Developer ID Application: ...` certificate in keychain
3. Self-signed `WhisperLocal Dev` (from `create-dev-cert.sh`) — for local dev
4. Ad-hoc

So you can keep using `./Scripts/install.sh` for dev iterations without affecting the release path.

## Credits

- [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) by Argmax for the Apple Silicon-optimized Whisper inference
- [OpenAI Whisper](https://github.com/openai/whisper) for the underlying STT model
- [soffes/HotKey](https://github.com/soffes/HotKey) for global hotkey registration
- Apple's `FoundationModels` framework for the on-device LLM
- Inspired by [whisperbar.pro](https://whisperbar.pro)

## License

MIT — see [LICENSE](LICENSE).
