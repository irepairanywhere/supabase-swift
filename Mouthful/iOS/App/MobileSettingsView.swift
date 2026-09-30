import SwiftUI
import MouthfulCore

struct MobileSettingsView: View {
  @EnvironmentObject var store: MobileSettingsStore
  @State private var cloudKey: String = SharedKeychain.get(SharedKeychain.cloudKeyAccount) ?? ""
  @State private var polishKey: String = SharedKeychain.get(SharedKeychain.polishKeyAccount) ?? ""
  @State private var cloudTest: String?
  @State private var polishTest: String?
  @State private var testing = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Engine", selection: $store.settings.engine) {
            ForEach(MobileEngine.allCases) { engine in
              Text(engine.displayName).tag(engine)
            }
          }
          Text(store.settings.engine.summary).font(.footnote).foregroundStyle(.secondary)
          Picker("Language", selection: $store.settings.languageCode) {
            ForEach(LanguageOption.all) { option in
              Text(option.name).tag(option.code)
            }
          }
        } header: {
          Text("Speech engine")
        }

        if store.settings.engine == .cloud {
          Section("Cloud provider") {
            Picker("Preset", selection: cloudPresetBinding) {
              ForEach(ProviderPreset.transcription) { preset in
                Text(preset.name).tag(preset.id)
              }
            }
            TextField("Server URL", text: $store.settings.cloudBaseURL)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .keyboardType(.URL)
            TextField("Model", text: $store.settings.cloudModel)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
            SecureField("API key", text: $cloudKey)
              .onChange(of: cloudKey) { _, value in SharedKeychain.set(value, account: SharedKeychain.cloudKeyAccount) }
            if let preset = ProviderPreset.transcriptionPreset(store.settings.cloudPresetID) {
              Text(preset.note).font(.footnote).foregroundStyle(.secondary)
            }
            testRow(result: cloudTest) {
              testConnection(baseURL: store.settings.cloudBaseURL, key: cloudKey) { cloudTest = $0 }
            }
          }
        }

        Section("Instant cleanup") {
          Toggle("Remove filler words", isOn: $store.settings.cleanup.removeFillerWords)
          Toggle("Collapse repeated words", isOn: $store.settings.cleanup.collapseRepeatedWords)
          Toggle("“New line” inserts a line break", isOn: $store.settings.cleanup.processLineCommands)
          Toggle("Spoken punctuation (“comma”, “period”)", isOn: $store.settings.cleanup.processPunctuationCommands)
          Toggle("Capitalize sentences", isOn: $store.settings.cleanup.capitalizeSentences)
        }

        Section {
          Toggle("Rewrite with an AI model", isOn: $store.settings.polishEnabled)
          Picker("Preset", selection: polishPresetBinding) {
            ForEach(ProviderPreset.chat) { preset in
              Text(preset.name).tag(preset.id)
            }
          }
          TextField("Server URL", text: $store.settings.polishBaseURL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
          TextField("Model", text: $store.settings.polishModel)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          SecureField("API key (empty for local servers)", text: $polishKey)
            .onChange(of: polishKey) { _, value in SharedKeychain.set(value, account: SharedKeychain.polishKeyAccount) }
          Picker("Style", selection: $store.settings.polishStyle) {
            ForEach(PolishStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          TextField("Extra instructions", text: $store.settings.polishCustomInstructions, axis: .vertical)
            .lineLimit(2...5)
          testRow(result: polishTest) {
            testConnection(baseURL: store.settings.polishBaseURL, key: polishKey) { polishTest = $0 }
          }
        } header: {
          Text("AI polish & command mode")
        } footer: {
          Text("Local servers (Ollama, LM Studio) must be reachable from your phone, e.g. http://192.168.1.20:11434/v1 on the same Wi-Fi. The keyboard's ✨ Command key appears once a provider is set.")
        }

        Section("Dictionary") {
          ForEach($store.settings.dictionary) { $entry in
            HStack {
              TextField("Spoken", text: $entry.spoken)
              Image(systemName: "arrow.right").foregroundStyle(.secondary)
              TextField("Written", text: $entry.written)
            }
          }
          .onDelete { offsets in store.settings.dictionary.remove(atOffsets: offsets) }
          Button {
            store.settings.dictionary.append(DictionaryEntry(spoken: "", written: ""))
          } label: {
            Label("Add replacement", systemImage: "plus")
          }
          TextField("Extra vocabulary (comma separated)", text: $store.settings.extraVocabulary, axis: .vertical)
            .lineLimit(1...4)
        }

        Section("Behavior") {
          Toggle("Add a space when continuing a sentence", isOn: $store.settings.autoInsertSpace)
          Toggle("Haptic feedback", isOn: $store.settings.hapticsEnabled)
        }

        Section {
          Button("Reset all settings", role: .destructive) { store.settings = MobileSettings() }
        }
      }
      .navigationTitle("Settings")
    }
  }

  private func testRow(result: String?, action: @escaping () -> Void) -> some View {
    HStack {
      Button("Test connection", action: action).disabled(testing)
      if testing { ProgressView() }
      if let result { Text(result).font(.footnote).foregroundStyle(.secondary) }
    }
  }

  private var cloudPresetBinding: Binding<String> {
    Binding(
      get: { store.settings.cloudPresetID },
      set: { id in
        store.settings.cloudPresetID = id
        if let preset = ProviderPreset.transcriptionPreset(id) {
          store.settings.cloudBaseURL = preset.baseURL
          store.settings.cloudModel = preset.defaultModel
        }
      })
  }

  private var polishPresetBinding: Binding<String> {
    Binding(
      get: { store.settings.polishPresetID },
      set: { id in
        store.settings.polishPresetID = id
        if let preset = ProviderPreset.chatPreset(id), id != "custom" {
          store.settings.polishBaseURL = preset.baseURL
          store.settings.polishModel = preset.defaultModel
        }
      })
  }

  private func testConnection(baseURL: String, key: String, completion: @escaping (String) -> Void) {
    testing = true
    Task { @MainActor in
      defer { testing = false }
      guard let client = OpenAICompatibleClient(baseURL: baseURL, apiKey: key) else {
        completion("That server URL is not valid.")
        return
      }
      do {
        let models = try await client.listModels()
        completion("Connected · \(models.count) models")
      } catch {
        completion(error.localizedDescription)
      }
    }
  }
}
