import Foundation
import MouthfulCore

/// Sends a WAV clip to any OpenAI-compatible `/audio/transcriptions` endpoint.
final class CloudTranscriptionEngine: TranscriptionEngine {
  let kind: EngineKind = .cloud

  var baseURL: String
  var apiKey: String?
  var model: String

  init(baseURL: String, apiKey: String?, model: String) {
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.model = model
  }

  func prepare(status: @escaping @Sendable (String) -> Void) async throws {
    _ = try client()
  }

  func transcribe(_ request: TranscriptionRequest) async throws -> String {
    let client = try client()
    let wav = WAVEncoder.encode16BitPCM(samples: request.samples, sampleRate: request.sampleRate)
    let prompt = request.vocabulary.isEmpty ? nil : request.vocabulary.joined(separator: ", ")
    do {
      return try await client.transcribe(wavData: wav, model: model, language: request.languageCode, prompt: prompt)
    } catch let error as OpenAICompatibleError {
      throw TranscriptionError.failed("Cloud transcription failed: \(error.localizedDescription)")
    }
  }

  private func client() throws -> OpenAICompatibleClient {
    guard !model.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw TranscriptionError.unavailable("Enter a transcription model name in Settings → Speech.")
    }
    guard let client = OpenAICompatibleClient(baseURL: baseURL, apiKey: apiKey) else {
      throw TranscriptionError.unavailable("Enter a valid server URL in Settings → Speech.")
    }
    return client
  }
}
