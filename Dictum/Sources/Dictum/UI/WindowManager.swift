import AppKit
import SwiftUI

/// Owns the app's ordinary windows (onboarding, history). A menu bar app has no main window, so
/// these are created on demand and reused while open.
@MainActor
final class WindowManager {
  static let shared = WindowManager()

  static let onboardingID = "onboarding"
  static let historyID = "history"

  private var windows: [String: NSWindow] = [:]

  func showOnboarding(controller: DictationController, settings: AppSettings) {
    show(id: Self.onboardingID, title: "Welcome to Dictum", size: CGSize(width: 540, height: 640)) {
      OnboardingView(controller: controller, settings: settings)
    }
  }

  func showHistory(history: HistoryStore) {
    show(id: Self.historyID, title: "Dictation History", size: CGSize(width: 760, height: 540), resizable: true) {
      HistoryView().environmentObject(history)
    }
  }

  func close(_ id: String) {
    windows[id]?.close()
  }

  static func activateApp() {
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Opens the SwiftUI `Settings` scene. Works from anywhere, not just from within a view.
  static func openSettings() {
    activateApp()
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
  }

  private func show<Content: View>(id: String, title: String, size: CGSize, resizable: Bool = false,
                                   @ViewBuilder content: () -> Content) {
    if let existing = windows[id] {
      existing.makeKeyAndOrderFront(nil)
      Self.activateApp()
      return
    }
    let hosting = NSHostingController(rootView: content())
    let window = NSWindow(contentViewController: hosting)
    var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
    if resizable { mask.insert(.resizable) }
    window.styleMask = mask
    window.title = title
    window.setContentSize(size)
    window.center()
    window.isReleasedWhenClosed = false
    windows[id] = window

    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
      Task { @MainActor in WindowManager.shared.windows[id] = nil }
    }

    window.makeKeyAndOrderFront(nil)
    Self.activateApp()
  }
}
