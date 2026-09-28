import Foundation
import DictumCore

struct TranscriptionRequest {
  var samples: [Float]
  var sampleRate: Int
  /// ISO 639-1 code, or nil to auto-detect / use the system language.
  var languageCode: String?
  /// Names and terms the engine should be biased towards.
  var vocabulary: [String]
}

enum TranscriptionError: LocalizedError {
  case notAuthorized(String)
  case unavailable(String)
  case noSpeech
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .notAuthorized(let message), .unavailable(let message), .failed(let message): return message
    case .noSpeech: return "No speech detected."
    }
  }
}

protocol TranscriptionEngine: AnyObject {
  var kind: EngineKind { get }
  /// Loads models / checks permissions. `status` receives human-readable progress ("Downloading 42%").
  func prepare(status: @escaping @Sendable (String) -> Void) async throws
  func transcribe(_ request: TranscriptionRequest) async throws -> String
}
