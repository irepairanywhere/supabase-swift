import Foundation

/// Which speech-to-text backend turns audio into text.
public enum EngineKind: String, Codable, CaseIterable, Identifiable, Sendable {
  /// Apple's built-in speech recognizer. Zero setup, free, mostly on-device.
  case apple
  /// WhisperKit: OpenAI Whisper models running locally on the Neural Engine/GPU.
  case whisperKit
  /// Any OpenAI-compatible `/v1/audio/transcriptions` endpoint (Groq, OpenAI, a local server).
  case cloud

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .apple: return "Apple Speech (built-in)"
    case .whisperKit: return "Whisper (on-device)"
    case .cloud: return "Cloud API (OpenAI-compatible)"
    }
  }

  public var summary: String {
    switch self {
    case .apple:
      return "Works immediately, no download. Good accuracy, uses the language you pick below."
    case .whisperKit:
      return "Best private option. Downloads a model once (75 MB – 1 GB) and runs fully offline."
    case .cloud:
      return "Fastest and most accurate. Sends audio to the provider you configure (Groq has a free tier)."
    }
  }
}

/// A Whisper model that WhisperKit can download from the `argmaxinc/whisperkit-coreml` repo.
/// `variant` is the string passed to `WhisperKit.download(variant:)`, which matches the
/// folder `*<variant>` in that repo, so every variant here resolves to exactly one folder.
public struct WhisperModelInfo: Identifiable, Hashable, Sendable {
  public let variant: String
  public let displayName: String
  public let approximateSize: String
  public let notes: String

  public var id: String { variant }

  public init(variant: String, displayName: String, approximateSize: String, notes: String) {
    self.variant = variant
    self.displayName = displayName
    self.approximateSize = approximateSize
    self.notes = notes
  }

  public static let all: [WhisperModelInfo] = [
    .init(variant: "tiny", displayName: "Tiny", approximateSize: "75 MB",
          notes: "Fastest. Fine for short notes, weak on names."),
    .init(variant: "base", displayName: "Base", approximateSize: "150 MB",
          notes: "Fast and decent. Good default for older Macs."),
    .init(variant: "small", displayName: "Small", approximateSize: "480 MB",
          notes: "Noticeably more accurate, still quick on Apple Silicon."),
    .init(variant: "distil-large-v3_594MB", displayName: "Distil Large v3 (English)", approximateSize: "590 MB",
          notes: "Near large-model accuracy for English, about 2x faster than Large."),
    .init(variant: "large-v3-v20240930_turbo_632MB", displayName: "Large v3 Turbo", approximateSize: "630 MB",
          notes: "Best balance for most people. Multilingual, fast on M1 and newer."),
    .init(variant: "large-v3-v20240930_626MB", displayName: "Large v3", approximateSize: "630 MB",
          notes: "Highest accuracy, slower than Turbo."),
  ]

  public static let recommended = all[4]

  public static func named(_ variant: String) -> WhisperModelInfo? {
    all.first { $0.variant == variant }
  }
}

/// A preset for an OpenAI-compatible HTTP provider.
public struct ProviderPreset: Identifiable, Hashable, Sendable {
  public let id: String
  public let name: String
  public let baseURL: String
  public let defaultModel: String
  public let requiresAPIKey: Bool
  public let note: String

  public init(id: String, name: String, baseURL: String, defaultModel: String, requiresAPIKey: Bool, note: String) {
    self.id = id
    self.name = name
    self.baseURL = baseURL
    self.defaultModel = defaultModel
    self.requiresAPIKey = requiresAPIKey
    self.note = note
  }

  /// Presets for `/audio/transcriptions`.
  public static let transcription: [ProviderPreset] = [
    .init(id: "groq", name: "Groq (free tier)", baseURL: "https://api.groq.com/openai/v1",
          defaultModel: "whisper-large-v3-turbo", requiresAPIKey: true,
          note: "Very fast. Free key at console.groq.com."),
    .init(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1",
          defaultModel: "whisper-1", requiresAPIKey: true,
          note: "Paid per minute. Also try gpt-4o-mini-transcribe."),
    .init(id: "local", name: "Local server", baseURL: "http://localhost:8000/v1",
          defaultModel: "whisper-1", requiresAPIKey: false,
          note: "Any OpenAI-compatible server (whisper.cpp server, faster-whisper-server, Speaches)."),
  ]

  /// Presets for `/chat/completions` (used for AI cleanup and command mode).
  public static let chat: [ProviderPreset] = [
    .init(id: "groq", name: "Groq (free tier)", baseURL: "https://api.groq.com/openai/v1",
          defaultModel: "llama-3.3-70b-versatile", requiresAPIKey: true,
          note: "Fast enough to feel instant. Free key at console.groq.com."),
    .init(id: "ollama", name: "Ollama (local, free)", baseURL: "http://localhost:11434/v1",
          defaultModel: "llama3.2", requiresAPIKey: false,
          note: "Run `ollama pull llama3.2` first. Fully offline."),
    .init(id: "lmstudio", name: "LM Studio (local, free)", baseURL: "http://localhost:1234/v1",
          defaultModel: "local-model", requiresAPIKey: false,
          note: "Start the LM Studio server and load any chat model."),
    .init(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1",
          defaultModel: "gpt-4o-mini", requiresAPIKey: true,
          note: "Paid per token, cheap for short dictations."),
    .init(id: "custom", name: "Custom", baseURL: "", defaultModel: "", requiresAPIKey: false,
          note: "Any OpenAI-compatible endpoint."),
  ]

  public static func transcriptionPreset(_ id: String) -> ProviderPreset? { transcription.first { $0.id == id } }
  public static func chatPreset(_ id: String) -> ProviderPreset? { chat.first { $0.id == id } }
}

/// How the optional LLM pass should rewrite a transcript.
public enum PolishStyle: String, Codable, CaseIterable, Identifiable, Sendable {
  case auto, casual, formal, verbatim

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .auto: return "Auto (match the app)"
    case .casual: return "Casual"
    case .formal: return "Formal"
    case .verbatim: return "Verbatim (light touch)"
    }
  }
}

/// How final text is placed into the frontmost app.
public enum InsertionMethod: String, Codable, CaseIterable, Identifiable, Sendable {
  /// Put text on the clipboard, press ⌘V, restore the clipboard. Works almost everywhere.
  case paste
  /// Ask the focused text field to insert the text through the Accessibility API. No clipboard
  /// involvement, but Electron/Chromium apps often ignore it, so it falls back to paste.
  case accessibility

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .paste: return "Paste (recommended)"
    case .accessibility: return "Accessibility API, paste as fallback"
    }
  }
}

/// Languages offered in Settings. `code` is an ISO 639-1 code, or `auto`.
public struct LanguageOption: Identifiable, Hashable, Sendable {
  public let code: String
  public let name: String
  public var id: String { code }

  public static let auto = LanguageOption(code: "auto", name: "Automatic / system language")

  public static let all: [LanguageOption] = [
    auto,
    .init(code: "en", name: "English"), .init(code: "es", name: "Spanish"), .init(code: "fr", name: "French"),
    .init(code: "de", name: "German"), .init(code: "it", name: "Italian"), .init(code: "pt", name: "Portuguese"),
    .init(code: "nl", name: "Dutch"), .init(code: "sv", name: "Swedish"), .init(code: "da", name: "Danish"),
    .init(code: "nb", name: "Norwegian"), .init(code: "fi", name: "Finnish"), .init(code: "pl", name: "Polish"),
    .init(code: "cs", name: "Czech"), .init(code: "tr", name: "Turkish"), .init(code: "ru", name: "Russian"),
    .init(code: "uk", name: "Ukrainian"), .init(code: "ar", name: "Arabic"), .init(code: "he", name: "Hebrew"),
    .init(code: "hi", name: "Hindi"), .init(code: "ja", name: "Japanese"), .init(code: "ko", name: "Korean"),
    .init(code: "zh", name: "Chinese"), .init(code: "vi", name: "Vietnamese"), .init(code: "th", name: "Thai"),
    .init(code: "id", name: "Indonesian"),
  ]
}
