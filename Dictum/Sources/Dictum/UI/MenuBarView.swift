import AppKit
import SwiftUI
import DictumCore

/// The menu bar icon. It changes while recording or working.
@MainActor
struct MenuBarLabel: View {
  @EnvironmentObject var controller: DictationController

  var iconName: String {
    switch controller.state {
    case .idle: return controller.accessibilityGranted ? "waveform" : "waveform.slash"
    case .recording: return "waveform.circle.fill"
    case .processing: return "ellipsis.circle"
    case .error: return "exclamationmark.circle"
    }
  }

  var body: some View {
    Image(systemName: iconName)
  }
}

/// The menu that opens from the menu bar icon.
@MainActor
struct MenuBarView: View {
  @EnvironmentObject var controller: DictationController
  @EnvironmentObject var settings: AppSettings
  @EnvironmentObject var history: HistoryStore

  var body: some View {
    Group {
      Text(controller.statusLine)
      if !controller.engineStatus.isEmpty {
        Text(controller.engineStatus)
      }
      if let error = controller.visibleLastError {
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
    }
    Group {
      Divider()
      Button("Settings…") { WindowManager.shared.showSettings() }
        .keyboardShortcut(",")
      Button("History… (\(history.entries.count))") { WindowManager.shared.showHistory() }
      Button("Setup & permissions…") { WindowManager.shared.showOnboarding() }
      Divider()
      Button("Quit Dictum") { NSApp.terminate(nil) }
        .keyboardShortcut("q")
    }
  }
}
