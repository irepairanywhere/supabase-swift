import Foundation

/// Raw values match `CGEventFlags` so the app can convert without a lookup table.
public enum ModifierMask {
  public static let shift: UInt64 = 0x0002_0000
  public static let control: UInt64 = 0x0004_0000
  public static let option: UInt64 = 0x0008_0000
  public static let command: UInt64 = 0x0010_0000
  public static let fn: UInt64 = 0x0080_0000
  public static let all: UInt64 = shift | control | option | command | fn
}

/// A global shortcut. Either a lone modifier key held down (Fn, Right ⌥ …) or a key plus modifiers.
public struct HotkeyBinding: Codable, Hashable, Sendable {
  /// macOS virtual key code (`kVK_*`).
  public var keyCode: UInt16
  /// Modifier flags (`ModifierMask`) that must be held. For modifier-only bindings this is the
  /// flag of the key itself.
  public var modifiers: UInt64
  /// True when the shortcut is a single modifier key pressed alone.
  public var isModifierOnly: Bool

  public init(keyCode: UInt16, modifiers: UInt64, isModifierOnly: Bool) {
    self.keyCode = keyCode
    self.modifiers = modifiers & ModifierMask.all
    self.isModifierOnly = isModifierOnly
  }

  // Modifier-only presets
  public static let fn = HotkeyBinding(keyCode: 63, modifiers: ModifierMask.fn, isModifierOnly: true)
  public static let rightOption = HotkeyBinding(keyCode: 61, modifiers: ModifierMask.option, isModifierOnly: true)
  public static let rightCommand = HotkeyBinding(keyCode: 54, modifiers: ModifierMask.command, isModifierOnly: true)
  public static let rightShift = HotkeyBinding(keyCode: 60, modifiers: ModifierMask.shift, isModifierOnly: true)
  public static let rightControl = HotkeyBinding(keyCode: 62, modifiers: ModifierMask.control, isModifierOnly: true)
  // Key-combo presets
  public static let controlOptionSpace = HotkeyBinding(keyCode: 49, modifiers: ModifierMask.control | ModifierMask.option, isModifierOnly: false)
  public static let controlOptionD = HotkeyBinding(keyCode: 2, modifiers: ModifierMask.control | ModifierMask.option, isModifierOnly: false)
  public static let controlOptionC = HotkeyBinding(keyCode: 8, modifiers: ModifierMask.control | ModifierMask.option, isModifierOnly: false)

  public static let presets: [HotkeyBinding] = [
    .rightOption, .fn, .rightCommand, .rightShift, .rightControl, .controlOptionSpace, .controlOptionD, .controlOptionC,
  ]

  /// The `ModifierMask` flag a lone modifier key toggles, or nil when `keyCode` isn't a modifier.
  public static func modifierFlag(forKeyCode keyCode: UInt16) -> UInt64? {
    switch keyCode {
    case 63: return ModifierMask.fn
    case 58, 61: return ModifierMask.option
    case 55, 54: return ModifierMask.command
    case 59, 62: return ModifierMask.control
    case 56, 60: return ModifierMask.shift
    default: return nil
    }
  }

  public var displayName: String {
    if isModifierOnly { return Self.keyName(keyCode) }
    var parts: [String] = []
    if modifiers & ModifierMask.control != 0 { parts.append("⌃") }
    if modifiers & ModifierMask.option != 0 { parts.append("⌥") }
    if modifiers & ModifierMask.shift != 0 { parts.append("⇧") }
    if modifiers & ModifierMask.command != 0 { parts.append("⌘") }
    if modifiers & ModifierMask.fn != 0 { parts.append("Fn") }
    parts.append(Self.keyName(keyCode))
    return parts.joined()
  }

  public static func keyName(_ code: UInt16) -> String {
    if let name = keyNames[code] { return name }
    return "Key \(code)"
  }

  private static let keyNames: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
    14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
    26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
    37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
    48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc", 54: "Right ⌘", 55: "Left ⌘", 56: "Left ⇧",
    57: "Caps Lock", 58: "Left ⌥", 59: "Left ⌃", 60: "Right ⇧", 61: "Right ⌥", 62: "Right ⌃", 63: "Fn",
    96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
    109: "F10", 111: "F12", 113: "F15", 115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4",
    119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
  ]
}
