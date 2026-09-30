import AppKit
import MouthfulCore

/// Puts the final text where the user's cursor is. Default strategy: clipboard + ⌘V, then restore
/// the clipboard. Optional: Accessibility insertion first, paste as fallback.
@MainActor
final class TextInserter {
  func insert(_ text: String, method: InsertionMethod, smartSpacing: Bool, restoreClipboard: Bool) async {
    var payload = text
    if smartSpacing, case .known(let previous) = AccessibilityBridge.textContext(), let previous {
      let noSpaceAfter: Set<Character> = ["(", "[", "{", "\"", "'", "“", "‘", "/", "-", "@", "#"]
      if !previous.isWhitespace, !previous.isNewline, !noSpaceAfter.contains(previous) {
        payload = " " + payload
      }
    }
    if method == .accessibility, AccessibilityBridge.insertViaAccessibility(payload) {
      return
    }
    await paste(payload, restoreClipboard: restoreClipboard)
  }

  private func paste(_ text: String, restoreClipboard: Bool) async {
    let pasteboard = NSPasteboard.general
    let snapshot = restoreClipboard ? Self.snapshot(of: pasteboard) : nil
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    let ourChangeCount = pasteboard.changeCount

    Self.postCommandV()

    // Give the target app time to read the pasteboard before putting the old contents back.
    try? await Task.sleep(nanoseconds: 350_000_000)
    if let snapshot, pasteboard.changeCount == ourChangeCount {
      Self.restore(snapshot, to: pasteboard)
    }
  }

  static func postCommandV() {
    let source = CGEventSource(stateID: .combinedSessionState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // kVK_ANSI_V
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
    for event in [keyDown, keyUp] {
      event?.flags = .maskCommand
      event?.setIntegerValueField(.eventSourceUserData, value: SyntheticEvent.marker)
    }
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
  }

  // MARK: - Clipboard preservation

  typealias PasteboardSnapshot = [[NSPasteboard.PasteboardType: Data]]

  static func snapshot(of pasteboard: NSPasteboard) -> PasteboardSnapshot {
    (pasteboard.pasteboardItems ?? []).map { item in
      var contents: [NSPasteboard.PasteboardType: Data] = [:]
      for type in item.types where !type.rawValue.hasPrefix("com.apple.pasteboard.promised") {
        if let data = item.data(forType: type) { contents[type] = data }
      }
      return contents
    }
  }

  static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    let items: [NSPasteboardItem] = snapshot.compactMap { contents in
      guard !contents.isEmpty else { return nil }
      let item = NSPasteboardItem()
      for (type, data) in contents { item.setData(data, forType: type) }
      return item
    }
    if !items.isEmpty { pasteboard.writeObjects(items) }
  }
}
