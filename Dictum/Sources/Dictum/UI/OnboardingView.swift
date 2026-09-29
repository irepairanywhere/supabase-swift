import SwiftUI
import DictumCore

struct OnboardingView: View {
  @ObservedObject var controller: DictationController
  @ObservedObject var settings: AppSettings
  @State private var speechStatus = Permissions.speechStatus

  private var canFinish: Bool { controller.microphoneGranted && controller.accessibilityGranted }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 14) {
        Image(systemName: "waveform.circle.fill")
          .font(.system(size: 44))
          .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 2) {
          Text("Welcome to Dictum").font(.title.weight(.semibold))
          Text("Hold a key, talk, let go. Your words land wherever the cursor is.")
            .foregroundStyle(.secondary)
        }
      }

      Text("Two permissions are required. macOS asks for them once.")
        .font(.callout)

      StepRow(number: 1, title: "Microphone", done: controller.microphoneGranted,
              detail: "So Dictum can hear you while you hold the key.") {
        if Permissions.microphoneUndetermined {
          Button("Allow") { controller.requestMicrophoneAccess() }
        } else {
          Button("Open System Settings") { Permissions.open(.microphone) }
        }
      }

      StepRow(number: 2, title: "Accessibility", done: controller.accessibilityGranted,
              detail: "Lets Dictum see the shortcut key and type into other apps. Turn on Dictum in the list, then come back here.") {
        Button("Open System Settings") {
          Permissions.promptForAccessibility()
          Permissions.open(.accessibility)
        }
      }

      StepRow(number: 3, title: "Speech recognition (optional)", done: speechStatus == .authorized,
              detail: "Needed only for the built-in Apple engine, which is the default. Skip it if you will use Whisper or a cloud API.") {
        if speechStatus == .notDetermined {
          Button("Allow") {
            Task { @MainActor in speechStatus = await Permissions.requestSpeech() }
          }
        } else if speechStatus != .authorized {
          Button("Open System Settings") { Permissions.open(.speechRecognition) }
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        HotkeyPicker(title: "Dictation key", binding: $settings.data.dictationHotkey)
        Text("Try it now: click into any text field, hold \(settings.data.dictationHotkey.displayName), say something, release. Double-tap it to go hands-free, tap once more to stop.")
          .font(.caption)
          .foregroundStyle(.secondary)
        if settings.data.dictationHotkey == .fn {
          Text("Fn/🌐 tip: in System Settings → Keyboard set “Press 🌐 key to” to “Do Nothing”.")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }

      Spacer(minLength: 0)

      HStack {
        Text(canFinish ? "All set. Dictum lives in your menu bar." : "Waiting for permissions…")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Done") {
          settings.data.hasCompletedOnboarding = true
          WindowManager.shared.close(WindowManager.onboardingID)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canFinish)
      }
    }
    .padding(24)
    .frame(width: 540, height: 640)
    .onAppear { speechStatus = Permissions.speechStatus }
  }
}

private struct StepRow<Action: View>: View {
  let number: Int
  let title: String
  let done: Bool
  let detail: String
  @ViewBuilder let action: () -> Action

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
        .font(.title2)
        .foregroundStyle(done ? Color.green : Color.secondary)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.headline)
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if !done { action() }
    }
  }
}
