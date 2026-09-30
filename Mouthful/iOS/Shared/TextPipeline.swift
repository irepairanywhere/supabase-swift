import Foundation
import MouthfulCore

/// Turns a raw transcript into the text that gets typed: rule-based cleanup, then optional AI polish.
enum TextPipeline {
  struct Outcome {
    var text: String
    /// Non-fatal problem worth showing (for example "AI polish failed, inserted plain text").
    var note: String?
  }

  /// Returns nil when nothing usable was heard.
  static func finalize(raw: String, settings: MobileSettings, polishAPIKey: String?, appName: String?) async -> Outcome? {
    let cleaned = TextCleaner.clean(raw, options: settings.cleanup, dictionary: settings.dictionary)
    guard !cleaned.isEmpty else { return nil }
    guard settings.polishEnabled, let polisher = settings.polisher(apiKey: polishAPIKey) else {
      return Outcome(text: cleaned, note: nil)
    }
    do {
      let polished = try await polisher.polish(cleaned, style: settings.polishStyle, appName: appName,
                                               customInstructions: settings.polishCustomInstructions,
                                               vocabulary: settings.vocabulary)
      return Outcome(text: polished, note: nil)
    } catch {
      return Outcome(text: cleaned, note: "AI polish failed, inserted the plain transcript. \(error.localizedDescription)")
    }
  }

  static func runCommand(instruction: String, selectedText: String?, settings: MobileSettings,
                         polishAPIKey: String?) async throws -> String {
    guard let polisher = settings.polisher(apiKey: polishAPIKey) else {
      throw TranscriberError.unavailable("Command mode needs an AI provider. Set one up in Mouthful → Settings.")
    }
    return try await polisher.runCommand(instruction: instruction, selectedText: selectedText, appName: nil)
  }

  /// Adds a leading space when the text continues a sentence.
  static func smartSpaced(_ text: String, before context: String?, enabled: Bool) -> String {
    guard enabled, let context, let last = context.last else { return text }
    let noSpaceAfter: Set<Character> = ["(", "[", "{", "\"", "'", "“", "‘", "/", "-", "@", "#"]
    if last.isWhitespace || last.isNewline || noSpaceAfter.contains(last) { return text }
    return " " + text
  }
}
