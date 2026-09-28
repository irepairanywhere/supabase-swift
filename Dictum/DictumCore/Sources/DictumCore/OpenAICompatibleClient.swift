import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OpenAICompatibleError: Error, LocalizedError, Equatable {
  case invalidBaseURL
  case transport(String)
  case httpStatus(Int, String)
  case emptyResponse
  case decoding(String)

  public var errorDescription: String? {
    switch self {
    case .invalidBaseURL: return "The server URL is not valid."
    case .transport(let message): return message
    case .httpStatus(let code, let message):
      if code == 401 { return "The API key was rejected (401)." }
      return message.isEmpty ? "Server returned HTTP \(code)." : "HTTP \(code): \(message)"
    case .emptyResponse: return "The server returned an empty response."
    case .decoding(let message): return "Could not read the server response: \(message)"
    }
  }
}

/// Minimal client for the two OpenAI-style endpoints the app needs. Works with OpenAI, Groq,
/// Ollama, LM Studio, whisper.cpp server, and anything else that copies that API shape.
public struct OpenAICompatibleClient: Sendable {
  public let baseURL: URL
  public let apiKey: String?

  public init?(baseURL: String, apiKey: String?) {
    var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else { return nil }
    self.baseURL = url
    let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.apiKey = key.isEmpty ? nil : key
  }

  // MARK: - Endpoints

  public func transcribe(wavData: Data, model: String, language: String? = nil, prompt: String? = nil,
                         timeout: TimeInterval = 90) async throws -> String {
    var request = makeRequest(path: "audio/transcriptions", timeout: timeout)
    let boundary = "DictumBoundary-\(UUID().uuidString)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    var fields: [(String, String)] = [("model", model), ("response_format", "json"), ("temperature", "0")]
    if let language, !language.isEmpty, language != "auto" { fields.append(("language", language)) }
    if let prompt, !prompt.isEmpty { fields.append(("prompt", prompt)) }
    request.httpBody = Self.multipartBody(boundary: boundary, fields: fields, fileField: "file",
                                          filename: "audio.wav", mimeType: "audio/wav", fileData: wavData)
    let data = try await send(request)
    return try Self.parseTranscription(data)
  }

  public func chat(model: String, systemPrompt: String, userMessage: String, temperature: Double = 0.2,
                   timeout: TimeInterval = 60) async throws -> String {
    var request = makeRequest(path: "chat/completions", timeout: timeout)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try Self.chatRequestBody(model: model, systemPrompt: systemPrompt,
                                                userMessage: userMessage, temperature: temperature)
    let data = try await send(request)
    return try Self.parseChat(data)
  }

  /// `GET /models`, used by the "Test connection" buttons.
  public func listModels(timeout: TimeInterval = 20) async throws -> [String] {
    var request = makeRequest(path: "models", timeout: timeout)
    request.httpMethod = "GET"
    let data = try await send(request)
    struct ModelList: Decodable { struct Item: Decodable { let id: String }; let data: [Item] }
    do {
      return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id)
    } catch {
      throw OpenAICompatibleError.decoding(error.localizedDescription)
    }
  }

  // MARK: - Request building (pure, testable)

  public static func multipartBody(boundary: String, fields: [(String, String)], fileField: String,
                                   filename: String, mimeType: String, fileData: Data) -> Data {
    var body = Data()
    for (name, value) in fields {
      body.append(ascii: "--\(boundary)\r\n")
      body.append(ascii: "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
      body.append(ascii: "\(value)\r\n")
    }
    body.append(ascii: "--\(boundary)\r\n")
    body.append(ascii: "Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
    body.append(ascii: "Content-Type: \(mimeType)\r\n\r\n")
    body.append(fileData)
    body.append(ascii: "\r\n--\(boundary)--\r\n")
    return body
  }

  public static func chatRequestBody(model: String, systemPrompt: String, userMessage: String,
                                     temperature: Double) throws -> Data {
    struct Message: Encodable { let role: String; let content: String }
    struct Body: Encodable { let model: String; let messages: [Message]; let temperature: Double }
    let body = Body(model: model,
                    messages: [Message(role: "system", content: systemPrompt),
                               Message(role: "user", content: userMessage)],
                    temperature: temperature)
    return try JSONEncoder().encode(body)
  }

  public static func parseTranscription(_ data: Data) throws -> String {
    struct Response: Decodable { let text: String }
    do {
      return try JSONDecoder().decode(Response.self, from: data).text
    } catch {
      // Some servers answer with plain text when response_format is ignored.
      if let text = String(data: data, encoding: .utf8), !text.isEmpty, !text.hasPrefix("{") { return text }
      throw OpenAICompatibleError.decoding(error.localizedDescription)
    }
  }

  public static func parseChat(_ data: Data) throws -> String {
    struct Response: Decodable {
      struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
      }
      let choices: [Choice]
    }
    do {
      let response = try JSONDecoder().decode(Response.self, from: data)
      guard let content = response.choices.first?.message.content else { throw OpenAICompatibleError.emptyResponse }
      return content
    } catch let error as OpenAICompatibleError {
      throw error
    } catch {
      throw OpenAICompatibleError.decoding(error.localizedDescription)
    }
  }

  /// Extracts `error.message` from an error payload, or falls back to the raw body.
  public static func errorMessage(from data: Data) -> String {
    struct ErrorEnvelope: Decodable {
      struct Inner: Decodable { let message: String? }
      let error: Inner?
    }
    if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data), let message = envelope.error?.message {
      return message
    }
    let raw = String(data: data, encoding: .utf8) ?? ""
    return String(raw.prefix(300))
  }

  // MARK: - Transport

  private func makeRequest(path: String, timeout: TimeInterval) -> URLRequest {
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
    return request
  }

  private func send(_ request: URLRequest) async throws -> Data {
    let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
      let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error {
          continuation.resume(throwing: OpenAICompatibleError.transport(error.localizedDescription))
          return
        }
        guard let data, let response else {
          continuation.resume(throwing: OpenAICompatibleError.emptyResponse)
          return
        }
        continuation.resume(returning: (data, response))
      }
      task.resume()
    }
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw OpenAICompatibleError.httpStatus(http.statusCode, Self.errorMessage(from: data))
    }
    return data
  }
}
