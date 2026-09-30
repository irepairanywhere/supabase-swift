import Combine
import Foundation
import DictumCore

/// Everything the user can configure. Decoding is lenient so adding a field in a future version
/// never wipes existing settings.
struct SettingsData: Codable, Equatable {
  var engine: EngineKind = .apple
  var languageCode: String = "auto"

  var dictationHotkey: HotkeyBinding = .rightOption
  var commandModeEnabled: Bool = true
  var commandHotkey: HotkeyBinding = .rightCommand
  var tapTogglesHandsFree: Bool = true
  var cancelOnOtherKeys: Bool = true
  var minimumRecordingSeconds: Double = 0.4

  var whisperVariant: String = WhisperModelInfo.recommended.variant

  var cloudPresetID: String = "groq"
  var cloudBaseURL: String = ProviderPreset.transcriptionPreset("groq")?.baseURL ?? ""
  var cloudModel: String = ProviderPreset.transcriptionPreset("groq")?.defaultModel ?? ""

  var cleanup: CleanupOptions = CleanupOptions()
  var dictionary: [DictionaryEntry] = []
  var extraVocabulary: String = ""

  var polishEnabled: Bool = false
  var polishPresetID: String = "groq"
  var polishBaseURL: String = ProviderPreset.chatPreset("groq")?.baseURL ?? ""
  var polishModel: String = ProviderPreset.chatPreset("groq")?.defaultModel ?? ""
  var polishStyle: PolishStyle = .auto
  var polishCustomInstructions: String = ""

  var insertionMethod: InsertionMethod = .paste
  var smartSpacing: Bool = true
  var restoreClipboard: Bool = true
  var playSounds: Bool = true
  var showOverlay: Bool = true
  var hasCompletedOnboarding: Bool = false

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = SettingsData()
    engine = (try? c.decodeIfPresent(EngineKind.self, forKey: .engine)) ?? d.engine
    languageCode = (try? c.decodeIfPresent(String.self, forKey: .languageCode)) ?? d.languageCode
    dictationHotkey = (try? c.decodeIfPresent(HotkeyBinding.self, forKey: .dictationHotkey)) ?? d.dictationHotkey
    commandModeEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .commandModeEnabled)) ?? d.commandModeEnabled
    commandHotkey = (try? c.decodeIfPresent(HotkeyBinding.self, forKey: .commandHotkey)) ?? d.commandHotkey
    tapTogglesHandsFree = (try? c.decodeIfPresent(Bool.self, forKey: .tapTogglesHandsFree)) ?? d.tapTogglesHandsFree
    cancelOnOtherKeys = (try? c.decodeIfPresent(Bool.self, forKey: .cancelOnOtherKeys)) ?? d.cancelOnOtherKeys
    minimumRecordingSeconds = (try? c.decodeIfPresent(Double.self, forKey: .minimumRecordingSeconds)) ?? d.minimumRecordingSeconds
    whisperVariant = (try? c.decodeIfPresent(String.self, forKey: .whisperVariant)) ?? d.whisperVariant
    cloudPresetID = (try? c.decodeIfPresent(String.self, forKey: .cloudPresetID)) ?? d.cloudPresetID
    cloudBaseURL = (try? c.decodeIfPresent(String.self, forKey: .cloudBaseURL)) ?? d.cloudBaseURL
    cloudModel = (try? c.decodeIfPresent(String.self, forKey: .cloudModel)) ?? d.cloudModel
    cleanup = (try? c.decodeIfPresent(CleanupOptions.self, forKey: .cleanup)) ?? d.cleanup
    dictionary = (try? c.decodeIfPresent([DictionaryEntry].self, forKey: .dictionary)) ?? d.dictionary
    extraVocabulary = (try? c.decodeIfPresent(String.self, forKey: .extraVocabulary)) ?? d.extraVocabulary
    polishEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .polishEnabled)) ?? d.polishEnabled
    polishPresetID = (try? c.decodeIfPresent(String.self, forKey: .polishPresetID)) ?? d.polishPresetID
    polishBaseURL = (try? c.decodeIfPresent(String.self, forKey: .polishBaseURL)) ?? d.polishBaseURL
    polishModel = (try? c.decodeIfPresent(String.self, forKey: .polishModel)) ?? d.polishModel
    polishStyle = (try? c.decodeIfPresent(PolishStyle.self, forKey: .polishStyle)) ?? d.polishStyle
    polishCustomInstructions = (try? c.decodeIfPresent(String.self, forKey: .polishCustomInstructions)) ?? d.polishCustomInstructions
    insertionMethod = (try? c.decodeIfPresent(InsertionMethod.self, forKey: .insertionMethod)) ?? d.insertionMethod
    smartSpacing = (try? c.decodeIfPresent(Bool.self, forKey: .smartSpacing)) ?? d.smartSpacing
    restoreClipboard = (try? c.decodeIfPresent(Bool.self, forKey: .restoreClipboard)) ?? d.restoreClipboard
    playSounds = (try? c.decodeIfPresent(Bool.self, forKey: .playSounds)) ?? d.playSounds
    showOverlay = (try? c.decodeIfPresent(Bool.self, forKey: .showOverlay)) ?? d.showOverlay
    hasCompletedOnboarding = (try? c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)) ?? d.hasCompletedOnboarding
  }

  /// Dictionary terms plus the free-form vocabulary field, deduplicated.
  var vocabulary: [String] {
    var terms = PersonalDictionary.vocabulary(from: dictionary)
    var seen = Set(terms.map { $0.lowercased() })
    for raw in extraVocabulary.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
      let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !term.isEmpty, !seen.contains(term.lowercased()) else { continue }
      seen.insert(term.lowercased())
      terms.append(term)
    }
    return terms
  }

  var effectiveLanguageCode: String? { languageCode == "auto" ? nil : languageCode }
}

@MainActor
final class AppSettings: ObservableObject {
  private static let storageKey = "app.dictum.settings.v1"

  @Published var data: SettingsData {
    didSet { persist() }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let stored = defaults.data(forKey: Self.storageKey),
       let decoded = try? JSONDecoder().decode(SettingsData.self, from: stored) {
      data = decoded
    } else {
      data = SettingsData()
    }
  }

  private let defaults: UserDefaults

  private func persist() {
    guard let encoded = try? JSONEncoder().encode(data) else { return }
    defaults.set(encoded, forKey: Self.storageKey)
  }

  // Keys are read on demand so they never sit in memory longer than needed.
  var cloudAPIKey: String? { Keychain.get(KeychainAccount.cloudTranscription) }
  var polishAPIKey: String? { Keychain.get(KeychainAccount.polish) }
}

/// Keychain account names for the API keys.
enum KeychainAccount {
  static let cloudTranscription = "cloud-transcription-api-key"
  static let polish = "polish-api-key"
}

extension AppSettings {
  /// Picking a transcription preset also fills in its server URL and default model.
  var cloudPresetID: String {
    get { data.cloudPresetID }
    set {
      var updated = data
      updated.cloudPresetID = newValue
      if let preset = ProviderPreset.transcriptionPreset(newValue) {
        updated.cloudBaseURL = preset.baseURL
        updated.cloudModel = preset.defaultModel
      }
      data = updated
    }
  }

  /// Picking a chat preset also fills in its server URL and default model ("Custom" keeps them).
  var polishPresetID: String {
    get { data.polishPresetID }
    set {
      var updated = data
      updated.polishPresetID = newValue
      if newValue != "custom", let preset = ProviderPreset.chatPreset(newValue) {
        updated.polishBaseURL = preset.baseURL
        updated.polishModel = preset.defaultModel
      }
      data = updated
    }
  }
}
