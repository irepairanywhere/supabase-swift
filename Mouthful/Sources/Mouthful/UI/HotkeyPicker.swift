import AppKit
import SwiftUI
import MouthfulCore

/// A preset menu plus a "Record…" button for any custom shortcut.
@MainActor
struct HotkeyPicker: View {
  let id: String
  let title: String
  @Binding var binding: HotkeyBinding
  @EnvironmentObject var recorder: ShortcutRecorder

  var body: some View {
    HStack {
      Picker(title, selection: $binding) {
        ForEach(HotkeyBinding.presets, id: \.self) { preset in
          Text(preset.displayName).tag(preset)
        }
        if !HotkeyBinding.presets.contains(binding) {
          Text("Custom: \(binding.displayName)").tag(binding)
        }
      }
      Button(recorder.activeID == id ? "Press keys… (Esc cancels)" : "Record…") {
        let target = $binding
        recorder.toggle(id) { captured in
          target.wrappedValue = captured
        }
      }
    }
    .onDisappear {
      if recorder.activeID == id { recorder.stop() }
    }
  }
}
