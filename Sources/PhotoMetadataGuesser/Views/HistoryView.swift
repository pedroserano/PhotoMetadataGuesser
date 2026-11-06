import SwiftUI
import DateGuessCore

struct HistoryView: View {
    @Environment(AppState.self) private var state
    var _batchToUndo = State<ApplyBatch?>(initialValue: nil)
    private var batchToUndo: ApplyBatch? { get { _batchToUndo.wrappedValue } nonmutating set { _batchToUndo.wrappedValue = newValue } }

    var body: some View {
        Group {
            if state.journal.isEmpty {
                ContentUnavailableView("No Changes Yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Each time you apply dates, the old ones are kept here so you can put them back."))
            } else {
                List {
                    ForEach(state.journal) { batch in
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 6) {
                                    ForEach(batch.entries.prefix(30), id: \.assetID) { entry in
                                        VStack(spacing: 2) {
                                            AssetThumbnail(assetID: entry.assetID, side: 64, cornerRadius: 6)
                                            Text(entry.newDate.formatted(.dateTime.month(.abbreviated).year()))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .frame(height: 84)
                            if !batch.failures.isEmpty {
                                DisclosureGroup("\(batch.failures.count) couldn’t be changed") {
                                    ForEach(batch.failures.keys.sorted().prefix(50), id: \.self) { id in
                                        Text("\(state.photo(id)?.filename ?? id): \(batch.failures[id] ?? "")")
                                            .font(.caption)
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text(batch.date.formatted(date: .long, time: .shortened))
                                Text("· \(batch.entries.count.formatted()) photos" + (batch.undone ? " · undone"
                                     : (batch.undoneIDs?.isEmpty == false ? " · \(batch.undoneIDs!.count) put back" : "")))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if !batch.undone {
                                    Button("Undo…") { batchToUndo = batch }
                                        .disabled(state.isApplying)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert("Undo this change?", isPresented: Binding(get: { batchToUndo != nil }, set: { if !$0 { batchToUndo = nil } })) {
            Button("Restore Previous Dates") {
                if let batch = batchToUndo { state.undo(batch) }
                batchToUndo = nil
            }
            Button("Cancel", role: .cancel) { batchToUndo = nil }
        } message: {
            Text("The \(batchToUndo?.entries.count ?? 0) photos will get back the dates they had before.")
        }
    }
}
