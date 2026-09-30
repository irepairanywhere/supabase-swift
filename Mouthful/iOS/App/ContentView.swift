import SwiftUI

struct ContentView: View {
  @EnvironmentObject var settings: MobileSettingsStore
  @State private var selection: Tab = .dictate

  enum Tab: Hashable { case dictate, setup, history, settings }

  var body: some View {
    TabView(selection: $selection) {
      DictateView()
        .tabItem { Label("Dictate", systemImage: "mic.fill") }
        .tag(Tab.dictate)
      SetupView()
        .tabItem { Label("Setup", systemImage: "keyboard") }
        .tag(Tab.setup)
      HistoryListView()
        .tabItem { Label("History", systemImage: "clock") }
        .tag(Tab.history)
      MobileSettingsView()
        .tabItem { Label("Settings", systemImage: "gearshape") }
        .tag(Tab.settings)
    }
    .onAppear {
      if !settings.settings.hasCompletedSetup { selection = .setup }
    }
  }
}
