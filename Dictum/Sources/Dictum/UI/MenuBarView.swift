import SwiftUI
import DictumCore

struct MenuBarLabel: View {
  @ObservedObject var controller: DictationController

  var body: some View {
    Image(systemName: iconName)
  }

  private var iconName: String {
    switch controller.state {
    case .idle: return controller.accessibilityGranted ? "waveform" : "waveform.slash"
    case .recording: return "waveform.circle.fill"
    case .processing: return "ellipsis.circle"
    case .error: return "exclamationmark.circle"
    }
  }
}

struct MenuBarView: View {
  @ObservedObject var controller: DictationController
  @ObservedObject var settings: AppSettings
  @ObservedObject var history: HistoryStore
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Text(controller.statusLine)
    if !controller.engineStatus.isEmpty {
      Text(controller.engineStatus)
    }
    if let error = controller.lastError, case .idle = controller.state {
      Text("Last error: \(error)")
    }
    Divider()

    Button(controller.isRecording ? "Stop & insert" : "Start hands-free dictation") {
      controller.toggleDictation()
    }
    .disabled(controller.isProcessing || !controller.microphoneGranted)

    if controller.isRecording {
      Button("Cancel recording") { controller.cancelIfRecording() }
    }

    Picker("Speech engine", selection: $settings.data.engine) {
      ForEach(EngineKind.allCases) { engine in
        Text(engine.displayName).tag(engine)
      }
    }

    Toggle("AI cleanup", isOn: $settings.data.polishEnabled)

    Divider()

    Button("Settings…") {
      WindowManager.activateApp()
      openSettings()
    }
    .keyboardShortcut(",")

    Button("History… (\(history.entries.count))") {
      WindowManager.shared.showHistory(history: history)
    }

    Button("Setup & permissions…") {
      WindowManager.shared.showOnboarding(controller: controller, settings: settings)
    }

    Divider()

    Button("Quit Dictum") { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }
}
