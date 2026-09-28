# Dictum

Free, open-source voice dictation for macOS and iPhone, in the spirit of Wispr Flow. Hold a key,
talk, let go: the cleaned-up text appears wherever your cursor is, in any app.

- **Mac**: menu bar app, global shortcut, three speech engines. This document.
- **iPhone**: a voice keyboard plus companion app. See [`iOS/README.md`](iOS/README.md).

- **Hold-to-talk** with a global shortcut (default: Right ⌥, or Fn / any combo you like). Quick tap
  locks hands-free mode; Esc cancels.
- **Three speech engines**, switchable from the menu bar:
  - *Apple Speech* (built in, zero setup, mostly on-device) – the default.
  - *Whisper on-device* via [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift): one download,
    then fully offline on Apple Silicon.
  - *Cloud API*: any OpenAI-compatible endpoint. Groq's free tier is preconfigured, OpenAI and local
    servers (whisper.cpp, faster-whisper) work too.
- **Instant cleanup** that runs locally: filler words, stutters, "new line / new paragraph", capitalization,
  optional spoken punctuation, and a personal dictionary ("super base" → "Supabase").
- **Optional AI polish** through any OpenAI-compatible chat model (Groq free tier, Ollama or LM Studio
  fully local, OpenAI). Tone adapts to the app you're typing into; add your own standing instructions.
- **Command mode**: select text, hold the command key, say "make this more formal" or
  "turn this into bullet points". With nothing selected it writes what you ask for.
- **Floating status pill**, start/stop sounds, clipboard restored after pasting, smart spacing.
- **History & stats** window (words dictated, speaking speed, typing time saved) – stored locally.
- Menu bar only, launch at login, no accounts, no telemetry, no subscription.

## Requirements

- macOS 14 Sonoma or newer (Apple Silicon recommended for the on-device Whisper engine).
- Xcode 15.3+ or the Command Line Tools (`xcode-select --install`) for building.

## Build & run

```bash
cd Dictum
make run          # builds build/Dictum.app in release mode and opens it
make install      # copies it to /Applications
```

The first build downloads WhisperKit and compiles everything; expect 3–6 minutes. Later builds are
incremental.

Prefer Xcode? `brew install xcodegen && make xcodeproj`, then open `Dictum.xcodeproj` and press Run.

On first launch Dictum opens a setup window and asks for:

1. **Microphone** – so it can hear you.
2. **Accessibility** – needed for the global shortcut and to type into other apps. Toggle *Dictum* on
   in System Settings → Privacy & Security → Accessibility.
3. **Speech Recognition** – only for the Apple engine (the default).

Then click into any text field, hold **Right ⌥**, say something, release.

### Using the Fn / 🌐 key

Set System Settings → Keyboard → *Press 🌐 key to* → **Do Nothing**, otherwise macOS Dictation or the
emoji picker opens as well. Then pick "Fn" in Settings → General.

### Ad-hoc signing caveat

`make app` signs the bundle ad-hoc. macOS ties the Accessibility grant to the code signature, so after
rebuilding you may need to switch Dictum off and on again in the Accessibility list. To avoid that,
sign with your own certificate:

```bash
CODESIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" make app
```

## Engines and providers

| Engine | Cost | Privacy | Notes |
| --- | --- | --- | --- |
| Apple Speech | free | on-device where the language supports it | Works instantly. Uses the language you pick; no auto-detection. |
| Whisper (WhisperKit) | free | fully offline | Models 75 MB – 630 MB. "Large v3 Turbo" is the sweet spot on M1+. First load compiles the model (about a minute). |
| Cloud API | provider-dependent | audio leaves your Mac | Groq: fast, generous free tier. OpenAI `whisper-1` / `gpt-4o-mini-transcribe`. Any local OpenAI-compatible server. |

AI polish and command mode use a chat model from the same kind of endpoint. Fully local options:
[Ollama](https://ollama.com) (`ollama pull llama3.2`, URL `http://localhost:11434/v1`) or LM Studio.
API keys are stored in your login keychain.

## Project layout

```
Dictum/
├── iOS/                     iPhone app + keyboard extension (XcodeGen spec, see iOS/README.md)
├── Package.swift            SwiftPM manifest for the Mac app (depends on DictumCore + WhisperKit)
├── Makefile, scripts/       make app | run | install | xcodeproj | test-core
├── project.yml              XcodeGen spec (optional Xcode project)
├── Resources/               Info.plist, entitlements
├── DictumCore/              Foundation-only library: text cleanup, dictionary, WAV encoder,
│                            OpenAI-compatible client, prompts. `swift test` runs in seconds.
└── Sources/Dictum/
    ├── DictumApp.swift            @main: menu bar extra + Settings scene
    ├── AppDelegate.swift          wiring, first-launch setup window
    ├── DictationController.swift  state machine: hotkey → record → transcribe → clean → insert
    ├── Hotkeys/                   CGEvent tap for global shortcuts (modifier-only or combos)
    ├── Audio/                     AVAudioEngine capture → 16 kHz mono float
    ├── Engines/                   Apple Speech, WhisperKit, cloud transcription
    ├── LLM/                       optional polish + command mode
    ├── Insertion/                 Accessibility API + clipboard/⌘V insertion
    ├── Settings/, Storage/        settings model, history store, keychain
    └── UI/                        overlay pill, menu, settings tabs, onboarding, history
```

Run the core unit tests with `make test-core` (or `cd DictumCore && swift test`).

## Troubleshooting

- **Nothing happens when I hold the key.** Accessibility isn't granted (menu bar icon shows a slashed
  waveform). Open *Setup & permissions…* from the menu.
- **Text is pasted but my clipboard changed.** "Restore the clipboard after pasting" is on by default;
  some apps take longer than 350 ms to read the pasteboard. Turn the option off if it bites you.
- **Text lands in the wrong place.** The app that had focus when you pressed the key receives the
  text. Click into the field first, then hold the key.
- **Whisper download fails.** Models come from huggingface.co. Check the network, or pick another
  model in Settings → Speech. Downloads live in `~/Library/Application Support/Dictum/Models`.
- **Right ⌥ + letter shortcuts start dictation.** They cancel automatically within 0.6 s when another
  key is pressed. If that bothers you, pick a key-combo shortcut instead.

## Roadmap

- Streaming partial results in the Mac overlay while you speak (the iPhone keyboard already does this).
- Apple's newer `SpeechAnalyzer` API on macOS 26+ as a fourth engine.
- Per-app style presets and snippets.

## License

MIT.
