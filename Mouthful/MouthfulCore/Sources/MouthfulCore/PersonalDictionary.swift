import Foundation

/// A spoken phrase and how it should be written. Leave `spoken` empty to only use `written`
/// as a vocabulary hint for the speech engine (names, product terms, jargon).
public struct DictionaryEntry: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var spoken: String
  public var written: String

  public init(id: UUID = UUID(), spoken: String, written: String) {
    self.id = id
    self.spoken = spoken
    self.written = written
  }
}

public enum PersonalDictionary {
  /// Replaces every `spoken` phrase with its `written` form, case-insensitively, on word boundaries.
  public static func apply(_ entries: [DictionaryEntry], to text: String) -> String {
    var result = text
    for entry in entries {
      let spoken = entry.spoken.trimmingCharacters(in: .whitespacesAndNewlines)
      let written = entry.written.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !spoken.isEmpty, !written.isEmpty, spoken != written else { continue }
      let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: spoken) + "(?![\\p{L}\\p{N}])"
      result = RegexHelper.replace(pattern, in: result, with: NSRegularExpression.escapedTemplate(for: written))
    }
    return result
  }

  /// Distinct `written` terms, suitable as vocabulary hints / prompt context for a speech engine.
  public static func vocabulary(from entries: [DictionaryEntry]) -> [String] {
    var seen = Set<String>()
    var terms: [String] = []
    for entry in entries {
      let term = entry.written.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !term.isEmpty, !seen.contains(term.lowercased()) else { continue }
      seen.insert(term.lowercased())
      terms.append(term)
    }
    return terms
  }
}

/// Small NSRegularExpression convenience used across the core.
enum RegexHelper {
  static func replace(_ pattern: String, in text: String, with template: String,
                      options: NSRegularExpression.Options = [.caseInsensitive]) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return re.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
  }
}
