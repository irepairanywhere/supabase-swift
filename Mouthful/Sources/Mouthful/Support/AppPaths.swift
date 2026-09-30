import Foundation

enum AppPaths {
  static let supportDirectory: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    let directory = base.appendingPathComponent("Mouthful", isDirectory: true)
    // The folder from before the rename holds downloaded models and history; keep using it.
    let legacy = base.appendingPathComponent("Dictum", isDirectory: true)
    if !FileManager.default.fileExists(atPath: directory.path),
       FileManager.default.fileExists(atPath: legacy.path) {
      try? FileManager.default.moveItem(at: legacy, to: directory)
    }
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
