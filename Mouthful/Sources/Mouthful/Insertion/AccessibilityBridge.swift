import AppKit
import ApplicationServices

/// Thin wrappers over the Accessibility API: which app is in front, what text is selected,
/// and what sits right before the insertion point.
enum AccessibilityBridge {
  struct FrontmostApp {
    let name: String?
    let bundleID: String?
  }

  enum TextContext {
    case unknown
    case known(previous: Character?)
  }

  static func frontmostApp() -> FrontmostApp {
    let app = NSWorkspace.shared.frontmostApplication
    return FrontmostApp(name: app?.localizedName, bundleID: app?.bundleIdentifier)
  }

  static func focusedElement() -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value)
    guard status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(value, to: AXUIElement.self)
  }

  static func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
    return value as? String
  }

  /// Currently selected text in the focused control, or nil when nothing is selected / unreadable.
  static func selectedText() -> String? {
    guard let element = focusedElement(),
          let text = stringAttribute(kAXSelectedTextAttribute, of: element),
          !text.isEmpty else { return nil }
    return text
  }

  /// The character right before the caret, when the focused control exposes its value and selection.
  static func textContext() -> TextContext {
    guard let element = focusedElement(),
          let value = stringAttribute(kAXValueAttribute, of: element) else { return .unknown }
    var rangeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
          let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return .unknown }
    let axValue = unsafeBitCast(rangeValue, to: AXValue.self)
    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range) else { return .unknown }
    let text = value as NSString
    guard range.location >= 0, range.location <= text.length else { return .unknown }
    if range.location == 0 { return .known(previous: nil) }
    let unit = text.character(at: range.location - 1)
    guard let scalar = UnicodeScalar(unit) else { return .known(previous: nil) }
    return .known(previous: Character(scalar))
  }

  /// Inserts text at the caret through AX. Returns false when the focused control is not an
  /// editable text role or the write did not visibly change the value.
  static func insertViaAccessibility(_ text: String) -> Bool {
    guard let element = focusedElement() else { return false }
    let role = stringAttribute(kAXRoleAttribute, of: element) ?? ""
    let editableRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]
    guard editableRoles.contains(role) else { return false }
    let before = stringAttribute(kAXValueAttribute, of: element)
    let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
    guard status == .success else { return false }
    if let before, let after = stringAttribute(kAXValueAttribute, of: element) {
      return after != before
    }
    return true
  }
}
