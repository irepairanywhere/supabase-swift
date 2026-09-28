import AVFAudio
import Speech
import SwiftUI

enum SetupChecks {
  static let keyboardBundleID = "app.dictum.mobile.keyboard"

  /// iOS lists enabled third-party keyboards by bundle identifier here.
  static var isKeyboardEnabled: Bool {
    let keyboards = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] ?? []
    return keyboards.contains { $0.hasPrefix(keyboardBundleID) }
  }

  static var microphoneGranted: Bool { AVAudioApplication.shared.recordPermission == .granted }
  static var microphoneUndetermined: Bool { AVAudioApplication.shared.recordPermission == .undetermined }

  static func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
}

struct SetupView: View {
  @EnvironmentObject var store: MobileSettingsStore
  @State private var keyboardEnabled = SetupChecks.isKeyboardEnabled
  @State private var microphoneGranted = SetupChecks.microphoneGranted
  @State private var speechStatus = SFSpeechRecognizer.authorizationStatus()

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("Dictum adds a voice keyboard to your iPhone. In any app, hold the 🌐 key, pick Dictum, tap the mic and talk. The text is typed for you, cleaned up.")
        }

        Section("1. Add the keyboard") {
          StepRow(done: keyboardEnabled, title: "Enable the Dictum keyboard",
                  detail: "Settings → General → Keyboard → Keyboards → Add New Keyboard… → Dictum")
          Button("Open Settings") { SetupChecks.openSettings() }
        }

        Section("2. Allow Full Access") {
          StepRow(done: store.settings.keyboardHasHadFullAccess, title: "Turn on “Allow Full Access”",
                  detail: "Settings → Dictum → Keyboards → Allow Full Access. Required for the microphone, your settings and cloud features. Dictum never sends or stores what you type.")
          Button("Open Dictum settings") { SetupChecks.openSettings() }
        }

        Section("3. Permissions") {
          HStack {
            StepRow(done: microphoneGranted, title: "Microphone", detail: "So Dictum can hear you.")
            Spacer()
            if !microphoneGranted {
              Button(SetupChecks.microphoneUndetermined ? "Allow" : "Settings") {
                if SetupChecks.microphoneUndetermined {
                  Task { @MainActor in
                    microphoneGranted = await AVAudioApplication.requestRecordPermission()
                  }
                } else {
                  SetupChecks.openSettings()
                }
              }
              .buttonStyle(.bordered)
            }
          }
          HStack {
            StepRow(done: speechStatus == .authorized, title: "Speech recognition",
                    detail: "For the built-in Apple engine (default). Not needed for the cloud engine.")
            Spacer()
            if speechStatus == .notDetermined {
              Button("Allow") {
                SFSpeechRecognizer.requestAuthorization { status in
                  Task { @MainActor in speechStatus = status }
                }
              }
              .buttonStyle(.bordered)
            } else if speechStatus != .authorized {
              Button("Settings") { SetupChecks.openSettings() }
                .buttonStyle(.bordered)
            }
          }
        }

        Section("4. Try it") {
          Text("Open Messages or Notes, hold 🌐 and choose Dictum. Tap the mic, speak, tap again. Hold the mic instead to talk push-to-talk style.")
          Button(store.settings.hasCompletedSetup ? "Setup complete ✓" : "Mark setup complete") {
            store.settings.hasCompletedSetup = true
          }
          .disabled(store.settings.hasCompletedSetup)
        }
      }
      .navigationTitle("Setup")
      .onAppear(perform: refresh)
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
        refresh()
      }
    }
  }

  private func refresh() {
    keyboardEnabled = SetupChecks.isKeyboardEnabled
    microphoneGranted = SetupChecks.microphoneGranted
    speechStatus = SFSpeechRecognizer.authorizationStatus()
    store.reload()
  }
}

struct StepRow: View {
  let done: Bool
  let title: String
  let detail: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: done ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(done ? Color.green : Color.secondary)
        .font(.title3)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.body)
        Text(detail).font(.footnote).foregroundStyle(.secondary)
      }
    }
  }
}
