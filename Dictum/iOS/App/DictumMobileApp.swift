import SwiftUI

@main
struct DictumMobileApp: App {
  @StateObject private var settings = MobileSettingsStore()
  @StateObject private var history = SharedHistoryStore()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(settings)
        .environmentObject(history)
        .onChange(of: scenePhase) { _, phase in
          if phase == .active {
            settings.reload()
            history.load()
          }
        }
    }
  }
}
