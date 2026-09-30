import AppKit
import ApplicationServices
import AVFoundation
import Speech

enum Permissions {
  enum Pane: String {
    case accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    case microphone = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    case speechRecognition = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
    case keyboard = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
  }

  static var microphoneGranted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
  static var microphoneUndetermined: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined }

  static func requestMicrophone() async -> Bool {
    await AVCaptureDevice.requestAccess(for: .audio)
  }

  static var accessibilityGranted: Bool { AXIsProcessTrusted() }

  /// Shows the system "Mouthful would like to control this computer" dialog and adds the app to the list.
  static func promptForAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  static var speechStatus: SFSpeechRecognizerAuthorizationStatus { SFSpeechRecognizer.authorizationStatus() }

  static func requestSpeech() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
  }

  static func open(_ pane: Pane) {
    if let url = URL(string: pane.rawValue) { NSWorkspace.shared.open(url) }
  }
}
