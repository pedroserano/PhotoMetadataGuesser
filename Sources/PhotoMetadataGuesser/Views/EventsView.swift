import SwiftUI
import DateGuessCore

/// Events and groups in one place: likely events among undated photos (even when they were scanned
/// years apart), suggested groups, and the events and groups you've saved.
struct EventsView: View {
    @Environment(AppState.self) private var state
    @State private var editing: EventDraft?
    @State private var openGroup: IdentifiedUUID?
    @State private var showingNewGroup = false
    @State private var suggestions: [GroupSuggestion] = []

    var body: some View {
        let events = state.eventSuggestions
        List {
            if !events.isEmpty {
                Section {
                    ForEach(events.prefix(200), id: \.self) { ids in
                        EventCard(state: state, ids: ids, onOpen: { editing = EventDraft(ids: $0) })
                    }
                } header: {
                    Text("Suggested Events")
                } footer: {
                    Text("Click a photo that doesn’t belong to leave it out. Same Event gives them one shared date and checks them for Apply.")
                }
            }
            if !suggestions.isEmpty {
                Section("Suggested Groups") {
                    ForEach(suggestions.prefix(40)) { s in
                        HStack(spacing: 12) {
                            Thumbnails(ids: s.assetIDs, side: 44, limit: 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).lineLimit(1)
                                Text(s.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Button("Make Group") {
                                let g = state.createGroup(name: s.title, assetIDs: s.assetIDs, kind: s.kind)
                                openGroup = IdentifiedUUID(id: g.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section("Your Events & Groups") {
                if state.groups.isEmpty {
                    Text("None yet. Click Same Event above, or New Group to gather photos you know go together.")
                        .foregroundStyle(.secondary)
                }
                ForEach(state.groups) { g in
                    Button {
                        openGroup = IdentifiedUUID(id: g.id)
                    } label: {
                        GroupRow(state: state, group: g)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit…") { openGroup = IdentifiedUUID(id: g.id) }
                        Button("Delete", role: .destructive) { state.groups.removeAll { $0.id == g.id } }
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if events.isEmpty && state.isEstimating && state.groups.isEmpty {
                ContentUnavailableView("Looking for Events…", systemImage: "square.stack",
                                       description: Text("Events show up here once photos have been compared."))
            }
        }
        .navigationSubtitle(events.isEmpty ? "" : "\(events.count.formatted()) suggested")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewGroup = true
                } label: {
                    Label("New Group", systemImage: "plus")
                }
                .help("Gather photos you know go together, and say what you know about them")
                .disabled(state.undatedSorted.isEmpty)
            }
        }
        .onAppear { suggestions = state.groupSuggestions() }
        .onChange(of: state.groups) { _, _ in suggestions = state.groupSuggestions() }
        .sheet(item: $editing) { draft in
            EventEditor(seed: draft.ids)
        }
        .sheet(item: $openGroup) { item in
            GroupSheet(groupID: item.id)
        }
        .sheet(isPresented: $showingNewGroup) {
            PhotoPickerSheet(groupID: nil) { id in openGroup = IdentifiedUUID(id: id) }
        }
    }
}

struct IdentifiedUUID: Identifiable {
    var id: UUID
}

struct EventDraft: Identifiable {
    var id: String { AppState.eventKey(ids) }
    var ids: [String]
}

/// A short row of thumbnails, with "+N" for the rest.
struct Thumbnails: View {
    var ids: [String]
    var side: CGFloat
    var limit: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ids.prefix(limit), id: \.self) { id in
                AssetThumbnail(assetID: id, side: side, cornerRadius: 5)
            }
            if ids.count > limit {
                Text("+\(ids.count - limit)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct EventCard: View {
    /// Passed in, not read from the environment (see PersonNameCell).
    var state: AppState
    var ids: [String]
    var onOpen: ([String]) -> Void
    /// Photos the user clicked to leave out of this event.
    @State private var excluded: Set<String> = []

    private var kept: [String] { ids.filter { !excluded.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(sharedGuess ?? "Event").font(.headline)
                    .help("The date all these photos get if you click Same Event, from all their clues together")
                Text("\(kept.count) photos").foregroundStyle(.secondary)
                Spacer()
                Button("Not One Event") { state.dismissEvent(ids) }
                    .buttonStyle(.borderless)
                Button("Set Date…") { onOpen(kept) }
                Button("Same Event") {
                    state.saveEvent(kept, name: sharedGuess.map { "Event, \($0)" } ?? "Event (\(kept.count) photos)",
                                    year: nil, month: nil, season: nil)
                }
                .buttonStyle(.borderedProminent)
                .disabled(kept.count < 2)
                .help("They’ll share one date, worked out from all their clues together, and be checked for Apply")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ids.prefix(12), id: \.self) { id in
                        let out = excluded.contains(id)
                        AssetThumbnail(assetID: id, side: 80, cornerRadius: 6)
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
        .padding(.vertical, 6)
    }

    /// The date this event gets if saved now, with every photo's clues pooled (e.g. "July 1979").
    /// Until that's computed, the most common of the photos' own guesses.
    private var sharedGuess: String? {
        if let combined = state.eventEstimates[AppState.eventKey(ids)] { return combined.displayString }
        let guesses = ids.compactMap { state.effectiveEstimate($0)?.displayString }
        return Dictionary(grouping: guesses, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
}

/// A saved event or group in the list.
struct GroupRow: View {
    /// Passed in, not read from the environment (see PersonNameCell).
    var state: AppState
    var group: PhotoGroup

    var body: some View {
        HStack(spacing: 12) {
            Thumbnails(ids: group.assetIDs, side: 44, limit: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts = ["\(group.assetIDs.count) photos", group.kind == .sameEvent ? "one event" : "same era"]
        if let first = group.assetIDs.first, group.kind == .sameEvent, let e = state.effectiveEstimate(first) {
            parts.append(e.displayString)
        }
        if !group.hint.isEmpty { parts.append(group.hint) }
        return parts.joined(separator: " · ")
    }
}

/// Everything about one saved event or group: what you know, and its photos.
struct GroupSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    var groupID: UUID
    @State private var selected: Set<String> = []
    @State private var adding = false

    var body: some View {
        let group = state.groups.first { $0.id == groupID }
        VStack(spacing: 0) {
            if let group {
                HSplitView {
                    GroupEditor(groupID: groupID)
                        .frame(minWidth: 340, idealWidth: 380, maxWidth: 420)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("\(group.assetIDs.count) photos").font(.headline)
                            Spacer()
                            if !selected.isEmpty {
                                Button("Remove \(selected.count) from Group") {
                                    state.remove(Array(selected), from: groupID)
                                    selected.removeAll()
                                }
                            }
                            Button("Add Photos…") { adding = true }
                        }
                        .padding(12)
                        ScrollView {
                            PhotoGrid(ids: group.assetIDs, selected: $selected)
                                .padding(12)
                        }
                    }
                    .frame(minWidth: 320)
                }
            }
            Divider()
            HStack {
                Button("Delete Group", role: .destructive) {
                    state.groups.removeAll { $0.id == groupID }
                    dismiss()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 900, height: 600)
        .sheet(isPresented: $adding) {
            PhotoPickerSheet(groupID: groupID) { _ in }
        }
    }
}

/// A grid of undated photos; click to select.
struct PhotoGrid: View {
    @Environment(AppState.self) private var state
    var ids: [String]
    @Binding var selected: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 10)], spacing: 10) {
            ForEach(ids, id: \.self) { id in
                if let photo = state.photo(id) {
                    GroupPhotoCell(photo: photo, isSelected: selected.contains(id), groupName: nil)
                        .onTapGesture {
                            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                        }
                }
            }
        }
    }
}

/// Pick undated photos for a new group, or to add to an existing one.
struct PhotoPickerSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    /// Nil makes a new group.
    var groupID: UUID?
    var onCreate: (UUID) -> Void
    @State private var selected: Set<String> = []
    @State private var name = ""
    @State private var onlyUngrouped = true
    @State private var search = ""

    private var photos: [String] {
        let grouped = Set(state.groups.flatMap(\.assetIDs))
        let current = Set(state.groups.first { $0.id == groupID }?.assetIDs ?? [])
        return state.undatedSorted.filter { p in
            if current.contains(p.id) { return false }
            if onlyUngrouped && grouped.contains(p.id) { return false }
            if search.isEmpty { return true }
            return p.filename.localizedCaseInsensitiveContains(search)
                || p.albums.contains { $0.localizedCaseInsensitiveContains(search) }
        }
        .map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if groupID == nil {
                TextField("Group name", text: $name, prompt: Text("Name, e.g. Grandma’s 80th birthday"))
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
            } else {
                Text("Add Photos").font(.title2.weight(.semibold))
            }
            HStack {
                TextField("Search filenames or albums", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Toggle("Only photos not in a group", isOn: $onlyUngrouped)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Select All") { selected.formUnion(photos) }
            }
            ScrollView {
                PhotoGrid(ids: photos, selected: $selected)
            }
            .overlay {
                if photos.isEmpty { ContentUnavailableView("No Photos", systemImage: "photo.on.rectangle") }
            }
            HStack {
                Text("\(selected.count) selected").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button(groupID == nil ? "Create Group" : "Add \(selected.count)") {
                    let ids = state.undatedSorted.map(\.id).filter { selected.contains($0) }
                    if let groupID {
                        state.add(ids, to: groupID)
                    } else {
                        let g = state.createGroup(name: name.isEmpty ? "New group" : name, assetIDs: ids)
                        onCreate(g.id)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 780, height: 600)
    }
}

struct GroupPhotoCell: View {
    var photo: UndatedPhoto
    var isSelected: Bool
    var groupName: String?

    var body: some View {
        AssetThumbnail(assetID: photo.id, side: 120, height: 100, cornerRadius: 8)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : .white, isSelected ? .white : .clear)
                    .shadow(radius: 2)
                    .padding(5)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 3)
            )
            .contentShape(Rectangle())
            .help(photo.albums.isEmpty ? photo.filename : "\(photo.filename)\nAlbums: \(photo.albums.joined(separator: ", "))")
    }
}

/// Edits everything the user knows about one group.
struct GroupEditor: View {
    @Environment(AppState.self) private var state
    var groupID: UUID

    /// Binds by ID (not index) so deleting or reordering groups can't point at the wrong one.
    private var groupBinding: Binding<PhotoGroup>? {
        guard let current = state.groups.first(where: { $0.id == groupID }) else { return nil }
        let state = self.state, id = groupID
        return Binding(
            get: { state.groups.first { $0.id == id } ?? current },
            set: { new in
                if let i = state.groups.firstIndex(where: { $0.id == id }) { state.groups[i] = new }
            })
    }

    var body: some View {
        if let group = groupBinding {
            Form {
                Section {
                    TextField("Name", text: group.name)
                    Picker("These photos are from", selection: group.kind) {
                        ForEach(GroupKind.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                }
                Section("What you know") {
                    TextField("Notes", text: group.hint, prompt: Text("e.g. Lake Tahoe trip, late 70s"), axis: .vertical)
                        .lineLimit(1...3)
                    LabeledContent("Years") {
                        HStack {
                            NumberField(title: "From", value: group.yearFrom, range: YearBounds.earliestPhotoYear...YearBounds.currentYear())
                            Text("to")
                            NumberField(title: "To", value: group.yearTo, range: YearBounds.earliestPhotoYear...YearBounds.currentYear())
                        }
                    }
                    Picker("Season", selection: group.season) {
                        Text("Unknown").tag(Season?.none)
                        ForEach(Season.allCases) { s in
                            Label(s.displayName, systemImage: s.symbolName).tag(Season?.some(s))
                        }
                    }
                }
                Section {
                    ForEach(group.people) { $hint in
                        HStack {
                            Text(state.people.first { $0.id == hint.personID }?.name ?? "Unknown person")
                            Spacer()
                            Text("about").foregroundStyle(.secondary)
                            NumberField(title: "age", value: $hint.approximateAge, range: 0...110, width: 50)
                            Button {
                                group.wrappedValue.people.removeAll { $0.id == hint.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                    }
                    Menu {
                        if state.people.isEmpty {
                            Text("Import people under People first")
                        }
                        ForEach(state.people) { person in
                            Button(person.name) {
                                group.wrappedValue.people.append(GroupPersonHint(personID: person.id))
                            }
                        }
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                    .fixedSize()
                } header: {
                    Text("Who’s in these photos")
                } footer: {
                    Text("Ages are optional.")
                }
            }
            .formStyle(.grouped)
        }
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
