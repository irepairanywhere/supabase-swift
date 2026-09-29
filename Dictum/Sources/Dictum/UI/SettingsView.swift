import SwiftUI
import DictumCore

struct SettingsView: View {
  var body: some View {
    TabView {
      GeneralSettingsTab()
        .tabItem { Label("General", systemImage: "gearshape") }
      EngineSettingsTab()
        .tabItem { Label("Speech", systemImage: "waveform") }
      AISettingsTab()
        .tabItem { Label("AI Cleanup", systemImage: "sparkles") }
      DictionarySettingsTab()
        .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
      AboutTab()
        .tabItem { Label("About", systemImage: "info.circle") }
    }
    .frame(width: 600, height: 560)
  }
}

// MARK: - General

struct GeneralSettingsTab: View {
  @EnvironmentObject var settings: AppSettings
  @EnvironmentObject var controller: DictationController
  @State private var launchAtLogin = LaunchAtLogin.isEnabled
  @State private var launchError: String?

  var body: some View {
    Form {
      Section("Dictation shortcut") {
        HotkeyPicker(title: "Hold to dictate", binding: $settings.data.dictationHotkey)
        Toggle("Double-tap locks hands-free mode (tap once more to stop)", isOn: $settings.data.tapTogglesHandsFree)
        Toggle("Cancel if another key is pressed right after the shortcut", isOn: $settings.data.cancelOnOtherKeys)
        if settings.data.dictationHotkey == .fn || (settings.data.commandModeEnabled && settings.data.commandHotkey == .fn) {
          HStack(alignment: .top) {
            Text("Using the Fn/🌐 key: in System Settings → Keyboard set “Press 🌐 key to” to “Do Nothing”, otherwise macOS Dictation or the emoji picker opens too.")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button("Open Keyboard Settings") { Permissions.open(.keyboard) }
          }
        }
        Text("Press Esc while recording to cancel.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Command mode") {
        Toggle("Enable command mode", isOn: $settings.data.commandModeEnabled)
        HotkeyPicker(title: "Hold to command", binding: $settings.data.commandHotkey)
          .disabled(!settings.data.commandModeEnabled)
        Text("Select text, hold the command key and say what to do: “make this more formal”, “translate to Spanish”, “turn this into bullet points”. With nothing selected it writes what you ask for. Needs an AI provider (AI Cleanup tab).")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Output") {
        Picker("Insert text by", selection: $settings.data.insertionMethod) {
          ForEach(InsertionMethod.allCases) { method in
            Text(method.displayName).tag(method)
          }
        }
        Toggle("Smart spacing (add a space when continuing a sentence)", isOn: $settings.data.smartSpacing)
        Toggle("Restore the clipboard after pasting", isOn: $settings.data.restoreClipboard)
        Toggle("Show the floating status pill", isOn: $settings.data.showOverlay)
        Toggle("Play start/stop sounds", isOn: $settings.data.playSounds)
      }

      Section("Startup") {
        Toggle("Launch Dictum at login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, newValue in
            do {
              try LaunchAtLogin.setEnabled(newValue)
              launchError = nil
            } catch {
              launchError = error.localizedDescription
              launchAtLogin = LaunchAtLogin.isEnabled
            }
          }
        if let launchError {
          Text(launchError).font(.caption).foregroundStyle(.red)
        }
      }

      Section("Permissions") {
        PermissionRows()
      }
    }
    .formStyle(.grouped)
  }
}

struct PermissionRows: View {
  @EnvironmentObject var controller: DictationController
  @State private var speechStatus = Permissions.speechStatus

  var body: some View {
    LabeledContent("Microphone") {
      HStack {
        StatusDot(ok: controller.microphoneGranted)
        if !controller.microphoneGranted {
          Button(Permissions.microphoneUndetermined ? "Allow" : "Open Settings") {
            if Permissions.microphoneUndetermined {
              controller.requestMicrophoneAccess()
            } else {
              Permissions.open(.microphone)
            }
          }
        }
      }
    }
    LabeledContent("Accessibility (shortcut + typing)") {
      HStack {
        StatusDot(ok: controller.accessibilityGranted)
        if !controller.accessibilityGranted {
          Button("Open Settings") {
            Permissions.promptForAccessibility()
            Permissions.open(.accessibility)
          }
        }
      }
    }
    LabeledContent("Speech recognition (Apple engine)") {
      HStack {
        StatusDot(ok: speechStatus == .authorized)
        if speechStatus == .notDetermined {
          Button("Allow") {
            Task { @MainActor in speechStatus = await Permissions.requestSpeech() }
          }
        } else if speechStatus != .authorized {
          Button("Open Settings") { Permissions.open(.speechRecognition) }
        }
      }
    }
    .onAppear { speechStatus = Permissions.speechStatus }
  }
}

struct StatusDot: View {
  let ok: Bool

  var body: some View {
    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
      .foregroundStyle(ok ? Color.green : Color.red)
  }
}

// MARK: - Speech engine

struct EngineSettingsTab: View {
  @EnvironmentObject var settings: AppSettings
  @EnvironmentObject var controller: DictationController
  @State private var cloudKey: String = Keychain.get(AppSettings.cloudKeyAccount) ?? ""
  @State private var customVariant = ""
  @State private var testResult: String?
  @State private var testing = false

  var body: some View {
    Form {
      Section("Speech engine") {
        Picker("Engine", selection: $settings.data.engine) {
          ForEach(EngineKind.allCases) { engine in
            Text(engine.displayName).tag(engine)
          }
        }
        .pickerStyle(.radioGroup)
        Text(settings.data.engine.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
        Picker("Language", selection: $settings.data.languageCode) {
          ForEach(LanguageOption.all) { option in
            Text(option.name).tag(option.code)
          }
        }
      }

      switch settings.data.engine {
      case .apple:
        Section("Apple Speech") {
          Text("Uses the same recognizer as macOS Dictation, on-device where your language supports it. “Automatic” means your system language; Apple Speech does not detect languages by itself.")
            .font(.caption)
            .foregroundStyle(.secondary)
          PermissionRows()
        }
      case .whisperKit:
        whisperSection
      case .cloud:
        cloudSection
      }
    }
    .formStyle(.grouped)
  }

  private var whisperSection: some View {
    Section("Whisper model") {
      Picker("Model", selection: $settings.data.whisperVariant) {
        ForEach(WhisperModelInfo.all) { model in
          Text("\(model.displayName) · \(model.approximateSize)").tag(model.variant)
        }
        if WhisperModelInfo.named(settings.data.whisperVariant) == nil {
          Text("Custom: \(settings.data.whisperVariant)").tag(settings.data.whisperVariant)
        }
      }
      if let info = WhisperModelInfo.named(settings.data.whisperVariant) {
        Text(info.notes).font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Button(controller.engineStatus.isEmpty ? "Download & load now" : "Working…") {
          controller.warmUpEngine()
        }
        .disabled(!controller.engineStatus.isEmpty)
        if !controller.engineStatus.isEmpty {
          ProgressView().controlSize(.small)
          Text(controller.engineStatus).font(.caption)
        }
      }
      if let error = controller.lastError, controller.engineStatus.isEmpty {
        Text(error).font(.caption).foregroundStyle(.red)
      }
      HStack {
        TextField("Other WhisperKit variant, e.g. large-v3_turbo_954MB", text: $customVariant)
        Button("Use") {
          let trimmed = customVariant.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return }
          settings.data.whisperVariant = trimmed
        }
        .disabled(customVariant.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      Text("Models download from huggingface.co/argmaxinc/whisperkit-coreml into ~/Library/Application Support/Dictum/Models. The first load compiles the model and can take a minute; after that it is instant and fully offline.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var cloudSection: some View {
    Section("Cloud provider") {
      Picker("Preset", selection: presetBinding) {
        ForEach(ProviderPreset.transcription) { preset in
          Text(preset.name).tag(preset.id)
        }
      }
      TextField("Server URL", text: $settings.data.cloudBaseURL)
      TextField("Model", text: $settings.data.cloudModel)
      SecureField("API key", text: $cloudKey)
        .onChange(of: cloudKey) { _, value in Keychain.set(value, account: AppSettings.cloudKeyAccount) }
      if let preset = ProviderPreset.transcriptionPreset(settings.data.cloudPresetID) {
        Text(preset.note).font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Button("Test connection") { testConnection() }
          .disabled(testing)
        if testing { ProgressView().controlSize(.small) }
        if let testResult { Text(testResult).font(.caption) }
      }
      Text("Audio leaves your Mac with this engine. Keys are stored in your login keychain.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var presetBinding: Binding<String> {
    Binding(
      get: { settings.data.cloudPresetID },
      set: { id in
        settings.data.cloudPresetID = id
        if let preset = ProviderPreset.transcriptionPreset(id) {
          settings.data.cloudBaseURL = preset.baseURL
          settings.data.cloudModel = preset.defaultModel
        }
      })
  }

  private func testConnection() {
    testing = true
    testResult = nil
    let baseURL = settings.data.cloudBaseURL
    let key = cloudKey
    Task { @MainActor in
      defer { testing = false }
      guard let client = OpenAICompatibleClient(baseURL: baseURL, apiKey: key) else {
        testResult = "That server URL is not valid."
        return
      }
      do {
        let models = try await client.listModels()
        testResult = "Connected · \(models.count) models available"
      } catch {
        testResult = error.localizedDescription
      }
    }
  }
}

// MARK: - AI cleanup

struct AISettingsTab: View {
  @EnvironmentObject var settings: AppSettings
  @State private var polishKey: String = Keychain.get(AppSettings.polishKeyAccount) ?? ""
  @State private var testResult: String?
  @State private var testing = false

  var body: some View {
    Form {
      Section("Instant cleanup (always on, runs locally)") {
        Toggle("Remove filler words", isOn: $settings.data.cleanup.removeFillerWords)
        TextField("Filler words", text: fillerBinding)
          .disabled(!settings.data.cleanup.removeFillerWords)
        Toggle("Collapse repeated words (“the the”)", isOn: $settings.data.cleanup.collapseRepeatedWords)
        Toggle("“New line” / “new paragraph” insert line breaks", isOn: $settings.data.cleanup.processLineCommands)
        Toggle("“Period”, “comma”, “question mark” insert punctuation", isOn: $settings.data.cleanup.processPunctuationCommands)
        Toggle("Capitalize sentences", isOn: $settings.data.cleanup.capitalizeSentences)
      }

      Section("AI polish (optional, needs a chat model)") {
        Toggle("Rewrite transcripts with an AI model", isOn: $settings.data.polishEnabled)
        Picker("Preset", selection: presetBinding) {
          ForEach(ProviderPreset.chat) { preset in
            Text(preset.name).tag(preset.id)
          }
        }
        TextField("Server URL", text: $settings.data.polishBaseURL)
        TextField("Model", text: $settings.data.polishModel)
        SecureField("API key (leave empty for local servers)", text: $polishKey)
          .onChange(of: polishKey) { _, value in Keychain.set(value, account: AppSettings.polishKeyAccount) }
        if let preset = ProviderPreset.chatPreset(settings.data.polishPresetID) {
          Text(preset.note).font(.caption).foregroundStyle(.secondary)
        }
        Picker("Style", selection: $settings.data.polishStyle) {
          ForEach(PolishStyle.allCases) { style in
            Text(style.displayName).tag(style)
          }
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("Extra instructions")
          TextEditor(text: $settings.data.polishCustomInstructions)
            .font(.body)
            .frame(height: 70)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.3)))
          Text("Example: “Always sign emails with ‘Cheers, Sam’. Keep Slack messages under three sentences.”")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        HStack {
          Button("Test connection") { testConnection() }
            .disabled(testing)
          if testing { ProgressView().controlSize(.small) }
          if let testResult { Text(testResult).font(.caption) }
        }
        Text("The same provider powers command mode. Fully local options: Ollama or LM Studio.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private var fillerBinding: Binding<String> {
    Binding(
      get: { settings.data.cleanup.fillerWords.joined(separator: ", ") },
      set: { text in
        settings.data.cleanup.fillerWords = text
          .split(separator: ",")
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      })
  }

  private var presetBinding: Binding<String> {
    Binding(
      get: { settings.data.polishPresetID },
      set: { id in
        settings.data.polishPresetID = id
        if let preset = ProviderPreset.chatPreset(id), id != "custom" {
          settings.data.polishBaseURL = preset.baseURL
          settings.data.polishModel = preset.defaultModel
        }
      })
  }

  private func testConnection() {
    testing = true
    testResult = nil
    let baseURL = settings.data.polishBaseURL
    let model = settings.data.polishModel
    let key = polishKey
    Task { @MainActor in
      defer { testing = false }
      guard let polisher = Polisher(baseURL: baseURL, apiKey: key, model: model) else {
        testResult = "Enter a valid server URL and a model name."
        return
      }
      do {
        let reply = try await polisher.polish("um so this is a test of the the cleanup", style: .verbatim,
                                              appName: nil, customInstructions: "", vocabulary: [])
        testResult = "Works · “\(reply)”"
      } catch {
        testResult = error.localizedDescription
      }
    }
  }
}

// MARK: - Dictionary

struct DictionarySettingsTab: View {
  @EnvironmentObject var settings: AppSettings

  var body: some View {
    Form {
      Section {
        Text("Teach Dictum your names and terms. “Spoken” is what the engine tends to hear, “Written” is what should be typed. The written forms are also sent to the speech engine as vocabulary hints.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Section("Replacements") {
        ForEach($settings.data.dictionary) { $entry in
          HStack {
            TextField("Spoken, e.g. super base", text: $entry.spoken)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            TextField("Written, e.g. Supabase", text: $entry.written)
            Button {
              settings.data.dictionary.removeAll { $0.id == entry.id }
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
          }
        }
        Button {
          settings.data.dictionary.append(DictionaryEntry(spoken: "", written: ""))
        } label: {
          Label("Add entry", systemImage: "plus")
        }
      }
      Section("Extra vocabulary") {
        TextField("Names, products, jargon (comma separated)", text: $settings.data.extraVocabulary, axis: .vertical)
          .lineLimit(2...6)
        Text("Whisper receives these as a prompt, Apple Speech as contextual strings, cloud APIs as the prompt field.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}

// MARK: - About

struct AboutTab: View {
  @EnvironmentObject var settings: AppSettings
  @EnvironmentObject var controller: DictationController
  @EnvironmentObject var history: HistoryStore

  var body: some View {
    Form {
      Section {
        LabeledContent("Dictum", value: "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
        Text("Free, open-source voice dictation for macOS. Hold a key, talk, release: the text appears wherever your cursor is.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Section("Your stats") {
        let stats = history.stats
        LabeledContent("Dictations", value: "\(stats.entries)")
        LabeledContent("Words dictated", value: "\(stats.words)")
        LabeledContent("Speaking speed", value: stats.wordsPerMinute > 0 ? "\(Int(stats.wordsPerMinute)) words/min" : "–")
        LabeledContent("Typing time saved", value: "\(Int(stats.estimatedMinutesSaved)) min")
        Button("Open History") { WindowManager.shared.showHistory(history: history) }
      }
      Section("Setup") {
        Button("Show setup & permissions again") {
          WindowManager.shared.showOnboarding(controller: controller, settings: settings)
        }
        Button("Reset all settings", role: .destructive) {
          settings.data = SettingsData()
        }
      }
    }
    .formStyle(.grouped)
  }
}
