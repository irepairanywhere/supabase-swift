import Foundation

enum AppPaths {
  static let supportDirectory: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    let directory = base.appendingPathComponent("Dictum", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }()

  static var modelsDirectory: URL {
    let directory = supportDirectory.appendingPathComponent("Models", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static var historyFile: URL { supportDirectory.appendingPathComponent("history.json") }
}
