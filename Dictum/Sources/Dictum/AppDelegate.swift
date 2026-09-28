import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let settings: AppSettings
  let history: HistoryStore
  let controller: DictationController

  override init() {
    let settings = AppSettings()
    let history = HistoryStore()
    self.settings = settings
    self.history = history
    self.controller = DictationController(settings: settings, history: history)
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    controller.start()
    let needsSetup = !settings.data.hasCompletedOnboarding
      || !Permissions.accessibilityGranted
      || !Permissions.microphoneGranted
    if needsSetup {
      WindowManager.shared.showOnboarding(controller: controller, settings: settings)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationWillTerminate(_ notification: Notification) {
    controller.cancelIfRecording()
  }
}
