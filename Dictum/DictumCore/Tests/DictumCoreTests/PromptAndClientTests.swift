import XCTest
@testable import DictumCore

final class PromptAndClientTests: XCTestCase {
  func testPolishPromptMentionsAppStyleAndVocabulary() {
    let prompt = PromptBuilder.polishSystemPrompt(style: .auto, appName: "Slack", customInstructions: "Never use emoji.",
                                                  vocabulary: ["Supabase", "Rocket Launch Media"])
    XCTAssertTrue(prompt.contains("Slack"))
    XCTAssertTrue(prompt.contains("Supabase, Rocket Launch Media"))
    XCTAssertTrue(prompt.contains("Never use emoji."))
    XCTAssertTrue(prompt.contains("do NOT answer"))
  }

  func testCommandMessageIncludesSelection() {
    let message = PromptBuilder.commandUserMessage(instruction: "make it shorter", selectedText: "Some long text")
    XCTAssertTrue(message.hasPrefix("INSTRUCTION:\nmake it shorter"))
    XCTAssertTrue(message.contains("SELECTED TEXT:\nSome long text"))
    XCTAssertFalse(PromptBuilder.commandUserMessage(instruction: "x", selectedText: "  ").contains("SELECTED TEXT"))
  }

  func testAcceptPolishedTextRejectsRunawayOutput() {
    let original = "what is the capital of france, do you know it"
    let answered = "The capital of France is Paris. Paris has been the capital since the 10th century and is home to..." +
      String(repeating: " more text", count: 20)
    XCTAssertEqual(PromptBuilder.acceptPolishedText(original: original, polished: answered), original)
    XCTAssertEqual(PromptBuilder.acceptPolishedText(original: original, polished: "  "), original)
    XCTAssertEqual(PromptBuilder.acceptPolishedText(original: original, polished: "What is the capital of France? Do you know it?"),
                   "What is the capital of France? Do you know it?")
  }

  func testStripCodeFences() {
    XCTAssertEqual(PromptBuilder.stripCodeFences("```text\nHello there\n```"), "Hello there")
    XCTAssertEqual(PromptBuilder.stripCodeFences("```\nHello\n```"), "Hello")
    XCTAssertEqual(PromptBuilder.stripCodeFences("plain ``` inline"), "plain ``` inline")
  }

  func testClientNormalizesBaseURL() {
    let client = OpenAICompatibleClient(baseURL: " https://api.groq.com/openai/v1/ ", apiKey: " key ")
    XCTAssertEqual(client?.baseURL.absoluteString, "https://api.groq.com/openai/v1")
    XCTAssertEqual(client?.apiKey, "key")
    XCTAssertNil(OpenAICompatibleClient(baseURL: "not a url", apiKey: nil))
    XCTAssertNil(OpenAICompatibleClient(baseURL: "localhost:1234", apiKey: nil)?.apiKey)
  }

  func testMultipartBodyLayout() {
    let body = OpenAICompatibleClient.multipartBody(boundary: "B", fields: [("model", "whisper-1")], fileField: "file",
                                                    filename: "audio.wav", mimeType: "audio/wav", fileData: Data([1, 2, 3]))
    let text = String(decoding: body, as: UTF8.self)
    XCTAssertTrue(text.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n"))
    XCTAssertTrue(text.contains("name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n"))
    XCTAssertTrue(text.hasSuffix("\r\n--B--\r\n"))
  }

  func testParsesResponses() throws {
    XCTAssertEqual(try OpenAICompatibleClient.parseTranscription(Data("{\"text\":\"hello\"}".utf8)), "hello")
    XCTAssertEqual(try OpenAICompatibleClient.parseTranscription(Data("plain text".utf8)), "plain text")
    let chat = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Cleaned.\"}}]}"
    XCTAssertEqual(try OpenAICompatibleClient.parseChat(Data(chat.utf8)), "Cleaned.")
    XCTAssertThrowsError(try OpenAICompatibleClient.parseChat(Data("{\"choices\":[]}".utf8)))
    XCTAssertEqual(OpenAICompatibleClient.errorMessage(from: Data("{\"error\":{\"message\":\"bad key\"}}".utf8)), "bad key")
  }

  func testChatRequestBody() throws {
    let data = try OpenAICompatibleClient.chatRequestBody(model: "m", systemPrompt: "s", userMessage: "u", temperature: 0.1)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(json["model"] as? String, "m")
    let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
    XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
  }
}

final class PolisherAndLenientDecodingTests: XCTestCase {
  func testPolisherRequiresURLAndModel() {
    XCTAssertNil(Polisher(baseURL: "not a url", apiKey: nil, model: "m"))
    XCTAssertNil(Polisher(baseURL: "http://localhost:11434/v1", apiKey: nil, model: "  "))
    XCTAssertEqual(Polisher(baseURL: "http://localhost:11434/v1", apiKey: nil, model: " llama3.2 ")?.model, "llama3.2")
  }

  func testLenientDecodingFallsBackToDefaults() throws {
    struct Prefs: Decodable, Equatable {
      var a: Int
      var b: String
      init(a: Int, b: String) { self.a = a; self.b = b }
      init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        a = c.decode(.a, default: 7)
        b = c.decode(.b, default: "x")
      }
    }
    let decoded = try JSONDecoder().decode(Prefs.self, from: Data("{\"a\":\"oops\"}".utf8))
    XCTAssertEqual(decoded, Prefs(a: 7, b: "x"))
    let full = try JSONDecoder().decode(Prefs.self, from: Data("{\"a\":1,\"b\":\"y\"}".utf8))
    XCTAssertEqual(full, Prefs(a: 1, b: "y"))
  }
}
