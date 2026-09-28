import AVFoundation
import Foundation
import Speech
import DictumCore

/// Apple's SFSpeechRecognizer. Free, no download, on-device for most languages on macOS 14+.
final class AppleSpeechEngine: TranscriptionEngine {
  let kind: EngineKind = .apple

  func prepare(status: @escaping @Sendable (String) -> Void) async throws {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      return
    case .notDetermined:
      let result = await Permissions.requestSpeech()
      guard result == .authorized else {
        throw TranscriptionError.notAuthorized("Speech recognition permission was not granted.")
      }
    default:
      throw TranscriptionError.notAuthorized(
        "Speech recognition is disabled for Dictum. Enable it in System Settings → Privacy & Security → Speech Recognition.")
    }
  }

  func transcribe(_ request: TranscriptionRequest) async throws -> String {
    try await prepare(status: { _ in })
    let locale = Self.locale(for: request.languageCode)
    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      throw TranscriptionError.unavailable("Apple Speech does not support \(locale.identifier). Pick another language or engine.")
    }
    guard recognizer.isAvailable else {
      throw TranscriptionError.unavailable("Apple Speech is temporarily unavailable. Check your network or Dictation settings.")
    }

    let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
    recognitionRequest.shouldReportPartialResults = false
    recognitionRequest.taskHint = .dictation
    recognitionRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    recognitionRequest.addsPunctuation = true
    if !request.vocabulary.isEmpty {
      recognitionRequest.contextualStrings = Array(request.vocabulary.prefix(100))
    }

    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(request.sampleRate),
                                     channels: 1, interleaved: false) else {
      throw TranscriptionError.failed("Unsupported audio format.")
    }

    return try await withCheckedThrowingContinuation { continuation in
      let resumer = OnceResumer<String>(continuation)
      let task = recognizer.recognitionTask(with: recognitionRequest) { result, error in
        if let error {
          resumer.fail(Self.map(error))
          return
        }
        if let result, result.isFinal {
          resumer.succeed(result.bestTranscription.formattedString)
        }
      }

      // Feed the recording in one-second buffers.
      let chunk = request.sampleRate
      var index = 0
      while index < request.samples.count {
        let count = min(chunk, request.samples.count - index)
        if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
           let destination = buffer.floatChannelData?[0] {
          request.samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
              destination.update(from: base + index, count: count)
            }
          }
          buffer.frameLength = AVAudioFrameCount(count)
          recognitionRequest.append(buffer)
        }
        index += count
      }
      recognitionRequest.endAudio()

      let timeout = max(30.0, Double(request.samples.count) / Double(request.sampleRate) * 2)
      DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
        resumer.fail(TranscriptionError.failed("Apple Speech took too long. Try a shorter recording or another engine."))
        task.cancel()
      }
    }
  }

  private static func map(_ error: Error) -> TranscriptionError {
    let nsError = error as NSError
    let description = nsError.localizedDescription.lowercased()
    if description.contains("no speech") || nsError.code == 1110 {
      return .noSpeech
    }
    if nsError.code == 203 || description.contains("retry") {
      return .failed("Apple Speech could not process that clip. Please try again.")
    }
    return .failed("Apple Speech error: \(nsError.localizedDescription)")
  }

  /// Picks the best supported locale for a two-letter code, preferring the user's region.
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
