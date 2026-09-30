import AppKit
import Combine
import SwiftUI
import DictumCore

enum OverlayPhase: Equatable {
  case listening(handsFree: Bool, mode: DictationMode)
  case processing(String)
  case success
  case error(String)
}

@MainActor
final class OverlayModel: ObservableObject {
  @Published var phase: OverlayPhase = .listening(handsFree: false, mode: .dictation)
  @Published var levels: [Float] = Array(repeating: 0, count: 18)
}

/// The small floating pill at the bottom of the screen. It never takes focus, so the app the
/// user is dictating into stays frontmost.
@MainActor
final class OverlayController {
  let model = OverlayModel()
  var isEnabled = true

  private var panel: NSPanel?
  private var hideTask: Task<Void, Never>?

  func show(_ phase: OverlayPhase) {
    hideTask?.cancel()
    model.phase = phase
    guard isEnabled else { return }
    let panel = ensurePanel()
    position(panel)
    panel.alphaValue = 1
    panel.orderFrontRegardless()
  }

  func hide(after delay: TimeInterval = 0) {
    hideTask?.cancel()
    guard delay > 0 else {
      fadeOut()
      return
    }
    hideTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.fadeOut()
    }
  }

  func pushLevel(_ rms: Float) {
    var levels = model.levels
    levels.removeFirst()
    levels.append(min(1, rms * 8))
    model.levels = levels
  }

  func resetLevels() {
    model.levels = Array(repeating: 0, count: model.levels.count)
  }

  private func ensurePanel() -> NSPanel {
    if let panel { return panel }
    let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 64),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
    panel.isFloatingPanel = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isMovable = false
    panel.animationBehavior = .none
    let hosting = NSHostingView(rootView: OverlayView().environmentObject(model))
    hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 64)
    panel.contentView = hosting
    self.panel = panel
    return panel
  }

  private func position(_ panel: NSPanel) {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    guard let frame = screen?.visibleFrame else { return }
    let size = panel.frame.size
    panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 28))
  }

  private func fadeOut() {
    guard let panel, panel.isVisible else { return }
    panel.orderOut(nil)
  }
}

/// A panel that never becomes key or main, so it can't steal focus from the app being dictated into.
/// It declares no initializers, so it inherits all of NSPanel's.
final class OverlayPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

@MainActor
struct OverlayView: View {
  @EnvironmentObject var model: OverlayModel

  var body: some View {
    HStack(spacing: 10) {
      phaseContent
    }
    .font(.system(size: 13, weight: .medium))
    .padding(.horizontal, 16)
    .padding(.vertical, 9)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay {
      Capsule().strokeBorder(Color.primary.opacity(0.12))
    }
    .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  var phaseContent: some View {
    switch model.phase {
    case .listening(let handsFree, let mode):
      Circle()
        .fill(mode == .command ? Color.purple : Color.red)
        .frame(width: 9, height: 9)
      WaveformView(levels: model.levels)
        .frame(width: 80, height: 22)
      Text(mode == .command ? "Command…" : (handsFree ? "Listening · tap to stop" : "Listening…"))
    case .processing(let message):
      ProgressView().controlSize(.small)
      Text(message)
    case .success:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
      Text("Inserted")
    case .error(let message):
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.yellow)
      Text(message).lineLimit(2)
    }
  }
}

@MainActor
struct WaveformView: View {
  let levels: [Float]

  var body: some View {
    HStack(alignment: .center, spacing: 2) {
      ForEach(levels.indices, id: \.self) { index in
        RoundedRectangle(cornerRadius: 1.5)
          .fill(Color.accentColor)
          .frame(width: 3, height: max(3, CGFloat(levels[index]) * 22))
      }
    }
    .animation(.linear(duration: 0.06), value: levels)
  }
}
