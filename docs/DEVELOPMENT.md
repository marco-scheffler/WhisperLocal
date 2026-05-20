# WhisperLocal — Developer & Maintainer Documentation

This is the deep-dive doc for anyone building, modifying, or releasing WhisperLocal. For a quick overview, see the [README](../README.md).

## Table of contents

- [Requirements](#requirements)
- [Build from source](#build-from-source)
- [First-launch permissions](#first-launch-permissions)
- [Usage modes](#usage-modes)
- [All settings](#all-settings)
- [Privacy](#privacy)
- [Architecture](#architecture)
- [Project layout](#project-layout)
- [Scripts reference](#scripts-reference)
- [Troubleshooting](#troubleshooting)
- [Notarized releases (maintainers)](#notarized-releases-maintainers)
- [Re-skinning the icon](#re-skinning-the-icon)

## Requirements

- macOS 15 (Sequoia) or later — macOS 26 (Tahoe) recommended for the LLM cleanup
- Apple Silicon (M1+). Tested on M5 Max.
- ~600 MB free disk for the Whisper model (auto-downloaded on first launch)
- Apple Intelligence enabled (System Settings → Apple Intelligence & Siri) for the optional LLM cleanup. The app degrades gracefully if it's unavailable — raw Whisper transcripts get pasted directly.

## Build from source

```bash
git clone https://github.com/WEBER-marcoscheffler/WhisperLocal.git
cd WhisperLocal

# One-time: stable self-signed code-signing cert so macOS TCC permissions
# survive rebuilds (TCC binds permissions to the signing identity).
./Scripts/create-dev-cert.sh

# Build, sign, install into /Applications
./Scripts/install.sh

open /Applications/WhisperLocal.app
```

Alternatively, just run `swift run` to start the app from the project directory without installing — useful during active development.

### Why the dev cert?

Each Swift build produces a binary with a new content hash. macOS TCC (the system that grants Microphone / Accessibility / Input Monitoring permissions) binds entries to a (code requirement, bundle id) pair. With ad-hoc signing (`codesign --sign -`), the code requirement *is* the binary hash — so every rebuild invalidates your TCC grants and you have to re-tick the boxes in System Settings.

A self-signed code-signing certificate gives you a stable code requirement string. Sign the binary with the same cert every time and TCC keeps your permissions across rebuilds. `create-dev-cert.sh` generates the cert via `/usr/bin/openssl` (LibreSSL, since Homebrew's openssl 3.x produces PKCS12 files macOS `security import` can't read) and imports it into your login keychain.

## First-launch permissions

When you first open WhisperLocal you'll be asked for three permissions. Grant all three and **quit + reopen the app** so it picks up the new permissions cleanly.

| Permission | Where | Why |
|---|---|---|
| **Microphone** | System prompt | Capture your audio |
| **Accessibility** | System Settings → Privacy & Security → Accessibility | Post a synthetic ⌘V to the focused window |
| **Input Monitoring** | System Settings → Privacy & Security → Input Monitoring | Listen for the global hotkey |

The first transcription takes ~2–5 minutes because the Whisper model (~600 MB) downloads from HuggingFace into `~/Library/Application Support/io.github.weber-marcoscheffler.WhisperLocal/Models/`. The progress is visible in the floating overlay and under Settings → Whisper model. Every subsequent transcription is sub-second.

## Usage modes

The default mode is **Toggle**. The first hotkey tap starts recording; recording stops when you either tap the hotkey again or stay silent for ~2 seconds. A hard 60-second cap prevents runaway sessions.

The alternative is classic **Push-to-talk**: hold the hotkey while speaking, release to finish. Switch in Settings → Hotkey → Mode.

The default hotkey is **⌥⌘** (Option + Command) held as a modifier-only push-to-talk trigger. Configurable in Settings — both modifier-only combos and standard key combos (e.g. `⌘⇧Space`, `F13`) are supported.

## All settings

Click the menu bar icon → **Settings…**

| Section | What it controls |
|---|---|
| **Whisper model** | Live status: not started / downloading X% / loading / ready / error |
| **Microphone** | Pick an input device (Built-in, USB, Bluetooth) or follow the system default. Refresh button to rescan. |
| **Language** | Auto-detect / German / English. Auto can mispick on very short utterances — set explicitly if you only speak one. |
| **Hotkey** | Capture a new combo. Mode: Push-to-talk or Toggle. |
| **Post-processing** | Toggle the FoundationModels LLM cleanup (default on). When off, the raw Whisper transcript is pasted. |
| **Startup** | Launch at login via `SMAppService`. Live status indicator. |
| **Permissions** | Status of Mic / Accessibility / Input Monitoring with one-click "Open Settings" buttons. Polls every second so the state updates as you grant. |
| **Logs** | In-app log viewer — last 500 entries. Color-coded by level. Copy + Clear buttons. |

## Privacy

- **Nothing leaves your Mac at runtime.** Whisper runs locally via CoreML. The optional LLM cleanup uses Apple's on-device FoundationModels which run in a sandboxed XPC process. Audio is never transmitted.
- **No analytics, no crash reporting, no third-party SDKs.** The only network activity at runtime is zero.
- **First-launch download:** the Whisper model (~600 MB) is fetched from `argmaxinc/whisperkit-coreml` on HuggingFace and cached in `~/Library/Application Support/io.github.weber-marcoscheffler.WhisperLocal/Models/`. After that there is no network activity at all.
- **Local LLM model:** none. FoundationModels is a system framework — its weights ship with macOS and are shared across apps.
- **Pasteboard:** when injecting text we briefly write to the system clipboard, post ⌘V, then restore the previous clipboard contents after 600 ms. We do not read your existing clipboard.

## Architecture

```
            ┌──────────────────────────────────────────────┐
            │  AppDelegate (LSUIElement = true)            │
            │                                              │
            │  ├── MenuBarController   (dynamic icon)      │
            │  ├── HotKeyManager       (global hotkey)     │
            │  ├── SettingsWindow      (SwiftUI)           │
            │  ├── OverlayWindow       (NSPanel.floating)  │
            │  └── DictationController (state machine)     │
            │      ├── AudioRecorder                       │
            │      ├── WhisperEngine                       │
            │      ├── LLMPostProcessor                    │
            │      └── TextInjector                        │
            └──────────────────────────────────────────────┘
```

| Layer | Component | Responsibility |
|---|---|---|
| Capture | `AudioRecorder` | AVAudioEngine → AVAudioConverter → 16 kHz mono float32. Selectable CoreAudio input device. RMS level publisher for the overlay. |
| Hotkey | `HotKeyManager` | `soffes/HotKey` for key combos; global `NSEvent.flagsChanged` monitor for modifier-only push-to-talk. |
| STT | `WhisperEngine` | Actor wrapping `WhisperKit`. Downloads `large-v3-v20240930_626MB` on first use via `WhisperKit.download(progressCallback:)`. |
| Cleanup | `LLMPostProcessor` | `FoundationModels.LanguageModelSession`. 3 s timeout via `TaskGroup` race — falls back to raw transcript. |
| Injection | `TextInjector` | `NSPasteboard` snapshot → write transcript → `CGEvent(virtualKey: kVK_ANSI_V)` with `.maskCommand` → restore snapshot after 600 ms. |
| State machine | `DictationController` | `@MainActor` with `Published var state`. Drives overlay phase, owns the silence monitor. |
| UI | `OverlayWindow`, `OverlayView`, `OverlayState` | Borderless `NSPanel` at `.floating` level + non-activating, hosts SwiftUI view that observes the controller. |
| | `MenuBarController` | `NSStatusItem` with SF Symbol that swaps based on dictation state. |
| | `SettingsWindow`, `SettingsView`, sub-views | Standard `NSWindow` wrapping a SwiftUI `Form`. |

### State machine

```
                ┌──────────┐
                │   idle   │◄────────────────────┐
                └────┬─────┘                     │
       hotkey down   │                           │
                     ▼                           │
              ┌────────────┐                     │
              │ recording  │                     │
              └────┬───────┘                     │
       hotkey up   │  (or silence ≥ 2s)          │
                   ▼                             │
            ┌──────────────┐                     │
            │ transcribing │                     │
            └────┬─────────┘                     │
                 │                               │
       LLM on?   ├── yes ──► post_processing ──┐ │
                 │                              ▼│
                 └── no ──────────────────► injecting
```

Failure transitions: any error → `idle` with the overlay briefly showing `.error(message)`.

## Project layout

```
WhisperLocal/
├── Package.swift
├── Sources/WhisperLocal/
│   ├── App.swift / AppDelegate.swift
│   ├── DictationController.swift
│   ├── Audio/                        # AudioRecorder, AudioDeviceManager, Recording protocol
│   ├── Hotkey/                       # HotKeyManager, HotKeyBinding
│   ├── Inference/                    # WhisperEngine, LLMPostProcessor, ModelStore, Transcribing, ModelStatus
│   ├── Injection/                    # TextInjector
│   ├── MenuBar/                      # MenuBarController
│   ├── Overlay/                      # OverlayWindow, OverlayView, OverlayState
│   ├── Permissions/                  # PermissionsManager
│   ├── Settings/                     # SettingsView, HotKeyCaptureView, PermissionsView, LogView, AudioDevicePicker
│   ├── LoginItem.swift               # SMAppService wrapper
│   ├── Logging.swift                 # LogStore + Log helper
│   └── Preferences.swift             # UserDefaults wrapper
├── Resources/
│   ├── Info.plist
│   ├── AppIcon.icns
│   └── WhisperLocal.entitlements
├── Scripts/
│   ├── GenerateIcon.swift            # programmatic icon source
│   ├── generate-icon.sh
│   ├── create-dev-cert.sh
│   ├── make-app-bundle.sh
│   ├── install.sh
│   ├── notarize.sh
│   └── release.sh
└── Tests/WhisperLocalTests/
```

## Scripts reference

| Script | What it does |
|---|---|
| `Scripts/create-dev-cert.sh` | One-time. Creates a self-signed `WhisperLocal Dev` code-signing certificate in your login keychain. Idempotent. |
| `Scripts/make-app-bundle.sh` | Build the release binary, wrap it into `WhisperLocal.app`, write `Contents/PkgInfo`, sign with the strongest identity available (env override → Developer ID → self-signed → ad-hoc). |
| `Scripts/install.sh` | `make-app-bundle.sh` + stop any running instance + copy to `/Applications`. Daily dev workflow. |
| `Scripts/generate-icon.sh` | Render `Resources/AppIcon.icns` from `Scripts/GenerateIcon.swift` (AppKit drawing). |
| `Scripts/notarize.sh` | Submit a built `.app` to Apple's notarization service and staple the ticket. Requires Developer ID signing + a stored credential profile. |
| `Scripts/release.sh vX.Y.Z` | Full release pipeline: bump version → build → sign Developer ID → notarize → staple → zip → tag → push → create GitHub release with notarized zip attached. |

## Troubleshooting

| Symptom | What to check |
|---|---|
| Overlay says "Too short — hold longer" but you held for 5 s | Look in Settings → Logs for `AudioRecorder` entries. Likely wrong input device — pick a specific mic in Settings → Microphone instead of "System default". |
| "No speech detected" | Whisper transcribed silence. Try Settings → Language → German (auto-detect can mispick on short utterances). |
| Transcript comes out in English when you spoke German | Same as above. Set Language to German explicitly. |
| `transcribe failed: CancellationError()` | Fixed in `573ef0b` — silence-monitor self-cancellation. If you're seeing this on master, file an issue. |
| Permissions reset on every rebuild | You're signing ad-hoc. Run `./Scripts/create-dev-cert.sh` once and rebuild. |
| App doesn't launch at login | System Settings → General → Login Items & Extensions → approve `WhisperLocal`. |
| Gatekeeper blocks "Unidentified developer" | You downloaded a self-built `.app` rather than the notarized release zip. Right-click → Open → Open in the dialog. Or download from [Releases](https://github.com/WEBER-marcoscheffler/WhisperLocal/releases/latest). |
| spctl says "rejected (the code is valid but does not seem to be an app)" | Means `Info.plist` is missing `CFBundlePackageType=APPL` and/or `CFBundleExecutable`. Fixed since v0.1.1. |

## Notarized releases (maintainers)

For public releases the app is signed with a Developer ID Application certificate and notarized by Apple so Gatekeeper opens it without warnings.

### One-time setup

1. Apple Developer Program membership ($99/year). Sign up at <https://developer.apple.com/programs/>.
2. Generate a **Developer ID Application** certificate at <https://developer.apple.com/account/resources/certificates/add>:
   - In Keychain Access → Certificate Assistant → "Request a Certificate from a Certificate Authority", choose "Saved to disk"
   - Upload the CSR on the Apple page, choose **Developer ID Application**
   - Download the resulting `.cer` and double-click to import into login keychain
3. Create an **app-specific password** at <https://account.apple.com/account/manage> → Sign-In & Security → App-Specific Passwords. Name it `whisperlocal-notarize`. Save the 16-character password — Apple only shows it once.
4. Look up your **Team ID** at <https://developer.apple.com/account> → Membership (10-character alphanumeric).
5. Store credentials so `notarytool` can run unattended:
   ```bash
   xcrun notarytool store-credentials whisperlocal-notarize \
       --apple-id "you@example.com" \
       --team-id  "ABCDE12345" \
       --password "abcd-efgh-ijkl-mnop"
   ```

### Cutting a release

```bash
./Scripts/release.sh v0.1.1
```

Pipeline:
1. Bumps `CFBundleShortVersionString` in `Info.plist` to `0.1.1`
2. Builds with hardened runtime + Developer ID signature + entitlements + secure timestamp
3. Uploads to Apple's notarization service and waits for verdict (typically 1–5 minutes)
4. Staples the ticket onto `.app/Contents/CodeResources`
5. Zips with `ditto -c -k --keepParent` (the only format Apple's tools handle correctly)
6. Tags `v0.1.1`, pushes the tag, creates a GitHub release with the notarized zip attached

The release notes are auto-generated from a template inside `release.sh` — edit them on the GitHub UI afterwards if you want anything richer.

### Signing identity priority in `make-app-bundle.sh`

1. `$SIGN_IDENTITY` env var if set (used by `release.sh`)
2. `Developer ID Application: ...` certificate in keychain → hardened runtime + entitlements
3. Self-signed `WhisperLocal Dev` (from `create-dev-cert.sh`) → no hardened runtime
4. Ad-hoc

So daily dev (`./Scripts/install.sh`) uses the self-signed identity automatically, and release builds upgrade to Developer ID automatically. You don't have to flip flags.

## Re-skinning the icon

The icon is drawn programmatically by `Scripts/GenerateIcon.swift` (AppKit / CoreGraphics). To change it:

1. Edit `Scripts/GenerateIcon.swift`
2. Run `./Scripts/generate-icon.sh` — produces `Resources/AppIcon.icns`
3. Run `./Scripts/install.sh` (or `./Scripts/release.sh vX.Y.Z`) to rebundle

To use a hand-designed icon instead: replace `Resources/AppIcon.icns` directly with a properly-built `.icns` file (use `iconutil -c icns my.iconset`).
