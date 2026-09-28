# Dictum for iPhone

A voice keyboard for iOS plus a small companion app. Switch to the Dictum keyboard in any app, tap
the mic, talk, and the cleaned-up text is typed for you.

## What's in the box

- **Keyboard extension** (`Keyboard/`): mic key with live transcript preview, tap-to-toggle or
  hold-to-talk, undo, space, return, delete, globe. Optional ✨ Command key: select text, say
  "make this shorter", the selection is rewritten.
- **App** (`App/`): setup checklist (enable keyboard, Full Access, permissions), an in-app
  dictation scratchpad with copy/share, shared history with stats, and settings.
- **Shared code** (`Shared/`): App Group settings, keychain, microphone capture, the live
  transcriber, and the cleanup/polish pipeline. `DictumCore` (one folder up) supplies the text
  cleaner, dictionary, WAV encoder and API client that the Mac app uses too.

Engines: **Apple Speech** (on-device, default) or any **OpenAI-compatible cloud API** (Groq free
tier preconfigured). On-device Whisper is not offered on iPhone: keyboard extensions get roughly
60 MB of memory, less than the smallest Whisper model.

## Build (Xcode required)

```bash
brew install xcodegen          # once
cd Dictum/iOS
make open                      # generates DictumMobile.xcodeproj and opens it
```

In Xcode:

1. Select the **DictumMobile** target → *Signing & Capabilities* → pick your Team (a free Apple ID
   works). Do the same for the **DictumKeyboard** target.
2. If Xcode complains that the bundle identifier or App Group is taken, change `app.dictum.mobile`
   and `group.app.dictum.mobile` to something unique in `project.yml`, both entitlements files,
   `Shared/MobileSettings.swift` (`SharedStorage.appGroup`) and `App/SetupView.swift`
   (`keyboardBundleID`), then run `make xcodeproj` again.
3. Plug in your iPhone, choose it as the run destination, press Run. On the phone, trust the
   developer certificate under Settings → General → VPN & Device Management the first time.

With a free Apple ID the build expires after 7 days; just press Run again.

## First run

The app opens on the Setup tab:

1. Settings → General → Keyboard → Keyboards → Add New Keyboard → **Dictum**.
2. Tap the Dictum keyboard → **Allow Full Access**. This is what lets a third-party keyboard use
   the microphone, read its own settings and reach the network. Dictum never logs keystrokes.
3. Allow Microphone (and Speech Recognition for the Apple engine).

Then open Notes, hold 🌐, pick Dictum, tap the mic, say something, tap again.

## Limitations

- iOS never lets third-party keyboards type into password fields or the phone dial pad.
- Apple Speech does not auto-detect languages; pick one in Settings (or leave it on your system
  language).
- Local AI servers (Ollama, LM Studio) must be reachable from the phone, so use the Mac's LAN
  address (for example `http://192.168.1.20:11434/v1`) and start Ollama with
  `OLLAMA_HOST=0.0.0.0 ollama serve`.
