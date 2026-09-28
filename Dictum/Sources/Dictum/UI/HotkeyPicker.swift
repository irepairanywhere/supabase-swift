import AppKit
import SwiftUI
import DictumCore

struct HotkeyPicker: View {
  let title: String
  @Binding var binding: HotkeyBinding

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
      ShortcutRecorderButton(binding: $binding)
    }
  }
}

/// Click, then press the shortcut you want. A lone modifier (Fn, Right ⌥ …) is accepted when it
/// is released without any other key; a key with modifiers is accepted on key down.
struct ShortcutRecorderButton: View {
  @Binding var binding: HotkeyBinding
  @State private var isRecording = false
  @State private var monitor: Any?
  @State private var pendingModifier: UInt16?

  var body: some View {
    Button(isRecording ? "Press keys… (Esc cancels)" : "Record…") {
      isRecording ? stop() : start()
    }
    .onDisappear { stop() }
  }

  private func start() {
    isRecording = true
    pendingModifier = nil
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
      handle(event)
      return nil
    }
  }

  private func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    isRecording = false
    pendingModifier = nil
  }

  private func handle(_ event: NSEvent) {
    let flags = Self.modifierMask(from: event.modifierFlags)
    switch event.type {
    case .keyDown:
      pendingModifier = nil
      if event.keyCode == 53 { // Escape
        stop()
        return
      }
      guard flags != 0 else { return } // Plain keys would make typing impossible.
      binding = HotkeyBinding(keyCode: event.keyCode, modifiers: flags, isModifierOnly: false)
      stop()
    case .flagsChanged:
      guard let flag = HotkeyBinding.modifierFlag(forKeyCode: event.keyCode) else { return }
      if flags & flag != 0 {
        pendingModifier = event.keyCode
      } else if pendingModifier == event.keyCode {
        binding = HotkeyBinding(keyCode: event.keyCode, modifiers: flag, isModifierOnly: true)
        stop()
      }
    default:
      break
    }
  }

  static func modifierMask(from flags: NSEvent.ModifierFlags) -> UInt64 {
    var mask: UInt64 = 0
    if flags.contains(.shift) { mask |= ModifierMask.shift }
    if flags.contains(.control) { mask |= ModifierMask.control }
    if flags.contains(.option) { mask |= ModifierMask.option }
    if flags.contains(.command) { mask |= ModifierMask.command }
    if flags.contains(.function) { mask |= ModifierMask.fn }
    return mask
  }
}
