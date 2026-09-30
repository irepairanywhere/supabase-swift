import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let settings: AppSettings
  let history: HistoryStore
  let controller: DictationController
  let recorder: ShortcutRecorder

  override init() {
    let settings = AppSettings()
    let history = HistoryStore()
    let controller = DictationController(settings: settings, history: history)
    let recorder = ShortcutRecorder()
    self.settings = settings
    self.history = history
    self.controller = controller
    self.recorder = recorder
    super.init()
    // While a new shortcut is being recorded, the global hotkeys must not start a dictation.
    recorder.onRecordingChange = { [weak controller] active in
      controller?.hotkeysSuspended = active
    }
    WindowManager.shared.configure(controller: controller, settings: settings, history: history, recorder: recorder)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    WindowManager.ensureEditMenu()
    controller.start()
    let needsSetup = !settings.data.hasCompletedOnboarding
      || !Permissions.accessibilityGranted
      || !Permissions.microphoneGranted
    if needsSetup {
      WindowManager.shared.showOnboarding()
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationWillTerminate(_ notification: Notification) {
    controller.cancelIfRecording()
  }
}
