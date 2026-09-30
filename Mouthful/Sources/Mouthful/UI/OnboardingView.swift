import Speech
import SwiftUI
import MouthfulCore

@MainActor
struct OnboardingView: View {
  @EnvironmentObject var controller: DictationController
  @EnvironmentObject var settings: AppSettings

  var canFinish: Bool { controller.microphoneGranted && controller.accessibilityGranted }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      header
      Text("Two permissions are required. macOS asks for them once.")
        .font(.callout)
      microphoneStep
      accessibilityStep
      speechStep
      Divider()
      shortcutSection
      Spacer(minLength: 0)
      footer
    }
    .padding(24)
    .frame(width: 540, height: 640)
  }

  var header: some View {
    HStack(spacing: 14) {
      Image(systemName: "waveform.circle.fill")
        .font(.system(size: 44))
        .foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 2) {
        Text("Welcome to Mouthful").font(.title.weight(.semibold))
        Text("Hold a key, talk, let go. Your words land wherever the cursor is.")
          .foregroundStyle(.secondary)
      }
    }
  }

  var microphoneStep: some View {
    StepRow(number: 1, title: "Microphone", done: controller.microphoneGranted,
            detail: "So Mouthful can hear you while you hold the key.") {
      if Permissions.microphoneUndetermined {
        Button("Allow") { controller.requestMicrophoneAccess() }
      } else {
        Button("Open System Settings") { Permissions.open(.microphone) }
      }
    }
  }

  var accessibilityStep: some View {
    StepRow(number: 2, title: "Accessibility", done: controller.accessibilityGranted,
            detail: "Lets Mouthful see the shortcut key and type into other apps. Turn on Mouthful in the list, then come back here.") {
      Button("Open System Settings") {
        Permissions.promptForAccessibility()
        Permissions.open(.accessibility)
      }
    }
  }

  var speechStep: some View {
    StepRow(number: 3, title: "Speech recognition (optional)", done: controller.speechStatus == .authorized,
            detail: "Needed only for the built-in Apple engine, which is the default. Skip it if you will use Whisper or a cloud API.") {
      if controller.speechStatus == .notDetermined {
        Button("Allow") { controller.requestSpeechAccess() }
      } else {
        Button("Open System Settings") { Permissions.open(.speechRecognition) }
      }
    }
  }

  var shortcutSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HotkeyPicker(id: "onboarding.dictation", title: "Dictation key", binding: $settings.data.dictationHotkey)
      Text("Try it now: click into any text field, hold \(settings.data.dictationHotkey.displayName), say something, release. Double-tap it to go hands-free, tap once more to stop.")
        .font(.caption)
        .foregroundStyle(.secondary)
      if settings.data.dictationHotkey == .fn {
        Text("Fn/🌐 tip: in System Settings → Keyboard set “Press 🌐 key to” to “Do Nothing”.")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
  }

  var footer: some View {
    HStack {
      Text(canFinish ? "All set. Mouthful lives in your menu bar." : "Waiting for permissions…")
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
}

@MainActor
struct StepRow<Action: View>: View {
  let number: Int
  let title: String
  let done: Bool
  let detail: String
  let action: Action

  init(number: Int, title: String, done: Bool, detail: String, @ViewBuilder action: () -> Action) {
    self.number = number
    self.title = title
    self.done = done
    self.detail = detail
    self.action = action()
  }

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
      if !done {
        action
      }
    }
  }
}
