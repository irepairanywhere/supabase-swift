import SwiftUI
import DictumCore

/// In-app dictation scratchpad: useful on its own and for testing engines before using the keyboard.
struct DictateView: View {
  @EnvironmentObject var store: MobileSettingsStore
  @EnvironmentObject var history: SharedHistoryStore
  @StateObject private var transcriber = LiveTranscriber()
  @State private var text = ""
  @State private var note: String?
  @State private var errorMessage: String?
  @State private var busy = false
  @State private var copied = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        ZStack(alignment: .topLeading) {
          TextEditor(text: $text)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
          if text.isEmpty && !transcriber.isRecording {
            Text("Tap the mic and start talking. The text appears here; copy or share it anywhere.")
              .foregroundStyle(.secondary)
              .padding(16)
              .allowsHitTesting(false)
          }
        }

        if transcriber.isRecording {
          Text(transcriber.partialText.isEmpty ? "Listening…" : transcriber.partialText)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let note {
          Text(note).font(.footnote).foregroundStyle(.orange)
        }
        if let errorMessage {
          Text(errorMessage).font(.footnote).foregroundStyle(.red)
        }

        micButton

        HStack(spacing: 12) {
          Button(copied ? "Copied" : "Copy") {
            UIPasteboard.general.string = text
            copied = true
            Task { @MainActor in
              try? await Task.sleep(nanoseconds: 1_200_000_000)
              copied = false
            }
          }
          .buttonStyle(.bordered)
          .disabled(text.isEmpty)
          ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
            .buttonStyle(.bordered)
            .disabled(text.isEmpty)
          Button("Clear", role: .destructive) { text = "" }
            .buttonStyle(.bordered)
            .disabled(text.isEmpty)
        }
      }
      .padding()
      .navigationTitle("Dictate")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Text(store.settings.engine == .apple ? "Apple Speech" : "Cloud")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var micButton: some View {
    VStack(spacing: 8) {
      Button(action: toggle) {
        ZStack {
          Circle()
            .fill(transcriber.isRecording ? Color.red : Color.accentColor)
            .frame(width: 88, height: 88)
            .scaleEffect(1 + CGFloat(transcriber.level) * 0.5)
            .animation(.easeOut(duration: 0.08), value: transcriber.level)
          if busy {
            ProgressView().tint(.white)
          } else {
            Image(systemName: transcriber.isRecording ? "stop.fill" : "mic.fill")
              .font(.system(size: 34, weight: .semibold))
              .foregroundStyle(.white)
          }
        }
      }
      .buttonStyle(.plain)
      .disabled(busy)
      Text(busy ? "Working…" : (transcriber.isRecording ? "Tap to stop" : "Tap to dictate"))
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private func toggle() {
    errorMessage = nil
    note = nil
    if transcriber.isRecording {
      finish()
    } else {
      do {
        try transcriber.start(settings: store.settings)
        if store.settings.hapticsEnabled { Haptics.tap() }
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func finish() {
    busy = true
    let settings = store.settings
    Task { @MainActor in
      defer { busy = false }
      do {
        let raw = try await transcriber.finish(settings: settings, cloudAPIKey: SharedKeychain.get(SharedKeychain.cloudKeyAccount))
        guard let outcome = await TextPipeline.finalize(raw: raw, settings: settings,
                                                        polishAPIKey: SharedKeychain.get(SharedKeychain.polishKeyAccount),
                                                        appName: "Notes") else {
          errorMessage = "No speech detected."
          return
        }
        text += TextPipeline.smartSpaced(outcome.text, before: text, enabled: settings.autoInsertSpace)
        note = outcome.note
        history.add(HistoryEntry(rawText: raw, finalText: outcome.text, appName: "Dictum", appBundleID: nil,
                                 durationSeconds: transcriber.lastDuration, engine: settings.engine.rawValue,
                                 mode: .dictation))
        if settings.hapticsEnabled { Haptics.success() }
      } catch {
        errorMessage = error.localizedDescription
        if settings.hapticsEnabled { Haptics.error() }
      }
    }
  }
}
