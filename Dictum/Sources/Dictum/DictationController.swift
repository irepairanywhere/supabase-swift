import AppKit
import Combine
import Foundation
import Speech
import DictumCore

/// The brain: hotkey → record → transcribe → clean → (polish) → insert → remember.
@MainActor
final class DictationController: ObservableObject {
  enum State: Equatable {
    case idle
    case recording(mode: DictationMode, handsFree: Bool)
    case processing(String)
    case error(String)
  }

  @Published private(set) var state: State = .idle
  /// Model download / load progress for the menu and settings ("Downloading Base 42%").
  @Published private(set) var engineStatus: String = ""
  @Published private(set) var lastError: String?
  @Published private(set) var hotkeysActive = false
  @Published private(set) var accessibilityGranted = Permissions.accessibilityGranted
  @Published private(set) var microphoneGranted = Permissions.microphoneGranted
  @Published private(set) var speechStatus: SFSpeechRecognizerAuthorizationStatus = Permissions.speechStatus

  let settings: AppSettings
  let history: HistoryStore
  let overlay = OverlayController()

  private let hotkeys = HotkeyMonitor()
  private let recorder = AudioRecorder()
  private let inserter = TextInserter()
  private let appleEngine = AppleSpeechEngine()
  private var whisperEngine: WhisperKitEngine?

  private var cancellables = Set<AnyCancellable>()
  private var permissionTimer: Timer?
  private var revealTask: Task<Void, Never>?
  private var processingTask: Task<Void, Never>?
  private var errorResetTask: Task<Void, Never>?
  private var warmUpTask: Task<Void, Never>?

  private var pressStartedAt: Date?
  private var lastTapAt: Date?
  private var stopOnRelease = false
  private var contextApp: AccessibilityBridge.FrontmostApp?
  private var commandSelection: String?
  private var lastAppliedEngine: EngineKind?
  private var lastAppliedVariant: String?

  init(settings: AppSettings, history: HistoryStore) {
    self.settings = settings
    self.history = history
    hotkeys.onPress = { [weak self] kind in self?.hotkeyPressed(kind) }
    hotkeys.onRelease = { [weak self] kind in self?.hotkeyReleased(kind) }
    hotkeys.onOtherKeyDown = { [weak self] keyCode in self?.otherKeyPressed(keyCode) }
    recorder.onLevel = { [weak self] level in self?.overlay.pushLevel(level) }
  }

  // MARK: - Derived state

  var isRecording: Bool {
    if case .recording = state { return true }
    return false
  }

  /// While true (a new shortcut is being recorded in Settings) the global hotkeys are ignored.
  var hotkeysSuspended: Bool {
    get { hotkeys.isSuspended }
    set { hotkeys.isSuspended = newValue }
  }

  /// The last error, shown in the menu only while idle.
  var visibleLastError: String? {
    if case .idle = state { return lastError }
    return nil
  }

  var isProcessing: Bool {
    if case .processing = state { return true }
    return false
  }

  var statusLine: String {
    switch state {
    case .idle:
      if !accessibilityGranted { return "Accessibility permission needed" }
      if !microphoneGranted { return "Microphone permission needed" }
      return "Ready · hold \(settings.data.dictationHotkey.displayName) to dictate"
    case .recording(let mode, let handsFree):
      let what = mode == .command ? "Listening for a command" : "Listening"
      let key = mode == .command ? settings.data.commandHotkey : settings.data.dictationHotkey
      return handsFree ? "\(what) · tap \(key.displayName) to stop" : "\(what)…"
    case .processing(let message):
      return message
    case .error(let message):
      return "Error: \(message)"
    }
  }

  // MARK: - Lifecycle

  func start() {
    applySettings(settings.data)
    settings.$data
      .dropFirst()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] data in self?.applySettings(data) }
      .store(in: &cancellables)
    refreshPermissions()
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refreshPermissions() }
    }
  }

  func refreshPermissions() {
    let accessibility = Permissions.accessibilityGranted
    let microphone = Permissions.microphoneGranted
    if accessibility != accessibilityGranted { accessibilityGranted = accessibility }
    if microphone != microphoneGranted { microphoneGranted = microphone }
    let speech = Permissions.speechStatus
    if speech != speechStatus { speechStatus = speech }
    if accessibility, !hotkeys.isRunning {
      hotkeysActive = hotkeys.start()
    } else if !accessibility, hotkeys.isRunning {
      hotkeys.stop()
      hotkeysActive = false
    }
  }

  func requestMicrophoneAccess() {
    Task {
      let granted = await Permissions.requestMicrophone()
      microphoneGranted = granted
    }
  }

  func requestSpeechAccess() {
    Task {
      let status = await Permissions.requestSpeech()
      speechStatus = status
    }
  }

  private func applySettings(_ data: SettingsData) {
    var bindings: [HotkeyKind: HotkeyBinding] = [.dictation: data.dictationHotkey]
    if data.commandModeEnabled, data.commandHotkey != data.dictationHotkey {
      bindings[.command] = data.commandHotkey
    }
    hotkeys.bindings = bindings
    overlay.isEnabled = data.showOverlay
    whisperEngine?.setVariant(data.whisperVariant)

    let engineChanged = lastAppliedEngine != data.engine
    let variantChanged = lastAppliedVariant != data.whisperVariant
    lastAppliedEngine = data.engine
    lastAppliedVariant = data.whisperVariant
    if engineChanged || (data.engine == .whisperKit && variantChanged) {
      warmUpEngine()
    }
  }

  // MARK: - Engines

  /// Loads models / checks permissions ahead of time so the first dictation is fast.
  func warmUpEngine() {
    warmUpTask?.cancel()
    let engine = currentEngine()
    warmUpTask = Task { [weak self] in
      let onStatus: @Sendable (String) -> Void = { message in
        Task { @MainActor in self?.engineStatus = message }
      }
      do {
        try await engine.prepare(status: onStatus)
        guard let self, !Task.isCancelled else { return }
        self.engineStatus = ""
      } catch {
        guard let self, !Task.isCancelled else { return }
        self.engineStatus = ""
        if engine.kind == .whisperKit { self.lastError = error.localizedDescription }
      }
    }
  }

  private func currentEngine() -> TranscriptionEngine {
    let data = settings.data
    switch data.engine {
    case .apple:
      return appleEngine
    case .whisperKit:
      return whisper()
    case .cloud:
      return CloudTranscriptionEngine(baseURL: data.cloudBaseURL, apiKey: settings.cloudAPIKey, model: data.cloudModel)
    }
  }

  private func whisper() -> WhisperKitEngine {
    if let whisperEngine {
      whisperEngine.setVariant(settings.data.whisperVariant)
      return whisperEngine
    }
    let engine = WhisperKitEngine(variant: settings.data.whisperVariant, modelsDirectory: AppPaths.modelsDirectory)
    whisperEngine = engine
    return engine
  }

  private func polisher(_ data: SettingsData) -> Polisher? {
    Polisher(baseURL: data.polishBaseURL, apiKey: settings.polishAPIKey, model: data.polishModel)
  }

  // MARK: - Hotkeys

  private func hotkeyPressed(_ kind: HotkeyKind) {
    let mode: DictationMode = kind == .command ? .command : .dictation
    switch state {
    case .idle, .error:
      beginRecording(mode: mode)
    case .recording(let activeMode, let handsFree):
      // Second tap while locked in hands-free mode: stop when the key comes back up.
      if handsFree, activeMode == mode { stopOnRelease = true }
    case .processing:
      break
    }
  }

  private func hotkeyReleased(_ kind: HotkeyKind) {
    let mode: DictationMode = kind == .command ? .command : .dictation
    guard case .recording(let activeMode, let handsFree) = state, activeMode == mode else { return }
    if handsFree {
      if stopOnRelease {
        stopOnRelease = false
        finishRecording()
      }
      return
    }
    let held = Date().timeIntervalSince(pressStartedAt ?? Date())
    guard held < 0.35 else {
      lastTapAt = nil
      finishRecording()
      return
    }
    // A quick tap: the second tap within half a second locks hands-free mode; a lone tap is ignored.
    let now = Date()
    if settings.data.tapTogglesHandsFree, let previousTap = lastTapAt, now.timeIntervalSince(previousTap) < 0.5 {
      lastTapAt = nil
      state = .recording(mode: mode, handsFree: true)
      overlay.show(.listening(handsFree: true, mode: mode))
    } else {
      lastTapAt = now
      cancelRecording()
    }
  }

  private func otherKeyPressed(_ keyCode: UInt16) {
    guard case .recording(_, let handsFree) = state else { return }
    if keyCode == 53 { // Escape
      cancelRecording()
      return
    }
    // Right ⌥ + E was a keyboard shortcut, not a dictation. Quietly stand down.
    if !handsFree, settings.data.cancelOnOtherKeys,
       let start = pressStartedAt, Date().timeIntervalSince(start) < 0.6 {
      cancelRecording()
    }
  }

  // MARK: - Recording

  /// Menu bar action: start hands-free, or stop if already recording.
  func toggleDictation() {
    switch state {
    case .idle, .error:
      beginRecording(mode: .dictation)
      if case .recording = state { state = .recording(mode: .dictation, handsFree: true) }
    case .recording:
      finishRecording()
    case .processing:
      break
    }
  }

  func cancelIfRecording() {
    if isRecording { cancelRecording() }
  }

  private func beginRecording(mode: DictationMode) {
    guard Permissions.microphoneGranted else {
      microphoneGranted = false
      showTransientError("Microphone access is needed. Open “Setup & permissions” from the menu bar.")
      return
    }
    var selection: String?
    if mode == .command {
      guard polisher(settings.data) != nil else {
        showTransientError("Command mode needs an AI provider. Set one up in Settings → AI Cleanup.")
        return
      }
      selection = AccessibilityBridge.selectedText()
    }
    do {
      try recorder.start()
    } catch {
      showTransientError(error.localizedDescription)
      return
    }
    errorResetTask?.cancel()
    lastError = nil
    commandSelection = selection
    contextApp = AccessibilityBridge.frontmostApp()
    pressStartedAt = Date()
    stopOnRelease = false
    state = .recording(mode: mode, handsFree: false)
    overlay.resetLevels()

    // Delay the pill and the sound a little so an accidental "Right ⌥ + key" shortcut
    // (which cancels us within a few milliseconds) doesn't flash the UI.
    revealTask?.cancel()
    revealTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 150_000_000)
      guard let self, !Task.isCancelled, case .recording(let currentMode, let handsFree) = self.state else { return }
      self.overlay.show(.listening(handsFree: handsFree, mode: currentMode))
      if self.settings.data.playSounds { Sounds.play(.start) }
    }
  }

  private func cancelRecording() {
    revealTask?.cancel()
    _ = recorder.stop()
    commandSelection = nil
    state = .idle
    overlay.hide()
  }

  private func finishRecording() {
    guard case .recording(let mode, _) = state else { return }
    revealTask?.cancel()
    let samples = recorder.stop()
    let duration = Double(samples.count) / AudioRecorder.targetSampleRate
    let data = settings.data
    guard duration >= data.minimumRecordingSeconds else {
      state = .idle
      overlay.hide()
      return
    }
    if data.playSounds { Sounds.play(.stop) }
    let app = contextApp
    let selection = commandSelection
    commandSelection = nil
    setProcessing("Transcribing…")
    processingTask = Task { [weak self] in
      guard let self else { return }
      await self.process(samples: samples, duration: duration, mode: mode, app: app, selection: selection, data: data)
    }
  }

  private func setProcessing(_ message: String) {
    state = .processing(message)
    overlay.show(.processing(message))
  }

  private func process(samples: [Float], duration: Double, mode: DictationMode,
                       app: AccessibilityBridge.FrontmostApp?, selection: String?, data: SettingsData) async {
    do {
      let engine = currentEngine()
      let request = TranscriptionRequest(samples: samples,
                                         sampleRate: Int(AudioRecorder.targetSampleRate),
                                         languageCode: data.effectiveLanguageCode,
                                         vocabulary: data.vocabulary)
      let raw = try await engine.transcribe(request)
      let cleaned = TextCleaner.clean(raw, options: data.cleanup, dictionary: data.dictionary)
      guard !cleaned.isEmpty else { throw TranscriptionError.noSpeech }

      var finalText = cleaned
      if mode == .command {
        guard let commandPolisher = self.polisher(data) else {
          throw TranscriptionError.unavailable("Command mode needs an AI provider (Settings → AI Cleanup).")
        }
        setProcessing("Applying…")
        finalText = try await commandPolisher.runCommand(instruction: cleaned, selectedText: selection, appName: app?.name)
      } else if data.polishEnabled, let textPolisher = self.polisher(data) {
        setProcessing("Polishing…")
        do {
          finalText = try await textPolisher.polish(cleaned, style: data.polishStyle, appName: app?.name,
                                                customInstructions: data.polishCustomInstructions,
                                                vocabulary: data.vocabulary)
        } catch {
          lastError = "AI cleanup failed, inserted the plain transcript instead. \(error.localizedDescription)"
        }
      }

      try Task.checkCancellation()
      await inserter.insert(finalText, method: data.insertionMethod, smartSpacing: data.smartSpacing,
                            restoreClipboard: data.restoreClipboard)
      history.add(HistoryEntry(rawText: raw, finalText: finalText, appName: app?.name, appBundleID: app?.bundleID,
                               durationSeconds: duration, engine: data.engine.rawValue, mode: mode))
      state = .idle
      overlay.show(.success)
      overlay.hide(after: 0.7)
    } catch is CancellationError {
      state = .idle
      overlay.hide()
    } catch {
      showTransientError(error.localizedDescription)
    }
  }

  private func showTransientError(_ message: String) {
    lastError = message
    state = .error(message)
    overlay.show(.error(message))
    if settings.data.playSounds { Sounds.play(.error) }
    overlay.hide(after: 2.8)
    errorResetTask?.cancel()
    errorResetTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 2_800_000_000)
      guard let self, !Task.isCancelled, case .error = self.state else { return }
      self.state = .idle
    }
  }
}
