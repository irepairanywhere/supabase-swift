import AppKit
import SwiftUI
import MouthfulCore

@MainActor
struct HistoryView: View {
  @EnvironmentObject var history: HistoryStore
  @EnvironmentObject var viewState: HistoryViewState

  var filtered: [HistoryEntry] {
    let query = viewState.search.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return history.entries }
    return history.entries.filter { entry in
      entry.finalText.localizedCaseInsensitiveContains(query)
        || (entry.appName ?? "").localizedCaseInsensitiveContains(query)
    }
  }

  var emptyTitle: String { history.entries.isEmpty ? "No dictations yet" : "No matches" }

  var emptyMessage: String {
    history.entries.isEmpty ? "Hold your dictation key in any text field and start talking." : "Try another search."
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 16) {
        StatsBadge(title: "Dictations", value: "\(history.stats.entries)")
        StatsBadge(title: "Words", value: "\(history.stats.words)")
        StatsBadge(title: "Time saved", value: "\(Int(history.stats.estimatedMinutesSaved)) min")
        Spacer()
        TextField("Search", text: $viewState.search)
          .textFieldStyle(.roundedBorder)
          .frame(width: 200)
        Button("Clear All", role: .destructive) { history.clear() }
          .disabled(history.entries.isEmpty)
      }
      .padding()
      Divider()
      if filtered.isEmpty {
        EmptyStateView(title: emptyTitle, message: emptyMessage)
      } else {
        List {
          ForEach(filtered) { entry in
            HistoryRow(entry: entry,
                       copied: viewState.copiedID == entry.id,
                       onCopy: { viewState.copyToClipboard(entry) },
                       onDelete: { history.remove(ids: [entry.id]) })
          }
        }
        .listStyle(.inset)
      }
    }
    .frame(minWidth: 620, minHeight: 420)
  }
}

@MainActor
struct StatsBadge: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value).font(.title3.weight(.semibold)).monospacedDigit()
      Text(title).font(.caption).foregroundStyle(.secondary)
    }
  }
}

@MainActor
struct EmptyStateView: View {
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "waveform")
        .font(.system(size: 36))
        .foregroundStyle(.secondary)
      Text(title).font(.title3.weight(.semibold))
      Text(message).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

@MainActor
struct HistoryRow: View {
  let entry: HistoryEntry
  let copied: Bool
  let onCopy: () -> Void
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
        if let app = entry.appName {
          Text("· \(app)")
        }
        Text("· \(Int(entry.durationSeconds.rounded()))s · \(entry.wordCount) words")
        if entry.mode == .command {
          Text("command")
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.purple.opacity(0.2), in: Capsule())
        }
        Spacer()
        Button(copied ? "Copied" : "Copy", action: onCopy)
          .buttonStyle(.borderless)
        Button(action: onDelete) {
          Image(systemName: "trash")
        }
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
