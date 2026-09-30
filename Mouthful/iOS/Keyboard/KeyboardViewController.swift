import Combine
import UIKit
import MouthfulCore

/// The Mouthful keyboard. Tap the mic to start, tap again to stop (or hold it push-to-talk style).
/// Everything heavy (recognition, cleanup, optional AI polish) is shared with the app.
final class KeyboardViewController: UIInputViewController {
  private enum Mode { case dictation, command }

  private let transcriber = LiveTranscriber()
  private let history = SharedHistoryStore()
  private var settings = SharedStorage.loadSettings()
  private var keyboardView: KeyboardView!
  private var cancellables = Set<AnyCancellable>()
  private var heightConstraint: NSLayoutConstraint?

  private var mode: Mode = .dictation
  private var pressBeganAt: Date?
  private var handsFree = false
  private var stopOnRelease = false
  private var busy = false
  private var lastInsertedCount = 0
  private var commandSelection: String?
  private var deleteRepeatTimer: Timer?
  private var statusResetTask: Task<Void, Never>?

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    let keyboardView = KeyboardView()
    keyboardView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(keyboardView)
    NSLayoutConstraint.activate([
      keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
      keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    self.keyboardView = keyboardView

    keyboardView.globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
    keyboardView.micButton.addTarget(self, action: #selector(micDown), for: .touchDown)
    keyboardView.micButton.addTarget(self, action: #selector(micUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    keyboardView.commandButton.addTarget(self, action: #selector(commandTapped), for: .touchUpInside)
    keyboardView.undoButton.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)
    keyboardView.deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
    keyboardView.deleteButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(deleteLongPress(_:))))
    keyboardView.spaceButton.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
    keyboardView.returnButton.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)

    transcriber.$partialText
      .receive(on: DispatchQueue.main)
      .sink { [weak self] text in self?.showPartial(text) }
      .store(in: &cancellables)
    transcriber.$level
      .receive(on: DispatchQueue.main)
      .sink { [weak self] level in self?.keyboardView.setLevel(level) }
      .store(in: &cancellables)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    settings = SharedStorage.loadSettings()
    if hasFullAccess, !settings.keyboardHasHadFullAccess {
      settings.keyboardHasHadFullAccess = true
      SharedStorage.save(settings)
    }
    if heightConstraint == nil {
      let constraint = view.heightAnchor.constraint(equalToConstant: 236)
      constraint.priority = UILayoutPriority(999)
      constraint.isActive = true
      heightConstraint = constraint
    }
    keyboardView.globeButton.isHidden = !needsInputModeSwitchKey
    keyboardView.commandButton.isHidden = !settings.polishConfigured
    keyboardView.undoButton.isEnabled = lastInsertedCount > 0
    showIdleStatus()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    transcriber.cancel()
    resetRecordingState()
    deleteRepeatTimer?.invalidate()
  }

  // MARK: - Mic

  @objc private func micDown() {
    guard !busy else { return }
    if transcriber.isRecording {
      // Locked in hands-free mode: this tap stops when the finger lifts.
      stopOnRelease = true
      return
    }
    pressBeganAt = Date()
    stopOnRelease = false
    handsFree = false
    startRecording(mode: .dictation)
  }

  @objc private func micUp() {
    guard transcriber.isRecording else { return }
    if handsFree {
      if stopOnRelease {
        stopOnRelease = false
        finishRecording()
      }
      return
    }
    let held = Date().timeIntervalSince(pressBeganAt ?? Date())
    if held < 0.35 {
      handsFree = true
      keyboardView.statusLabel.text = "Listening… tap the mic when you're done"
    } else {
      finishRecording()
    }
  }

  @objc private func commandTapped() {
    guard !busy, !transcriber.isRecording else { return }
    commandSelection = textDocumentProxy.selectedText
    handsFree = true
    startRecording(mode: .command)
  }

  private func startRecording(mode: Mode) {
    self.mode = mode
    do {
      try transcriber.start(settings: settings)
    } catch {
      showTransient(error.localizedDescription + (hasFullAccess ? "" : " Turn on Allow Full Access for Mouthful in Settings."))
      resetRecordingState()
      return
    }
    if settings.hapticsEnabled { Haptics.tap() }
    statusResetTask?.cancel()
    keyboardView.setRecording(true, command: mode == .command)
    keyboardView.statusLabel.textColor = .label
    keyboardView.statusLabel.text = mode == .command
      ? (commandSelection == nil ? "Say what to write…" : "Say what to do with the selection…")
      : "Listening…"
  }

  private func finishRecording() {
    guard transcriber.isRecording else { return }
    busy = true
    keyboardView.setRecording(false, command: false)
    keyboardView.statusLabel.text = "Transcribing…"
    let settings = self.settings
    let mode = self.mode
    let selection = commandSelection

    Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        self.busy = false
        self.resetRecordingState()
      }
      do {
        let raw = try await self.transcriber.finish(settings: settings,
                                                    cloudAPIKey: SharedKeychain.get(SharedKeychain.cloudKeyAccount))
        let polishKey = SharedKeychain.get(SharedKeychain.polishKeyAccount)
        let text: String
        var note: String?
        if mode == .command {
          let instruction = TextCleaner.clean(raw, options: settings.cleanup, dictionary: settings.dictionary)
          guard !instruction.isEmpty else { throw TranscriberError.noSpeech }
          self.keyboardView.statusLabel.text = "Applying…"
          text = try await TextPipeline.runCommand(instruction: instruction, selectedText: selection,
                                                   settings: settings, polishAPIKey: polishKey)
        } else {
          if settings.polishEnabled { self.keyboardView.statusLabel.text = "Polishing…" }
          guard let outcome = await TextPipeline.finalize(raw: raw, settings: settings, polishAPIKey: polishKey, appName: nil) else {
            throw TranscriberError.noSpeech
          }
          text = outcome.text
          note = outcome.note
        }
        self.insert(text, replacingSelection: mode == .command && selection != nil)
        self.history.add(HistoryEntry(rawText: raw, finalText: text, appName: nil, appBundleID: nil,
                                      durationSeconds: self.transcriber.lastDuration, engine: settings.engine.rawValue,
                                      mode: mode == .command ? .command : .dictation))
        if settings.hapticsEnabled { Haptics.success() }
        self.showTransient(note ?? "Inserted. Tap the mic to add more.", isError: note != nil)
      } catch {
        if settings.hapticsEnabled { Haptics.error() }
        self.showTransient(error.localizedDescription)
      }
    }
  }

  private func resetRecordingState() {
    handsFree = false
    stopOnRelease = false
    pressBeganAt = nil
    commandSelection = nil
    mode = .dictation
    keyboardView.setRecording(false, command: false)
  }

  // MARK: - Text

  private func insert(_ text: String, replacingSelection: Bool) {
    let proxy = textDocumentProxy
    let payload = replacingSelection
      ? text
      : TextPipeline.smartSpaced(text, before: proxy.documentContextBeforeInput, enabled: settings.autoInsertSpace)
    proxy.insertText(payload)
    lastInsertedCount = payload.count
    keyboardView.undoButton.isEnabled = true
  }

  @objc private func undoTapped() {
    guard lastInsertedCount > 0 else { return }
    for _ in 0..<lastInsertedCount { textDocumentProxy.deleteBackward() }
    lastInsertedCount = 0
    keyboardView.undoButton.isEnabled = false
    showTransient("Removed the last dictation.", isError: false)
  }

  @objc private func deleteTapped() {
    textDocumentProxy.deleteBackward()
    lastInsertedCount = 0
    keyboardView.undoButton.isEnabled = false
  }

  @objc private func deleteLongPress(_ recognizer: UILongPressGestureRecognizer) {
    switch recognizer.state {
    case .began:
      deleteRepeatTimer?.invalidate()
      deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.textDocumentProxy.deleteBackward() }
      }
    case .ended, .cancelled, .failed:
      deleteRepeatTimer?.invalidate()
      deleteRepeatTimer = nil
    default:
      break
    }
  }

  @objc private func spaceTapped() {
    textDocumentProxy.insertText(" ")
  }

  @objc private func returnTapped() {
    textDocumentProxy.insertText("\n")
  }

  // MARK: - Status line

  private func showPartial(_ text: String) {
    guard transcriber.isRecording, !text.isEmpty else { return }
    keyboardView.statusLabel.textColor = .label
    keyboardView.statusLabel.text = text
  }

  private func showIdleStatus() {
    statusResetTask?.cancel()
    keyboardView.statusLabel.textColor = .secondaryLabel
    if !hasFullAccess {
      keyboardView.statusLabel.text = "Turn on “Allow Full Access” for Mouthful (Settings → General → Keyboard → Keyboards) so it can hear you."
    } else {
      keyboardView.statusLabel.text = settings.engine == .cloud
        ? "Tap the mic to dictate · cloud engine"
        : "Tap the mic to dictate · hold to talk"
    }
  }

  private func showTransient(_ message: String, isError: Bool = true) {
    keyboardView.statusLabel.textColor = isError ? .systemRed : .secondaryLabel
    keyboardView.statusLabel.text = message
    statusResetTask?.cancel()
    statusResetTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: isError ? 4_000_000_000 : 2_500_000_000)
      guard let self, !Task.isCancelled, !self.transcriber.isRecording, !self.busy else { return }
      self.showIdleStatus()
    }
  }
}
