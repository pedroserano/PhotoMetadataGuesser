import SwiftUI
import DateGuessCore

struct HistoryView: View {
    @Environment(AppState.self) private var state
    var _batchToUndo = State<ApplyBatch?>(initialValue: nil)
    private var batchToUndo: ApplyBatch? { get { _batchToUndo.wrappedValue } nonmutating set { _batchToUndo.wrappedValue = newValue } }
    @State private var placesToUndo: PlaceBatch?

    /// Date and place changes together, newest first.
    private enum Item: Identifiable {
        case dates(ApplyBatch)
        case places(PlaceBatch)
        var id: UUID { switch self { case .dates(let b): b.id; case .places(let b): b.id } }
        var date: Date { switch self { case .dates(let b): b.date; case .places(let b): b.date } }
    }

    private var items: [Item] {
        (state.journal.map(Item.dates) + state.places.journal.map(Item.places)).sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("No Changes Yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Each time you apply dates or places, the old ones are kept here so you can put them back."))
            } else {
                List {
                    ForEach(items) { item in
                        switch item {
                        case .dates(let batch): dateSection(batch)
                        case .places(let batch): placeSection(batch)
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
        .alert("Remove these locations?", isPresented: Binding(get: { placesToUndo != nil }, set: { if !$0 { placesToUndo = nil } })) {
            Button("Remove Locations") {
                if let batch = placesToUndo { state.places.undo(batch) }
                placesToUndo = nil
            }
            Button("Cancel", role: .cancel) { placesToUndo = nil }
        } message: {
            Text("The \(placesToUndo?.entries.count ?? 0) photos will go back to having no location.")
        }
    }

    private func placeSection(_ batch: PlaceBatch) -> some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(batch.entries.prefix(30), id: \.assetID) { entry in
                        VStack(spacing: 2) {
                            AssetThumbnail(assetID: entry.assetID, side: 64, cornerRadius: 6)
                            PlaceLabel(point: entry.new, name: entry.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 64)
                    }
                }
            }
            .frame(height: 84)
            if !batch.failures.isEmpty {
                DisclosureGroup("\(batch.failures.count) couldn’t be changed") {
                    ForEach(batch.failures.keys.sorted().prefix(50), id: \.self) { id in
                        Text("\(id): \(batch.failures[id] ?? "")").font(.caption)
                    }
                }
            }
        } header: {
            HStack {
                Label(batch.date.formatted(date: .long, time: .shortened), systemImage: "mappin.and.ellipse")
                Text("· \(batch.entries.count.formatted()) locations" + (batch.undone ? " · undone" : ""))
                    .foregroundStyle(.secondary)
                Spacer()
                if !batch.undone {
                    Button("Undo…") { placesToUndo = batch }
                        .disabled(state.places.isApplying)
                }
            }
        }
    }

    private func dateSection(_ batch: ApplyBatch) -> some View {
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
