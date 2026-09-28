import SwiftUI
import DictumCore

struct HistoryListView: View {
  @EnvironmentObject var history: SharedHistoryStore

  var body: some View {
    NavigationStack {
      Group {
        if history.entries.isEmpty {
          ContentUnavailableView("No dictations yet", systemImage: "waveform",
                                 description: Text("Everything you dictate with the keyboard or in the app shows up here."))
        } else {
          List {
            Section {
              HStack {
                stat("Dictations", "\(history.stats.entries)")
                Spacer()
                stat("Words", "\(history.stats.words)")
                Spacer()
                stat("Time saved", "\(Int(history.stats.estimatedMinutesSaved)) min")
              }
            }
            Section {
              ForEach(history.entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                  HStack {
                    Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    Text("· \(entry.wordCount) words")
                    if entry.mode == .command { Text("· command") }
                    Spacer()
                    Button {
                      UIPasteboard.general.string = entry.finalText
                    } label: {
                      Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                  }
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  Text(entry.finalText).textSelection(.enabled)
                }
                .padding(.vertical, 2)
              }
              .onDelete { offsets in
                history.remove(ids: Set(offsets.map { history.entries[$0].id }))
              }
            }
          }
        }
      }
      .navigationTitle("History")
      .toolbar {
        if !history.entries.isEmpty {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Clear", role: .destructive) { history.clear() }
          }
        }
      }
      .onAppear { history.load() }
    }
  }

  private func stat(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value).font(.title3.weight(.semibold)).monospacedDigit()
      Text(title).font(.caption).foregroundStyle(.secondary)
    }
  }
}
