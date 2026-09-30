import AppKit
import Combine
import Foundation
import DictumCore

// View-local state lives in these small objects instead of SwiftUI's @State. Recent macOS SDKs
// implement @State as a compiler macro whose plugin ships only with the full Xcode, so keeping
// @State out of the app lets it build with just the Command Line Tools.

/// State for the Settings window.
@MainActor
final class SettingsViewState: ObservableObject {
  let settings: AppSettings

  @Published var cloudKey: String {
    didSet { if cloudKey != oldValue { Keychain.set(cloudKey, account: KeychainAccount.cloudTranscription) } }
  }
  @Published var polishKey: String {
    didSet { if polishKey != oldValue { Keychain.set(polishKey, account: KeychainAccount.polish) } }
  }
  /// Comma-separated filler words, kept exactly as typed so commas and spaces survive editing.
  @Published var fillerText: String {
    didSet { settings.data.cleanup.fillerWords = SettingsViewState.words(from: fillerText) }
  }
  @Published var launchAtLogin: Bool {
    didSet {
      guard launchAtLogin != oldValue, !isRevertingLaunch else { return }
      applyLaunchAtLogin(launchAtLogin, previous: oldValue)
    }
  }
  @Published var launchError: String?
  @Published var customVariant = ""
  @Published var cloudTestResult: String?
  @Published var polishTestResult: String?
  @Published var isTesting = false

  private var isRevertingLaunch = false

  init(settings: AppSettings) {
    self.settings = settings
    cloudKey = Keychain.get(KeychainAccount.cloudTranscription) ?? ""
    polishKey = Keychain.get(KeychainAccount.polish) ?? ""
    fillerText = settings.data.cleanup.fillerWords.joined(separator: ", ")
    launchAtLogin = LaunchAtLogin.isEnabled
  }

  func useCustomVariant() {
    let trimmed = customVariant.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    settings.data.whisperVariant = trimmed
  }

  func testCloud() {
    let baseURL = settings.data.cloudBaseURL
    let key = cloudKey
    isTesting = true
    cloudTestResult = nil
    Task { [weak self] in
      let message = await ConnectionTester.listModels(baseURL: baseURL, apiKey: key)
      self?.cloudTestResult = message
      self?.isTesting = false
    }
  }

  func testPolish() {
    let baseURL = settings.data.polishBaseURL
    let model = settings.data.polishModel
    let key = polishKey
    isTesting = true
    polishTestResult = nil
    Task { [weak self] in
      let message = await ConnectionTester.polish(baseURL: baseURL, apiKey: key, model: model)
      self?.polishTestResult = message
      self?.isTesting = false
    }
  }

  private func applyLaunchAtLogin(_ enabled: Bool, previous: Bool) {
    do {
      try LaunchAtLogin.setEnabled(enabled)
      launchError = nil
    } catch {
      launchError = error.localizedDescription
      isRevertingLaunch = true
      launchAtLogin = previous
      isRevertingLaunch = false
    }
  }

  static func words(from text: String) -> [String] {
    text.split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}

/// State for the History window.
@MainActor
final class HistoryViewState: ObservableObject {
  @Published var search = ""
  @Published var copiedID: UUID?

  func copyToClipboard(_ entry: HistoryEntry) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(entry.finalText, forType: .string)
    let id = entry.id
    copiedID = id
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      guard let self, self.copiedID == id else { return }
      self.copiedID = nil
    }
  }
}

/// Records a new global shortcut. Only one picker records at a time; `activeID` names it.
@MainActor
final class ShortcutRecorder: ObservableObject {
  @Published private(set) var activeID: String?

  /// Told true while recording so the global hotkeys don't fire during capture.
  var onRecordingChange: ((Bool) -> Void)?

  private var monitor: Any?
  private var pendingModifier: UInt16?
  private var onCapture: ((HotkeyBinding) -> Void)?

  func toggle(_ id: String, onCapture: @escaping (HotkeyBinding) -> Void) {
    if activeID == id {
      stop()
    } else {
      start(id, onCapture: onCapture)
    }
  }

  func start(_ id: String, onCapture: @escaping (HotkeyBinding) -> Void) {
    stop()
    activeID = id
    self.onCapture = onCapture
    onRecordingChange?(true)
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.handle(event)
      }
      return nil
    }
  }

  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    let wasActive = activeID != nil
    monitor = nil
    activeID = nil
    onCapture = nil
    pendingModifier = nil
    if wasActive { onRecordingChange?(false) }
  }

  /// A lone modifier (Fn, Right ⌥ …) is accepted when released without any other key; a key with
  /// modifiers is accepted on key down. Esc cancels.
  private func handle(_ event: NSEvent) {
    let flags = ShortcutRecorder.modifierMask(from: event.modifierFlags)
    switch event.type {
    case .keyDown:
      pendingModifier = nil
      if event.keyCode == 53 {
        stop()
        return
      }
      guard flags != 0 else { return } // A plain key would make typing impossible.
      capture(HotkeyBinding(keyCode: event.keyCode, modifiers: flags, isModifierOnly: false))
    case .flagsChanged:
      guard let flag = HotkeyBinding.modifierFlag(forKeyCode: event.keyCode) else { return }
      if flags & flag != 0 {
        pendingModifier = event.keyCode
      } else if pendingModifier == event.keyCode {
        capture(HotkeyBinding(keyCode: event.keyCode, modifiers: flag, isModifierOnly: true))
      }
    default:
      break
    }
  }

  private func capture(_ binding: HotkeyBinding) {
    let callback = onCapture
    stop()
    callback?(binding)
  }

  static func modifierMask(from flags: NSEvent.ModifierFlags) -> UInt64 {
    var mask: UInt64 = 0
    if flags.contains(.shift) { mask |= ModifierMask.shift }
    if flags.contains(.control) { mask |= ModifierMask.control }
    if flags.contains(.option) { mask |= ModifierMask.option }
    if flags.contains(.command) { mask |= ModifierMask.command }
    if flags.contains(.function) { mask |= ModifierMask.fn }
    return mask
  }
}

/// "Test connection" helpers for the Settings window.
enum ConnectionTester {
  static func listModels(baseURL: String, apiKey: String) async -> String {
    guard let client = OpenAICompatibleClient(baseURL: baseURL, apiKey: apiKey) else {
      return "That server URL is not valid."
    }
    do {
      let models = try await client.listModels()
      return "Connected · \(models.count) models available"
    } catch {
      return error.localizedDescription
    }
  }

  static func polish(baseURL: String, apiKey: String, model: String) async -> String {
    guard let polisher = Polisher(baseURL: baseURL, apiKey: apiKey, model: model) else {
      return "Enter a valid server URL and a model name."
    }
    do {
      let reply = try await polisher.polish("um so this is a test of the the cleanup", style: .verbatim,
                                            appName: nil, customInstructions: "", vocabulary: [])
      return "Works · “\(reply)”"
    } catch {
      return error.localizedDescription
    }
  }
}
