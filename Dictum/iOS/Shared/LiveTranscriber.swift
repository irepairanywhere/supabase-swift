import AVFoundation
import Combine
import Foundation
import Speech
import DictumCore

enum TranscriberError: LocalizedError {
  case audioSession(String)
  case microphone(String)
  case unavailable(String)
  case noSpeech
  case notRecording

  var errorDescription: String? {
    switch self {
    case .audioSession(let message): return "Audio session problem: \(message)"
    case .microphone(let message): return message
    case .unavailable(let message): return message
    case .noSpeech: return "No speech detected."
    case .notRecording: return "Not recording."
    }
  }
}

/// Records from the microphone and produces a transcript. With Apple Speech it streams partial
/// results while you talk; with the cloud engine it uploads a WAV when you stop.
@MainActor
final class LiveTranscriber: ObservableObject {
  enum Phase: Equatable { case idle, recording, transcribing }

  @Published private(set) var phase: Phase = .idle
  @Published private(set) var partialText = ""
  @Published private(set) var level: Float = 0
  private(set) var lastDuration: TimeInterval = 0

  private var capture: MicrophoneCapture?
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var resumer: OnceResumer<String>?
  private var latestText = ""
  private var engine: MobileEngine = .apple
  private var startedAt: Date?

  var isRecording: Bool { phase == .recording }

  func start(settings: MobileSettings) throws {
    guard phase == .idle else { return }
    engine = settings.engine
    latestText = ""
    partialText = ""
    level = 0

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
      try session.setActive(true, options: [])
    } catch {
      throw TranscriberError.audioSession(error.localizedDescription)
    }

    let capture = MicrophoneCapture()
    capture.collectsSamples = engine == .cloud
    capture.onLevel = { [weak self] value in self?.level = min(1, value * 8) }

    if engine == .apple {
      let locale = Self.locale(for: settings.effectiveLanguageCode)
      guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
        deactivateSession()
        throw TranscriberError.unavailable("Apple Speech isn't available for \(locale.identifier). Pick another language or the cloud engine.")
      }
      let request = SFSpeechAudioBufferRecognitionRequest()
      request.shouldReportPartialResults = true
      request.taskHint = .dictation
      request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
      request.addsPunctuation = true
      let vocabulary = settings.vocabulary
      if !vocabulary.isEmpty { request.contextualStrings = Array(vocabulary.prefix(100)) }
      self.recognizer = recognizer
      self.request = request
      task = recognizer.recognitionTask(with: request) { [weak self] result, error in
        Task { @MainActor [weak self] in self?.handle(result: result, error: error) }
      }
      capture.onNativeBuffer = { [weak request] buffer in request?.append(buffer) }
    }

    do {
      try capture.start()
    } catch {
      cleanup()
      throw TranscriberError.microphone(error.localizedDescription)
    }
    self.capture = capture
    startedAt = Date()
    phase = .recording
  }

  /// Stops recording and returns the raw transcript.
  func finish(settings: MobileSettings, cloudAPIKey: String?) async throws -> String {
    guard phase == .recording, let capture else { throw TranscriberError.notRecording }
    let samples = capture.stop()
    lastDuration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
    phase = .transcribing
    defer {
      cleanup()
      phase = .idle
    }

    switch engine {
    case .apple:
      request?.endAudio()
      return try await withCheckedThrowingContinuation { continuation in
        let resumer = OnceResumer<String>(continuation)
        self.resumer = resumer
        // The final result normally lands within a second; never wait longer than this.
        Task { @MainActor [weak self] in
          try? await Task.sleep(nanoseconds: 6_000_000_000)
          guard let self else { return }
          let text = self.latestText
          if text.isEmpty { resumer.fail(TranscriberError.noSpeech) } else { resumer.succeed(text) }
        }
      }
    case .cloud:
      guard let client = OpenAICompatibleClient(baseURL: settings.cloudBaseURL, apiKey: cloudAPIKey) else {
        throw TranscriberError.unavailable("Enter a valid cloud server URL in Dictum → Settings.")
      }
      guard !samples.isEmpty else { throw TranscriberError.noSpeech }
      let wav = WAVEncoder.encode16BitPCM(samples: samples, sampleRate: Int(MicrophoneCapture.targetSampleRate))
      let prompt = settings.vocabulary.isEmpty ? nil : settings.vocabulary.joined(separator: ", ")
      do {
        return try await client.transcribe(wavData: wav, model: settings.cloudModel,
                                           language: settings.effectiveLanguageCode, prompt: prompt)
      } catch {
        throw TranscriberError.unavailable(error.localizedDescription)
      }
    }
  }

  func cancel() {
    _ = capture?.stop()
    cleanup()
    partialText = ""
    level = 0
    phase = .idle
  }

  private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
    if let result {
      latestText = result.bestTranscription.formattedString
      partialText = latestText
      if result.isFinal { resumer?.succeed(latestText) }
    }
    if error != nil {
      // Silence, the one-minute server cap, or a cancelled task: keep what we heard so far.
      if latestText.isEmpty {
        resumer?.fail(TranscriberError.noSpeech)
      } else {
        resumer?.succeed(latestText)
      }
    }
  }

  private func cleanup() {
    task?.cancel()
    task = nil
    request = nil
    recognizer = nil
    resumer = nil
    capture = nil
    deactivateSession()
  }

  private func deactivateSession() {
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }

  /// Best supported locale for a two-letter code, preferring the user's region.
  static func locale(for code: String?) -> Locale {
    guard let code, code != "auto" else { return Locale.current }
    let supported = SFSpeechRecognizer.supportedLocales()
    func normalized(_ locale: Locale) -> String { locale.identifier.replacingOccurrences(of: "_", with: "-") }
    if let exact = supported.first(where: { normalized($0) == code }) { return exact }
    let candidates = supported.filter { $0.language.languageCode?.identifier == code }
    let currentRegion = Locale.current.region?.identifier
    if let regional = candidates.first(where: { $0.region?.identifier == currentRegion }) { return regional }
    let preferred = [
      "en": "en-US", "es": "es-ES", "fr": "fr-FR", "de": "de-DE", "pt": "pt-BR", "zh": "zh-CN", "it": "it-IT",
      "ja": "ja-JP", "ko": "ko-KR", "nl": "nl-NL", "sv": "sv-SE", "ru": "ru-RU", "ar": "ar-SA", "hi": "hi-IN",
      "tr": "tr-TR", "pl": "pl-PL", "da": "da-DK", "nb": "nb-NO", "fi": "fi-FI", "cs": "cs-CZ", "uk": "uk-UA",
      "he": "he-IL", "vi": "vi-VN", "th": "th-TH", "id": "id-ID",
    ]
    if let identifier = preferred[code], let match = candidates.first(where: { normalized($0) == identifier }) {
      return match
    }
    return candidates.sorted { normalized($0) < normalized($1) }.first ?? Locale(identifier: code)
  }
}
