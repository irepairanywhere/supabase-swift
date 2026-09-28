import SwiftUI

@main
struct DictumApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      MenuBarView(controller: appDelegate.controller, settings: appDelegate.settings, history: appDelegate.history)
    } label: {
      MenuBarLabel(controller: appDelegate.controller)
    }
    .menuBarExtraStyle(.menu)

    Settings {
      SettingsView()
        .environmentObject(appDelegate.settings)
        .environmentObject(appDelegate.controller)
        .environmentObject(appDelegate.history)
    }
  }
}
