import SwiftUI
import DateGuessCore

/// Likely events among undated photos, even when they were scanned or imported at different times.
/// Date one event and every photo in it gets that date.
struct EventsView: View {
    @Environment(AppState.self) private var state
    var _editing = State<EventDraft?>(initialValue: nil)
    private var editing: EventDraft? { get { _editing.wrappedValue } nonmutating set { _editing.wrappedValue = newValue } }

    var body: some View {
        let events = state.eventSuggestions
        Group {
            if events.isEmpty {
                ContentUnavailableView {
                    Label(state.isEstimating ? "Looking for events…" : "No suggested events", systemImage: "square.stack.3d.up")
                } description: {
                    Text(state.isEstimating
                         ? "Events show up here once photos have been compared."
                         : "Photos that look like they’re from the same day or occasion show up here. Ones you’ve already saved as events are under Groups.")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("These look like they’re from the same event, even if they were scanned years apart. Click a photo that doesn’t belong to leave it out, then click Same Event: they’ll share one date and be checked in Review & Apply. Know the date? Click Set Date.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(events.prefix(200), id: \.self) { ids in
                            EventCard(ids: ids, onOpen: { editing = EventDraft(ids: $0) })
                        }
                    }
                    .padding(20)
                }
            }
        }
        .sheet(item: _editing.projectedValue) { draft in
            EventEditor(seed: draft.ids)
        }
    }
}

struct EventDraft: Identifiable {
    var id: String { AppState.eventKey(ids) }
    var ids: [String]
}

struct EventCard: View {
    @Environment(AppState.self) private var state
    var ids: [String]
    var onOpen: ([String]) -> Void
    /// Photos the user clicked to leave out of this event.
    @State private var excluded: Set<String> = []

    private var kept: [String] { ids.filter { !excluded.contains($0) } }

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text("\(kept.count) photos").font(.headline)
                if let guess = sharedGuess {
                    Text("· would be dated \(guess)")
                        .foregroundStyle(.secondary)
                        .help("The date all these photos get if you click Same Event, from all their clues together")
                }
                Spacer()
                Button("Not One Event") { state.dismissEvent(ids) }
                    .buttonStyle(.borderless)
                Button("Set Date…") { onOpen(kept) }
                Button {
                    state.saveEvent(kept, name: sharedGuess.map { "Event, \($0)" } ?? "Event (\(kept.count) photos)",
                                    year: nil, month: nil, season: nil)
                } label: {
                    Label("Same Event", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(kept.count < 2)
                .help("They’ll share one date, worked out from all their clues together, and be checked for Apply")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ids.prefix(12), id: \.self) { id in
                        let out = excluded.contains(id)
                        AssetThumbnail(assetID: id, side: 84, cornerRadius: 6)
                            .opacity(out ? 0.35 : 1)
                            .overlay(alignment: .topTrailing) {
                                if out {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .red).padding(4)
                                }
                            }
                            .onTapGesture { if out { excluded.remove(id) } else { excluded.insert(id) } }
                            .help(out ? "Left out. Click to put it back" : "Click to leave this one out")
                    }
                    if ids.count > 12 { Text("+\(ids.count - 12)").foregroundStyle(.secondary).padding(.horizontal, 6) }
                }
            }
        }
    }

    /// The date this event gets if saved now, with every photo's clues pooled (e.g. "July 1979").
    /// Until that's computed, the most common of the photos' own guesses.
    private var sharedGuess: String? {
        if let combined = state.eventEstimates[AppState.eventKey(ids)] { return combined.displayString }
        let guesses = ids.compactMap { state.effectiveEstimate($0)?.displayString }
        return Dictionary(grouping: guesses, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
}

/// Confirm which photos belong to an event, add ones it may have missed, and date it once.
struct EventEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    var seed: [String]

    @State private var included: Set<String> = []
    @State private var candidates: [String] = []
    @State private var name = ""
    @State private var year: Int?
    @State private var month: Int?
    @State private var season: Season?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Event name", text: $name, prompt: Text("Name, e.g. Lake Tahoe trip"))
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                Spacer()
                Text("\(included.count) photos").foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("In this event. Click a photo to leave it out.").font(.headline)
                    grid(seed + candidates.filter { included.contains($0) })
                    if !candidates.isEmpty {
                        Text("Might also be from this event. Click to add.").font(.headline)
                        grid(candidates.filter { !included.contains($0) })
                    }
                }
            }
            Divider()
            HStack(spacing: 10) {
                Text("When was it?").font(.headline)
                NumberField(title: "Year", value: $year, range: state.lowestYear...YearBounds.currentYear(), width: 70)
                Picker("Month", selection: $month) {
                    Text("Month unknown").tag(Int?.none)
                    ForEach(1...12, id: \.self) { m in Text(DateEstimate.monthNames[m - 1]).tag(Int?.some(m)) }
                }
                .labelsHidden()
                .fixedSize()
                if month == nil {
                    Picker("Season", selection: $season) {
                        Text("Season unknown").tag(Season?.none)
                        ForEach(Season.allCases) { s in Text(s.displayName).tag(Season?.some(s)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Event") {
                    let ids = state.undatedSorted.map(\.id).filter { included.contains($0) }
                    state.saveEvent(ids, name: name.isEmpty ? "Event (\(ids.count) photos)" : name,
                                    year: year, month: month, season: season)
                    state.banner = year == nil
                        ? "Saved \(ids.count) photos as one event with one shared date, and checked them in Review & Apply."
                        : "Dated \(ids.count) photos together and checked them in Review & Apply, ready to apply."
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(included.count < 2)
            }
            Text(year == nil ? "Without a year, the photos still get one shared guess from all their clues combined." : "Every photo in the event gets this date and is checked in Review & Apply. Nothing changes in Photos until you click Apply there.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 780, height: 620)
        .onAppear {
            included = Set(seed)
            candidates = state.eventCandidates(for: seed)
            // Start from the current shared guess, so often only a tweak is needed.
            let guesses = seed.compactMap { state.effectiveEstimate($0) }
            if let common = Dictionary(grouping: guesses, by: \.year).max(by: { $0.value.count < $1.value.count }) {
                year = common.key
                let seasons = common.value.filter { !$0.seasonIsDefault }.map(\.season)
                season = Dictionary(grouping: seasons, by: { $0 }).max { $0.value.count < $1.value.count }?.key
            }
        }
    }

    private func grid(_ ids: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 130), spacing: 8)], spacing: 8) {
            ForEach(ids, id: \.self) { id in
                let on = included.contains(id)
                AssetThumbnail(assetID: id, side: 104, cornerRadius: 8)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title3)
                            .foregroundStyle(on ? Theme.accent : .white)
                            .shadow(radius: 2)
                            .padding(5)
                    }
                    .opacity(on ? 1 : 0.6)
                    .onTapGesture {
                        if on { included.remove(id) } else { included.insert(id) }
                    }
                    .help(state.effectiveEstimate(id)?.displayString ?? "")
            }
        }
    }
}
