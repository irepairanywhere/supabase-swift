import Combine
import Foundation
import DictumCore

/// Speech engines available on iPhone. On-device Whisper is not offered here: keyboard extensions
/// are limited to roughly 60 MB of memory, which is less than the smallest Whisper model.
enum MobileEngine: String, Codable, CaseIterable, Identifiable {
  case apple
  case cloud

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .apple: return "Apple Speech (on-device)"
    case .cloud: return "Cloud API (Groq, OpenAI, custom)"
    }
  }

  var summary: String {
    switch self {
    case .apple: return "Free, private, works offline for most languages. Live preview while you speak."
    case .cloud: return "Most accurate. Audio is sent to the provider you configure; Groq has a free tier."
    }
  }
}

/// Everything the user can configure, shared between the app and the keyboard through the
/// App Group. Decoding is lenient so new fields never wipe existing settings.
struct MobileSettings: Codable, Equatable {
  var engine: MobileEngine = .apple
  var languageCode: String = "auto"

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

  var autoInsertSpace: Bool = true
  var hapticsEnabled: Bool = true
  /// Set by the keyboard the first time it runs with Full Access, so the app can show a checkmark.
  var keyboardHasHadFullAccess: Bool = false
  var hasCompletedSetup: Bool = false

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = MobileSettings()
    engine = c.decode(.engine, default: d.engine)
    languageCode = c.decode(.languageCode, default: d.languageCode)
    cloudPresetID = c.decode(.cloudPresetID, default: d.cloudPresetID)
    cloudBaseURL = c.decode(.cloudBaseURL, default: d.cloudBaseURL)
    cloudModel = c.decode(.cloudModel, default: d.cloudModel)
    cleanup = c.decode(.cleanup, default: d.cleanup)
    dictionary = c.decode(.dictionary, default: d.dictionary)
    extraVocabulary = c.decode(.extraVocabulary, default: d.extraVocabulary)
    polishEnabled = c.decode(.polishEnabled, default: d.polishEnabled)
    polishPresetID = c.decode(.polishPresetID, default: d.polishPresetID)
    polishBaseURL = c.decode(.polishBaseURL, default: d.polishBaseURL)
    polishModel = c.decode(.polishModel, default: d.polishModel)
    polishStyle = c.decode(.polishStyle, default: d.polishStyle)
    polishCustomInstructions = c.decode(.polishCustomInstructions, default: d.polishCustomInstructions)
    autoInsertSpace = c.decode(.autoInsertSpace, default: d.autoInsertSpace)
    hapticsEnabled = c.decode(.hapticsEnabled, default: d.hapticsEnabled)
    keyboardHasHadFullAccess = c.decode(.keyboardHasHadFullAccess, default: d.keyboardHasHadFullAccess)
    hasCompletedSetup = c.decode(.hasCompletedSetup, default: d.hasCompletedSetup)
  }

  var effectiveLanguageCode: String? { languageCode == "auto" ? nil : languageCode }

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

  /// True when a chat endpoint and model are filled in (the key is optional for local servers).
  var polishConfigured: Bool { polisher(apiKey: nil) != nil }

  func polisher(apiKey: String?) -> Polisher? {
    Polisher(baseURL: polishBaseURL, apiKey: apiKey, model: polishModel)
  }
}

/// App Group storage shared by the app and the keyboard extension.
enum SharedStorage {
  static let appGroup = "group.app.dictum.mobile"
  static let settingsKey = "settings.v1"

  static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

  static var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
  }

  static func loadSettings() -> MobileSettings {
    guard let data = defaults.data(forKey: settingsKey),
          let settings = try? JSONDecoder().decode(MobileSettings.self, from: data) else { return MobileSettings() }
    return settings
  }

  static func save(_ settings: MobileSettings) {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    defaults.set(data, forKey: settingsKey)
  }
}

@MainActor
final class MobileSettingsStore: ObservableObject {
  @Published var settings: MobileSettings {
    didSet { SharedStorage.save(settings) }
  }

  init() {
    settings = SharedStorage.loadSettings()
  }

  /// Picks up changes the keyboard wrote (for example the Full Access flag).
  func reload() {
    let fresh = SharedStorage.loadSettings()
    if fresh != settings { settings = fresh }
  }
}
