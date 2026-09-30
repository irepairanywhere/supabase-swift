import AppKit
import CoreGraphics
import MouthfulCore

/// Stamped onto the ⌘V events Mouthful posts itself so the event tap ignores them.
enum SyntheticEvent {
  static let marker: Int64 = 0x4449_4354
}

enum HotkeyKind: Hashable {
  case dictation
  case command
}

/// Watches the keyboard system-wide through a CGEvent tap. Needs Accessibility permission.
/// Modifier-only shortcuts (Fn, Right ⌥ …) are detected on `flagsChanged`; key combos are
/// detected on keyDown/keyUp and swallowed so they don't reach the frontmost app.
@MainActor
final class HotkeyMonitor {
  var bindings: [HotkeyKind: HotkeyBinding] = [:]
  var onPress: ((HotkeyKind) -> Void)?
  var onRelease: ((HotkeyKind) -> Void)?
  /// Any other key going down (key code), used to cancel accidental activations and for Escape.
  var onOtherKeyDown: ((UInt16) -> Void)?

  private(set) var isRunning = false

  /// When true every event passes through untouched (used while recording a new shortcut).
  var isSuspended = false {
    didSet { if isSuspended { pressed.removeAll() } }
  }
  private var tap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var pressed: Set<HotkeyKind> = []

  /// Returns false when the tap could not be created, which means Accessibility is not granted.
  @discardableResult
  func start() -> Bool {
    if isRunning { return true }

    func bit(_ type: CGEventType) -> CGEventMask { CGEventMask(1) << CGEventMask(type.rawValue) }
    let mask = bit(.keyDown) | bit(.keyUp) | bit(.flagsChanged)

    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo else { return Unmanaged.passUnretained(event) }
      let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
      // The run loop source is attached to the main run loop, so this runs on the main thread.
      let swallow = MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
      return swallow ? nil : Unmanaged.passUnretained(event)
    }

    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                      place: .headInsertEventTap,
                                      options: .defaultTap,
                                      eventsOfInterest: mask,
                                      callback: callback,
                                      userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
      return false
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    self.tap = tap
    runLoopSource = source
    isRunning = true
    return true
  }

  func stop() {
    if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    tap = nil
    runLoopSource = nil
    pressed.removeAll()
    isRunning = false
  }

  /// Returns true when the event must be swallowed.
  private func handle(type: CGEventType, event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return false
    }
    if isSuspended || event.getIntegerValueField(.eventSourceUserData) == SyntheticEvent.marker {
      return false
    }

    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags.rawValue & ModifierMask.all

    switch type {
    case .flagsChanged:
      for (kind, binding) in bindings where binding.isModifierOnly && binding.keyCode == keyCode {
        let isDown = flags & binding.modifiers != 0
        if isDown, !pressed.contains(kind) {
          pressed.insert(kind)
          onPress?(kind)
        } else if !isDown, pressed.contains(kind) {
          pressed.remove(kind)
          onRelease?(kind)
        }
      }
      return false

    case .keyDown:
      let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
      for (kind, binding) in bindings
      where !binding.isModifierOnly && binding.keyCode == keyCode && flags == binding.modifiers {
        if !isRepeat, !pressed.contains(kind) {
          pressed.insert(kind)
          onPress?(kind)
        }
        return true
      }
      onOtherKeyDown?(keyCode)
      return false

    case .keyUp:
      for (kind, binding) in bindings
      where !binding.isModifierOnly && binding.keyCode == keyCode && pressed.contains(kind) {
        pressed.remove(kind)
        onRelease?(kind)
        return true
      }
      return false

    default:
      return false
    }
  }
}
