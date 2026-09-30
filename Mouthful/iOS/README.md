# Mouthful for iPhone

A voice keyboard for iOS plus a small companion app. Switch to the Mouthful keyboard in any app, tap
the mic, talk, and the cleaned-up text is typed for you.

## What's in the box

- **Keyboard extension** (`Keyboard/`): mic key with live transcript preview, tap-to-toggle or
  hold-to-talk, undo, space, return, delete, globe. Optional ✨ Command key: select text, say
  "make this shorter", the selection is rewritten.
- **App** (`App/`): setup checklist (enable keyboard, Full Access, permissions), an in-app
  dictation scratchpad with copy/share, shared history with stats, and settings.
- **Shared code** (`Shared/`): App Group settings, keychain, microphone capture, the live
  transcriber, and the cleanup/polish pipeline. `MouthfulCore` (one folder up) supplies the text
  cleaner, dictionary, WAV encoder and API client that the Mac app uses too.

Engines: **Apple Speech** (on-device, default) or any **OpenAI-compatible cloud API** (Groq free
tier preconfigured). On-device Whisper is not offered on iPhone: keyboard extensions get roughly
60 MB of memory, less than the smallest Whisper model.

## Build (Xcode required, a free Apple ID is enough)

One-time setup, about 30 minutes, no coding:

1. Install **Xcode** from the Mac App Store. Open it once, accept the license and let it install the
   **iOS** platform when it asks.
2. In Xcode: **Xcode → Settings… → Accounts → +** and sign in with your Apple ID.
3. On the iPhone: **Settings → Privacy & Security → Developer Mode → On** (the phone restarts). Plug it
   into the Mac with a cable and tap **Trust** on the phone.
4. In Terminal:

   ```bash
   cd Mouthful
   make iphone        # first run downloads XcodeGen (~14 MB), then opens the project in Xcode
   ```

5. In Xcode, click the blue **MouthfulMobile** icon at the top of the left sidebar. Under *TARGETS*
   select **MouthfulMobile → Signing & Capabilities** and pick your name under **Team** (it says
   "Personal Team"). Do the same for the **MouthfulKeyboard** target.
6. In the toolbar, change the run destination from a simulator to **your iPhone**, then press the
   **Run** ▶ button. The first build takes a few minutes.
7. The first launch fails with "Untrusted Developer": on the phone go to **Settings → General → VPN &
   Device Management**, tap your Apple ID and **Trust** it, then press Run again.

Free Apple ID limits: the app stops opening after **7 days** (plug in and press Run again to renew),
and at most three sideloaded apps per phone. A paid Apple Developer account ($99/year) removes both
and is required for TestFlight or the App Store.

If Xcode complains that the bundle identifier or App Group is already taken, change
`com.rocketlaunchmedia.mouthful.ios` and `group.com.rocketlaunchmedia.mouthful` to something unique in
`project.yml`, both `.entitlements` files, `Shared/MobileSettings.swift` (`SharedStorage.appGroup`) and
`App/SetupView.swift` (`keyboardBundleID`), then run `make iphone` again.

## First run

The app opens on the Setup tab:

1. Settings → General → Keyboard → Keyboards → Add New Keyboard → **Mouthful**.
2. Tap the Mouthful keyboard → **Allow Full Access**. This is what lets a third-party keyboard use
   the microphone, read its own settings and reach the network. Mouthful never logs keystrokes.
3. Allow Microphone (and Speech Recognition for the Apple engine).

Then open Notes, hold 🌐, pick Mouthful, tap the mic, say something, tap again.

## Limitations

- iOS never lets third-party keyboards type into password fields or the phone dial pad.
- Apple Speech does not auto-detect languages; pick one in Settings (or leave it on your system
  language).
- Local AI servers (Ollama, LM Studio) must be reachable from the phone, so use the Mac's LAN
  address (for example `http://192.168.1.20:11434/v1`) and start Ollama with
  `OLLAMA_HOST=0.0.0.0 ollama serve`.
