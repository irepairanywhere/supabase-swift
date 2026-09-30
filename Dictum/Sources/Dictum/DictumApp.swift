import SwiftUI

@main
struct DictumApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra {
      MenuBarView()
        .environmentObject(appDelegate.controller)
        .environmentObject(appDelegate.settings)
        .environmentObject(appDelegate.history)
    } label: {
      MenuBarLabel()
        .environmentObject(appDelegate.controller)
    }
    .menuBarExtraStyle(.menu)
  }
}
