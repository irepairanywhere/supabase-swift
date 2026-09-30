import Foundation

public enum DictationMode: String, Codable, Sendable {
  case dictation
  case command
}

/// One finished dictation, kept so users can copy text again and see their stats.
public struct HistoryEntry: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var date: Date
  public var rawText: String
  public var finalText: String
  public var appName: String?
  public var appBundleID: String?
  public var durationSeconds: Double
  public var engine: String
  public var mode: DictationMode

  public init(id: UUID = UUID(), date: Date = Date(), rawText: String, finalText: String,
              appName: String?, appBundleID: String?, durationSeconds: Double,
              engine: String, mode: DictationMode) {
    self.id = id
    self.date = date
    self.rawText = rawText
    self.finalText = finalText
    self.appName = appName
    self.appBundleID = appBundleID
    self.durationSeconds = durationSeconds
    self.engine = engine
    self.mode = mode
  }

  public var wordCount: Int {
    finalText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
  }
}

public struct DictationStats: Equatable, Sendable {
  public var entries: Int
  public var words: Int
  public var secondsSpoken: Double

  /// Speaking averages roughly 150 words per minute versus ~40 typed, so every spoken word
  /// saves about the difference. Rough, but the same maths the commercial apps show.
  public var estimatedMinutesSaved: Double {
    let typingMinutes = Double(words) / 40.0
    let speakingMinutes = secondsSpoken / 60.0
    return max(0, typingMinutes - speakingMinutes)
  }

  public var wordsPerMinute: Double {
    guard secondsSpoken > 0 else { return 0 }
    return Double(words) / (secondsSpoken / 60.0)
  }

  public init(entries: [HistoryEntry]) {
    self.entries = entries.count
    self.words = entries.reduce(0) { $0 + $1.wordCount }
    self.secondsSpoken = entries.reduce(0) { $0 + $1.durationSeconds }
  }
}
