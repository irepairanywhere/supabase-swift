import Combine
import Foundation
import MouthfulCore

/// Dictation history in the App Group container so the keyboard can append and the app can read.
@MainActor
final class SharedHistoryStore: ObservableObject {
  @Published private(set) var entries: [HistoryEntry] = []

  private let fileURL: URL?
  private let maximumEntries = 500

  init() {
    fileURL = SharedStorage.containerURL?.appendingPathComponent("history.json")
    load()
  }

  var stats: DictationStats { DictationStats(entries: entries) }

  func load() {
    guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
  }

  func add(_ entry: HistoryEntry) {
    load()
    entries.insert(entry, at: 0)
    if entries.count > maximumEntries { entries.removeLast(entries.count - maximumEntries) }
    save()
  }

  func remove(ids: Set<UUID>) {
    entries.removeAll { ids.contains($0.id) }
    save()
  }

  func clear() {
    entries.removeAll()
    save()
  }

  private func save() {
    guard let fileURL else { return }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(entries) else { return }
    try? data.write(to: fileURL, options: [.atomic])
  }
}
