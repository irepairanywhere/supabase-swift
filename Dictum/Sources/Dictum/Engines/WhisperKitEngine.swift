import Foundation
import WhisperKit
import DictumCore

/// On-device Whisper via WhisperKit (CoreML). Models are downloaded once into
/// ~/Library/Application Support/Dictum/Models and then run fully offline.
final class WhisperKitEngine: TranscriptionEngine {
  let kind: EngineKind = .whisperKit

  private(set) var variant: String
  private let modelsDirectory: URL
  private let folderStore: ModelFolderStore

  private var whisperKit: WhisperKit?
  private var loadedVariant: String?
  private var preparation: Task<Void, Error>?

  init(variant: String, modelsDirectory: URL, folderStore: ModelFolderStore = ModelFolderStore()) {
    self.variant = variant
    self.modelsDirectory = modelsDirectory
    self.folderStore = folderStore
  }

  var isLoaded: Bool { whisperKit != nil && loadedVariant == variant }

  func isDownloaded(_ variant: String) -> Bool {
    guard let path = folderStore.folder(for: variant) else { return false }
    return FileManager.default.fileExists(atPath: path)
  }

  func setVariant(_ newVariant: String) {
    guard newVariant != variant else { return }
    variant = newVariant
    preparation?.cancel()
    preparation = nil
    whisperKit = nil
    loadedVariant = nil
  }

  func prepare(status: @escaping @Sendable (String) -> Void) async throws {
    if isLoaded { return }
    if let preparation {
      try await preparation.value
      return
    }
    let variant = self.variant
    let task = Task<Void, Error> { [self] in
      let folder = try await ensureDownloaded(variant: variant, status: status)
      try Task.checkCancellation()
      status("Loading \(Self.displayName(variant))…")
      let config = WhisperKitConfig(modelFolder: folder.path,
                                    verbose: false,
                                    logLevel: .none,
                                    prewarm: true,
                                    load: true,
                                    download: false)
      let kit = try await WhisperKit(config)
      try Task.checkCancellation()
      self.whisperKit = kit
      self.loadedVariant = variant
      status("")
    }
    preparation = task
    defer { if preparation == task { preparation = nil } }
    do {
      try await task.value
    } catch {
      status("")
      if error is CancellationError { throw error }
      throw TranscriptionError.unavailable("Whisper model failed to load: \(error.localizedDescription)")
    }
  }

  private func ensureDownloaded(variant: String, status: @escaping @Sendable (String) -> Void) async throws -> URL {
    if let saved = folderStore.folder(for: variant), FileManager.default.fileExists(atPath: saved) {
      return URL(fileURLWithPath: saved)
    }
    let name = Self.displayName(variant)
    status("Downloading \(name)…")
    let folder = try await WhisperKit.download(variant: variant,
                                               downloadBase: modelsDirectory,
                                               useBackgroundSession: false,
                                               progressCallback: { progress in
                                                 let percent = Int(progress.fractionCompleted * 100)
                                                 status("Downloading \(name) \(percent)%")
                                               })
    folderStore.setFolder(folder.path, for: variant)
    return folder
  }

  func transcribe(_ request: TranscriptionRequest) async throws -> String {
    try await prepare(status: { _ in })
    guard let kit = whisperKit else { throw TranscriptionError.unavailable("Whisper model is not loaded yet.") }

    var options = DecodingOptions(task: .transcribe,
                                  language: request.languageCode,
                                  temperature: 0,
                                  usePrefillPrompt: true,
                                  detectLanguage: request.languageCode == nil,
                                  skipSpecialTokens: true,
                                  withoutTimestamps: true,
                                  wordTimestamps: false,
                                  suppressBlank: true,
                                  chunkingStrategy: .vad)

    // Bias the decoder towards the user's vocabulary by feeding it as prompt context.
    if !request.vocabulary.isEmpty, let tokenizer = kit.tokenizer {
      let hint = " " + request.vocabulary.joined(separator: ", ")
      let tokens = tokenizer.encode(text: hint).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
      if !tokens.isEmpty { options.promptTokens = Array(tokens.prefix(200)) }
    }

    let results: [TranscriptionResult]
    do {
      results = try await kit.transcribe(audioArray: request.samples, decodeOptions: options)
    } catch {
      throw TranscriptionError.failed("Whisper failed: \(error.localizedDescription)")
    }
    return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func displayName(_ variant: String) -> String {
    WhisperModelInfo.named(variant)?.displayName ?? variant
  }
}

/// Remembers where WhisperKit put each downloaded model. Safe to call from any thread.
final class ModelFolderStore: @unchecked Sendable {
  private let key = "app.dictum.whisperModelFolders"
  private let lock = NSLock()
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func folder(for variant: String) -> String? {
    lock.lock(); defer { lock.unlock() }
    return (defaults.dictionary(forKey: key) as? [String: String])?[variant]
  }

  func setFolder(_ path: String, for variant: String) {
    lock.lock(); defer { lock.unlock() }
    var map = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
    map[variant] = path
    defaults.set(map, forKey: key)
  }
}
