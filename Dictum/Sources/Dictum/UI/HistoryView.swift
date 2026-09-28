import AppKit
import SwiftUI
import DictumCore

struct HistoryView: View {
  @EnvironmentObject var history: HistoryStore
  @State private var search = ""

  private var filtered: [HistoryEntry] {
    guard !search.isEmpty else { return history.entries }
    return history.entries.filter {
      $0.finalText.localizedCaseInsensitiveContains(search) || ($0.appName ?? "").localizedCaseInsensitiveContains(search)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 16) {
        StatsBadge(title: "Dictations", value: "\(history.stats.entries)")
        StatsBadge(title: "Words", value: "\(history.stats.words)")
        StatsBadge(title: "Time saved", value: "\(Int(history.stats.estimatedMinutesSaved)) min")
        Spacer()
        TextField("Search", text: $search)
          .textFieldStyle(.roundedBorder)
          .frame(width: 200)
        Button("Clear All", role: .destructive) { history.clear() }
          .disabled(history.entries.isEmpty)
      }
      .padding()
      Divider()
      if filtered.isEmpty {
        ContentUnavailableView(
          history.entries.isEmpty ? "No dictations yet" : "No matches",
          systemImage: "waveform",
          description: Text(history.entries.isEmpty ? "Hold your dictation key in any text field and start talking." : "Try another search."))
      } else {
        List {
          ForEach(filtered) { entry in
            HistoryRow(entry: entry) { history.remove(ids: [entry.id]) }
          }
        }
        .listStyle(.inset)
      }
    }
    .frame(minWidth: 620, minHeight: 420)
  }
}

private struct StatsBadge: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value).font(.title3.weight(.semibold)).monospacedDigit()
      Text(title).font(.caption).foregroundStyle(.secondary)
    }
  }
}

private struct HistoryRow: View {
  let entry: HistoryEntry
  let onDelete: () -> Void
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
        if let app = entry.appName { Text("· \(app)") }
        Text("· \(Int(entry.durationSeconds.rounded()))s · \(entry.wordCount) words")
        if entry.mode == .command {
          Text("command").padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.purple.opacity(0.2), in: Capsule())
        }
        Spacer()
        Button(copied ? "Copied" : "Copy") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(entry.finalText, forType: .string)
          copied = true
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
          }
        }
        .buttonStyle(.borderless)
        Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
          .buttonStyle(.borderless)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      Text(entry.finalText)
        .textSelection(.enabled)
      if entry.rawText != entry.finalText {
        Text("Heard: \(entry.rawText)")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(2)
      }
    }
    .padding(.vertical, 4)
  }
}
