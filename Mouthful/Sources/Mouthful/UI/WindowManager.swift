import AppKit
import SwiftUI

/// Owns the app's ordinary windows (settings, onboarding, history). A menu bar app has no main
/// window, so these are created on demand and reused while open.
@MainActor
final class WindowManager {
  static let shared = WindowManager()

  static let settingsID = "settings"
  static let onboardingID = "onboarding"
  static let historyID = "history"

  private struct Dependencies {
    let controller: DictationController
    let settings: AppSettings
    let history: HistoryStore
    let recorder: ShortcutRecorder
  }

  private var dependencies: Dependencies?
  private var windows: [String: NSWindow] = [:]
  private var closeObservers: [String: NSObjectProtocol] = [:]

  func configure(controller: DictationController, settings: AppSettings, history: HistoryStore,
                 recorder: ShortcutRecorder) {
    dependencies = Dependencies(controller: controller, settings: settings, history: history, recorder: recorder)
  }

  func showSettings() {
    guard let deps = dependencies else { return }
    let state = SettingsViewState(settings: deps.settings)
    show(id: WindowManager.settingsID, title: "Mouthful Settings") {
      SettingsView()
        .environmentObject(deps.settings)
        .environmentObject(deps.controller)
        .environmentObject(deps.history)
        .environmentObject(deps.recorder)
        .environmentObject(state)
    }
  }

  func showHistory() {
    guard let deps = dependencies else { return }
    let viewState = HistoryViewState()
    show(id: WindowManager.historyID, title: "Dictation History", initialSize: NSSize(width: 760, height: 540)) {
      HistoryView()
        .environmentObject(deps.history)
        .environmentObject(viewState)
    }
  }

  func showOnboarding() {
    guard let deps = dependencies else { return }
    show(id: WindowManager.onboardingID, title: "Welcome to Mouthful") {
      OnboardingView()
        .environmentObject(deps.controller)
        .environmentObject(deps.settings)
        .environmentObject(deps.recorder)
    }
  }

  func close(_ id: String) {
    windows[id]?.close()
  }

  static func activateApp() {
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Text fields get ⌘C / ⌘V / ⌘A only through the main menu. A menu bar app never shows its main
  /// menu, so make sure a hidden Edit menu exists; otherwise pasting an API key would not work.
  static func ensureEditMenu() {
    let mainMenu = NSApp.mainMenu ?? NSMenu(title: "Main")
    let hasPaste = mainMenu.items.contains { item in
      guard let submenu = item.submenu else { return false }
      return submenu.items.contains { $0.keyEquivalent == "v" && $0.keyEquivalentModifierMask == [.command] }
    }
    if hasPaste { return }
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(NSMenuItem.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    editItem.submenu = edit
    mainMenu.addItem(editItem)
    if NSApp.mainMenu == nil {
      NSApp.mainMenu = mainMenu
    }
  }

  private func show<Content: View>(id: String, title: String, initialSize: NSSize? = nil,
                                   @ViewBuilder content: () -> Content) {
    WindowManager.ensureEditMenu()
    if let existing = windows[id] {
      existing.makeKeyAndOrderFront(nil)
      WindowManager.activateApp()
      return
    }
    let hosting = NSHostingController(rootView: content())
    let window = NSWindow(contentViewController: hosting)
    var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
    if initialSize != nil {
      mask.insert(.resizable)
    }
    window.styleMask = mask
    window.title = title
    window.isReleasedWhenClosed = false
    if let initialSize {
      window.setContentSize(initialSize)
    }
    window.center()
    windows[id] = window
    closeObservers[id] = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { _ in
      Task { @MainActor in
        WindowManager.shared.windowWillClose(id)
      }
    }
    window.makeKeyAndOrderFront(nil)
    WindowManager.activateApp()
  }

  private func windowWillClose(_ id: String) {
    windows[id] = nil
    if let observer = closeObservers.removeValue(forKey: id) {
      NotificationCenter.default.removeObserver(observer)
    }
    if id != WindowManager.historyID {
      dependencies?.recorder.stop()
    }
  }
}
