import Foundation

/// Rule-based cleanup applied to every transcript before it is inserted. Runs in microseconds,
/// needs no network, and is what most dictations get when the optional LLM pass is off.
public struct CleanupOptions: Codable, Equatable, Sendable {
  public var removeFillerWords: Bool
  public var fillerWords: [String]
  public var collapseRepeatedWords: Bool
  /// "new line" / "new paragraph" become line breaks.
  public var processLineCommands: Bool
  /// "period", "comma", "question mark" … become punctuation. Off by default because the
  /// speech engines already punctuate and these words are often meant literally.
  public var processPunctuationCommands: Bool
  public var capitalizeSentences: Bool
  public var normalizeWhitespace: Bool

  public static let defaultFillerWords = ["um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "hmm", "mm", "mhm"]

  public init(removeFillerWords: Bool = true,
              fillerWords: [String] = CleanupOptions.defaultFillerWords,
              collapseRepeatedWords: Bool = true,
              processLineCommands: Bool = true,
              processPunctuationCommands: Bool = false,
              capitalizeSentences: Bool = true,
              normalizeWhitespace: Bool = true) {
    self.removeFillerWords = removeFillerWords
    self.fillerWords = fillerWords
    self.collapseRepeatedWords = collapseRepeatedWords
    self.processLineCommands = processLineCommands
    self.processPunctuationCommands = processPunctuationCommands
    self.capitalizeSentences = capitalizeSentences
    self.normalizeWhitespace = normalizeWhitespace
  }
}

public enum TextCleaner {
  public static func clean(_ raw: String, options: CleanupOptions = CleanupOptions(),
                           dictionary: [DictionaryEntry] = []) -> String {
    var text = stripArtifacts(raw)
    text = PersonalDictionary.apply(dictionary, to: text)
    if options.removeFillerWords { text = removeFillers(text, fillers: options.fillerWords) }
    if options.collapseRepeatedWords { text = collapseRepeats(text) }
    if options.processLineCommands { text = applyLineCommands(text) }
    if options.processPunctuationCommands { text = applyPunctuationCommands(text) }
    if options.normalizeWhitespace { text = normalizeWhitespace(text) }
    if options.capitalizeSentences { text = capitalizeSentences(text) }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Steps

  /// Removes Whisper-style noise tags such as `[BLANK_AUDIO]`, `(music)` and stray special tokens.
  public static func stripArtifacts(_ text: String) -> String {
    var t = text
    let noise = "blank_audio|music|applause|laughter|laughs|inaudible|silence|noise|静音|音楽"
    t = RegexHelper.replace("\\[(?:\(noise))[^\\]]*\\]", in: t, with: "")
    t = RegexHelper.replace("\\((?:\(noise))[^)]*\\)", in: t, with: "")
    t = RegexHelper.replace("<\\|[^|]*\\|>", in: t, with: "")
    t = t.replacingOccurrences(of: "♪", with: "")
    return t
  }

  /// Removes standalone filler words while keeping the sentence punctuation sensible.
  public static func removeFillers(_ text: String, fillers: [String]) -> String {
    let cleaned = fillers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard !cleaned.isEmpty else { return text }
    let alternation = cleaned.sorted { $0.count > $1.count }
      .map { NSRegularExpression.escapedPattern(for: $0) }
      .joined(separator: "|")
    let before = "(?<![\\p{L}\\p{N}'-])"
    let after = "(?![\\p{L}\\p{N}'-])"
    let filler = "\(before)(?:\(alternation))\(after)"
    var t = text
    // "I, um, think" -> "I think"
    t = RegexHelper.replace(",\\s*\(filler)\\s*,", in: t, with: "")
    // "Um, I think" / "and um, I think" -> "I think" / "and I think"
    t = RegexHelper.replace("\(filler)\\s*,\\s*", in: t, with: "")
    // "I think um." -> "I think."
    t = RegexHelper.replace("\\s*\(filler)(?=\\s*[.!?;:])", in: t, with: "")
    // "I think um that" -> "I think that"
    t = RegexHelper.replace("\(filler)\\s*", in: t, with: "")
    return t
  }

  /// "I I think the the plan" -> "I think the plan".
  public static func collapseRepeats(_ text: String) -> String {
    RegexHelper.replace("(?<![\\p{L}\\p{N}'])([\\p{L}\\p{N}']+)(?:\\s+\\1(?![\\p{L}\\p{N}']))+", in: text, with: "$1")
  }

  public static func applyLineCommands(_ text: String) -> String {
    var t = text
    t = RegexHelper.replace("\\s*(?<![\\p{L}])new\\s+paragraph(?![\\p{L}])[,.;:!?]?\\s*", in: t, with: "\n\n")
    t = RegexHelper.replace("\\s*(?<![\\p{L}])new\\s*line(?![\\p{L}])[,.;:!?]?\\s*", in: t, with: "\n")
    return t
  }

  public static func applyPunctuationCommands(_ text: String) -> String {
    let commands: [(String, String)] = [
      ("(?:period|full stop)", "."), ("comma", ","), ("question mark", "?"),
      ("exclamation (?:mark|point)", "!"), ("semicolon", ";"), ("colon", ":"),
    ]
    var t = text
    for (spoken, symbol) in commands {
      t = RegexHelper.replace("\\s*(?<![\\p{L}])\(spoken)(?![\\p{L}])[.,]?", in: t, with: symbol)
    }
    return t
  }

  public static func normalizeWhitespace(_ text: String) -> String {
    var t = text
    t = RegexHelper.replace("[ \\t]+", in: t, with: " ", options: [])
    t = RegexHelper.replace(" +([,.;:!?])", in: t, with: "$1", options: [])
    t = RegexHelper.replace("[ \\t]*\\n[ \\t]*", in: t, with: "\n", options: [])
    t = RegexHelper.replace("\\n{3,}", in: t, with: "\n\n", options: [])
    return t
  }

  /// Uppercases the first letter of the text, of each line, and after sentence-ending punctuation
  /// followed by whitespace. Also fixes a lone lowercase "i".
  public static func capitalizeSentences(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.count)
    var capitalizeNext = true
    var previous: Character? = nil
    for ch in text {
      if capitalizeNext, ch.isLetter {
        result.append(contentsOf: String(ch).uppercased())
        capitalizeNext = false
      } else {
        result.append(ch)
      }
      if ch == "\n" {
        capitalizeNext = true
      } else if ch.isWhitespace, let p = previous, ".!?".contains(p) {
        capitalizeNext = true
      } else if !ch.isWhitespace, ch != "\"", ch != "'", ch != "(", ch != "“", ch != "‘" {
        capitalizeNext = false
      }
      previous = ch
    }
    return RegexHelper.replace("(?<![\\p{L}\\p{N}'])i(?![\\p{L}\\p{N}'])", in: result, with: "I", options: [])
  }
}
