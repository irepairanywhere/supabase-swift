import Foundation
import DictumCore

/// The optional LLM pass: cleans transcripts and powers command mode. Any OpenAI-compatible
/// chat endpoint works (Groq, Ollama, LM Studio, OpenAI …).
struct Polisher {
  let client: OpenAICompatibleClient
  let model: String

  init?(baseURL: String, apiKey: String?, model: String) {
    let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedModel.isEmpty, let client = OpenAICompatibleClient(baseURL: baseURL, apiKey: apiKey) else { return nil }
    self.client = client
    self.model = trimmedModel
  }

  func polish(_ text: String, style: PolishStyle, appName: String?, customInstructions: String,
              vocabulary: [String]) async throws -> String {
    let system = PromptBuilder.polishSystemPrompt(style: style, appName: appName,
                                                  customInstructions: customInstructions, vocabulary: vocabulary)
    let output = try await client.chat(model: model, systemPrompt: system, userMessage: text, temperature: 0.2)
    return PromptBuilder.acceptPolishedText(original: text, polished: PromptBuilder.stripCodeFences(output))
  }

  func runCommand(instruction: String, selectedText: String?, appName: String?) async throws -> String {
    let output = try await client.chat(model: model,
                                       systemPrompt: PromptBuilder.commandSystemPrompt(appName: appName),
                                       userMessage: PromptBuilder.commandUserMessage(instruction: instruction,
                                                                                     selectedText: selectedText),
                                       temperature: 0.3)
    let result = PromptBuilder.stripCodeFences(output)
    guard !result.isEmpty else { throw OpenAICompatibleError.emptyResponse }
    return result
  }
}
