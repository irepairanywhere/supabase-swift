import Foundation
import MouthfulCore

@MainActor
final class HistoryStore: ObservableObject {
  @Published private(set) var entries: [HistoryEntry] = []

  private let fileURL: URL
  private let maximumEntries = 1000

  init(fileURL: URL = AppPaths.historyFile) {
    self.fileURL = fileURL
    load()
  }

  var stats: DictationStats { DictationStats(entries: entries) }

  func add(_ entry: HistoryEntry) {
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

  private func load() {
    guard let data = try? Data(contentsOf: fileURL) else { return }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
  }

  private func save() {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(entries) else { return }
    try? data.write(to: fileURL, options: [.atomic])
  }
}
