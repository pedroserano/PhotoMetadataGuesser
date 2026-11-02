import SwiftUI
import DateGuessCore

struct ReviewView: View {
    @Environment(AppState.self) private var state
    var goToPeople: () -> Void = {}

    var _filter = State<Filter>(initialValue: .toReview)
    private var filter: Filter { get { _filter.wrappedValue } nonmutating set { _filter.wrappedValue = newValue } }
    var _sort = State<Sort>(initialValue: .library)
    private var sort: Sort { get { _sort.wrappedValue } nonmutating set { _sort.wrappedValue = newValue } }
    var _groupFilter = State<UUID?>(initialValue: nil)
    private var groupFilter: UUID? { get { _groupFilter.wrappedValue } nonmutating set { _groupFilter.wrappedValue = newValue } }
    var _search = State<String>(initialValue: "")
    private var search: String { get { _search.wrappedValue } nonmutating set { _search.wrappedValue = newValue } }
    var _detailID = State<String?>(initialValue: nil)
    private var detailID: String? { get { _detailID.wrappedValue } nonmutating set { _detailID.wrappedValue = newValue } }
    var _lastClicked = State<String?>(initialValue: nil)
    private var lastClicked: String? { get { _lastClicked.wrappedValue } nonmutating set { _lastClicked.wrappedValue = newValue } }
    var _confirmApply = State<Bool>(initialValue: false)
    private var confirmApply: Bool { get { _confirmApply.wrappedValue } nonmutating set { _confirmApply.wrappedValue = newValue } }

    enum Filter: String, CaseIterable, Identifiable {
        case toReview = "All"
        case selected = "Checked"
        case low = "Unsure"
        case ignored = "Hidden"
        var id: String { rawValue }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case library = "Library order"
        case confidence = "Most confident first"
        case year = "Estimated year"
        case filename = "Filename"
        var id: String { rawValue }
    }

    private var visibleIDs: [String] {
        var items = state.undatedSorted.filter { state.estimates[$0.id] != nil }
        if let g = groupFilter, let group = state.groups.first(where: { $0.id == g }) {
            let ids = Set(group.assetIDs)
            items = items.filter { ids.contains($0.id) }
        }
        if !search.isEmpty {
            items = items.filter { $0.filename.localizedCaseInsensitiveContains(search) || $0.albums.contains { $0.localizedCaseInsensitiveContains(search) } }
        }
        items = items.filter { photo in
            let d = state.decision(photo.id)
            let level = state.effectiveEstimate(photo.id)?.confidenceLevel
            switch filter {
            case .toReview: return !d.ignored
            case .selected: return d.selected && !d.ignored
            case .low: return !d.ignored && level == .low
            case .ignored: return d.ignored
            }
        }
        switch sort {
        case .library: break
        case .confidence:
            items.sort { (state.estimates[$0.id]?.estimate.confidence ?? 0) > (state.estimates[$1.id]?.estimate.confidence ?? 0) }
        case .year:
            items.sort { (state.effectiveEstimate($0.id)?.year ?? 0) < (state.effectiveEstimate($1.id)?.year ?? 0) }
        case .filename:
            items.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        }
        return items.map(\.id)
    }

    var body: some View {
        let ids = visibleIDs
        let selectedCount = state.selectedForApply.count
        ScrollView {
            if state.people.isEmpty && !state.estimates.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.2").foregroundStyle(.secondary)
                    Text("Birth years make guesses much better.").foregroundStyle(.secondary)
                    Button("Add People") { goToPeople() }
                        .buttonStyle(.link)
                    Spacer()
                }
                .font(.callout)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16, alignment: .top)], spacing: 20) {
                ForEach(ids, id: \.self) { id in
                    ReviewCard(assetID: id, onOpen: { detailID = id },
                               onToggle: { toggle(id, in: ids, extendRange: NSEvent.modifierFlags.contains(.shift)) })
                }
            }
            .padding(20)
        }
        .overlay { emptyState(ids) }
        // Menu items' shortcuts only work while the menu is open, so these keep ⌘A and ⇧⌘A working.
        .background {
            Group {
                Button("Check All Shown") { state.select(ids, true) }
                    .keyboardShortcut("a", modifiers: .command)
                Button("Uncheck All Shown") { state.select(ids, false) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .searchable(text: _search.projectedValue, placement: .toolbar, prompt: "Filenames or albums")
        .navigationSubtitle(selectedCount > 0 ? "\(selectedCount.formatted()) checked" : "\(ids.count.formatted()) photos")
        .toolbar { toolbarItems(ids, selectedCount) }
        .sheet(item: Binding(get: { detailID.map(IdentifiedString.init) }, set: { detailID = $0?.id })) { item in
            PhotoDetailSheet(assetID: item.id)
        }
        .alert("Apply \(selectedCount.formatted()) new dates?", isPresented: _confirmApply.projectedValue) {
            Button("Apply Dates") { state.applySelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only photos without a real date that you checked are changed. Any whose date was changed in Photos since the last scan are skipped. Photos updates each date the same way Image ▸ Adjust Date and Time does: the photos aren’t replaced, and their places, people, albums and edits stay the same. You can undo this from History.")
        }
    }

    @ViewBuilder private func emptyState(_ ids: [String]) -> some View {
        if state.scan.lastScan == nil && !state.isScanning {
            ContentUnavailableView {
                Label("Find Your Undated Photos", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("The app looks for photos without a real date, like scanned prints, and guesses when each was taken. Nothing changes until you apply.")
            } actions: {
                Button("Scan Library") { state.startScan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        } else if state.estimates.isEmpty {
            ContentUnavailableView {
                Label(state.isScanning ? "Scanning Your Library…" : state.isEstimating ? "Guessing Dates…" : "Nothing to Review", systemImage: "sparkles")
            } description: {
                Text(state.isScanning || state.isEstimating ? "The first guesses show up here in a moment." : "No undated photos were found.")
            }
        } else if ids.isEmpty {
            if search.isEmpty {
                ContentUnavailableView("No Photos", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("Nothing matches “\(filter.rawValue)”."))
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbarItems(_ ids: [String], _ selectedCount: Int) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Show", selection: _filter.projectedValue) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            sortMenu
            checkMenu(ids)
            Button {
                confirmApply = true
            } label: {
                Text(selectedCount == 0 ? "Apply" : "Apply \(selectedCount.formatted())")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount == 0 || state.isApplying)
            .help("Set the checked photos’ dates in Photos")
        }
    }

    /// Click checks or unchecks one photo; Shift-click sets every photo from the last one clicked to this
    /// one the same way (like selecting a range of files in Finder).
    private func toggle(_ id: String, in ids: [String], extendRange: Bool) {
        let newValue = !state.decision(id).selected
        if extendRange, let anchor = lastClicked, let a = ids.firstIndex(of: anchor), let b = ids.firstIndex(of: id) {
            state.select(Array(ids[min(a, b)...max(a, b)]), newValue)
        } else {
            state.setSelected(id, newValue)
        }
        lastClicked = id
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: _sort.projectedValue) {
                ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            if !state.groups.isEmpty {
                Picker("Event or Group", selection: _groupFilter.projectedValue) {
                    Text("All Photos").tag(UUID?.none)
                    ForEach(state.groups) { g in Text(g.name).tag(UUID?.some(g.id)) }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort, or show one event or group")
    }

    /// Bulk checking: ⌘A checks everything shown, ⇧⌘A unchecks it.
    private func checkMenu(_ ids: [String]) -> some View {
        let confident = ids.filter { state.effectiveEstimate($0)?.confidenceLevel == .high }
        return Menu {
            Button("Check All Shown  ⌘A") { state.select(ids, true) }
            Button("Check Confident (\(confident.count.formatted()))") { state.select(confident, true) }
                .disabled(confident.isEmpty)
            Button("Check Medium or High Confidence") {
                state.select(ids.filter { state.effectiveEstimate($0)?.confidenceLevel != .low }, true)
            }
            Divider()
            Button("Uncheck All Shown  ⇧⌘A") { state.select(ids, false) }
        } label: {
            Label("Check", systemImage: "checkmark.circle")
        }
        .help("Check or uncheck many photos at once (⌘A checks all shown)")
    }
}

struct IdentifiedString: Identifiable {
    var id: String
}

struct ReviewCard: View {
    @Environment(AppState.self) private var state
    var assetID: String
    var onOpen: () -> Void
    /// Clicking the picture (or its checkmark) checks or unchecks it.
    var onToggle: () -> Void = {}
    var _showWhy = State<Bool>(initialValue: false)
    private var showWhy: Bool { get { _showWhy.wrappedValue } nonmutating set { _showWhy.wrappedValue = newValue } }

    var body: some View {
        if let computed = state.estimates[assetID], let estimate = state.effectiveEstimate(assetID), let photo = state.photo(assetID) {
            let decision = state.decision(assetID)
            let overridden = decision.isOverridden
            VStack(alignment: .leading, spacing: 6) {
                AssetThumbnail(assetID: assetID, side: .infinity, height: 170)
                    // A single click checks it: no double-click to wait for, so checking many is quick.
                    .onTapGesture { if !decision.ignored { onToggle() } }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(decision.selected ? Theme.accent : .clear, lineWidth: 3)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: decision.selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(decision.selected ? Theme.accent : .white, decision.selected ? .white : .clear)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .padding(7)
                            .opacity(decision.ignored ? 0.3 : 1)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .topTrailing) {
                        Button(action: onOpen) {
                            Image(systemName: "info.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, .black.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        .help("Details and who’s in it")
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let g = computed.groupName {
                            Label(g, systemImage: "square.stack")
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.regularMaterial, in: Capsule())
                                .padding(7)
                                .allowsHitTesting(false)
                        }
                    }
                    .help("\(photo.filename) · now \(photo.libraryDate?.shortDay ?? "no date")")

                HStack(spacing: 5) {
                    SeasonIcon(season: estimate.season)
                    Text(estimate.displayString)
                        .font(.headline)
                        .lineLimit(1)
                    if overridden {
                        Image(systemName: "pencil").foregroundStyle(.secondary).help("You changed this guess")
                    }
                    Spacer(minLength: 4)
                    ConfidenceBadge(estimate: computed.estimate)
                }
                Text(subtitle(computed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Stepper(value: Binding(
                        get: { estimate.year },
                        set: { state.setOverride(assetID, year: $0, season: decision.overrideSeason) }),
                        in: state.lowestYear...YearBounds.currentYear()) {
                        Text(String(estimate.year)).monospacedDigit()
                    }
                    .fixedSize()
                    .help("Change the year")
                    Menu {
                        Section("Season") {
                            ForEach(Season.allCases) { s in
                                Button {
                                    state.setOverride(assetID, year: decision.overrideYear, season: s)
                                } label: {
                                    Label("\(s.displayName) (\(DateEstimate.monthNames[s.representativeMonth - 1]))", systemImage: s.symbolName)
                                }
                            }
                        }
                        Section("Month") {
                            ForEach(1...12, id: \.self) { m in
                                Button(DateEstimate.monthNames[m - 1]) { state.setMonth(assetID, m) }
                            }
                        }
                        if overridden {
                            Divider()
                            Button("Use the Original Guess") { state.setOverride(assetID, year: nil, season: nil) }
                        }
                    } label: {
                        // Shows the exact month when there is one, otherwise the season.
                        Text(estimate.usedExactMonth ? DateEstimate.monthNames[max(1, min(12, estimate.month)) - 1] : estimate.season.displayName)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Change the season or the exact month")
                    Spacer(minLength: 0)
                    Button { showWhy = true } label: {
                        Image(systemName: "questionmark.bubble")
                    }
                    .buttonStyle(.borderless)
                    .help("Why this date?")
                    .popover(isPresented: _showWhy.projectedValue, arrowEdge: .bottom) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Why \(estimate.displayString)?").font(.headline)
                                Text("Most likely \(computed.estimate.rangeText) · about \(Int(computed.estimate.confidence * 100))% confident within ±2 years")
                                    .font(.caption).foregroundStyle(.secondary)
                                EvidenceList(evidence: computed.evidence)
                            }
                            .padding(16)
                        }
                        .frame(width: 420, height: 380)
                    }
                }
                .controlSize(.small)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .opacity(decision.ignored ? 0.5 : 1)
            .contextMenu {
                Button(decision.selected ? "Uncheck" : "Check") { state.setSelected(assetID, !decision.selected) }
                    .disabled(decision.ignored)
                Button("Details & Who’s in It…") { onOpen() }
                Button("Show in Photos") { Task { await state.showInPhotos(assetID) } }
                Divider()
                if decision.ignored {
                    Button("Review This Photo Again") { state.setIgnored(assetID, false) }
                } else {
                    Button("Keep Current Date (Don’t Show Again)") { state.setIgnored(assetID, true) }
                }
            }
        }
    }

    private func subtitle(_ c: ComputedEstimate) -> String {
        let e = c.estimate
        if !e.hasAnyEvidence { return "No clues found — please set the year yourself" }
        let used = c.evidence.filter { $0.hasYearInfo }.count
        var text = "Likely \(e.rangeText) · \(used) clue\(used == 1 ? "" : "s")"
        if e.seasonIsDefault { text += " · season unknown" }
        return text
    }
}

struct PhotoDetailSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    var assetID: String

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            FacePreview(assetID: assetID, maxSide: 520)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let estimate = state.effectiveEstimate(assetID), let computed = state.estimates[assetID] {
                        HStack {
                            SeasonIcon(season: estimate.season)
                            Text(estimate.displayString).font(.title.weight(.semibold))
                            ConfidenceBadge(estimate: computed.estimate)
                        }
                        Text("Likely between \(computed.estimate.rangeText)").foregroundStyle(.secondary)
                    }
                    if let photo = state.photo(assetID) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(photo.filename).font(.headline)
                            Text("Currently dated: \(photo.libraryDate?.formatted(date: .long, time: .shortened) ?? "no date")")
                            Text(photo.reason.explanation)
                            if !photo.albums.isEmpty { Text("Albums: \(photo.albums.joined(separator: ", "))") }
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    Divider()
                    PhotoPeopleEditor(assetID: assetID)
                    SameEventStrip(assetID: assetID)
                    Divider()
                    EvidenceList(evidence: state.estimates[assetID]?.evidence ?? [])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(width: 1000, height: 620)
        .overlay(alignment: .topTrailing) {
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(16)
        }
    }
}

/// Who's in this photo according to Photos' name tags, and how old they look. Names are added in
/// Photos itself; here you can fill in a missing birth year or an age.
struct PhotoPeopleEditor: View {
    @Environment(AppState.self) private var state
    var assetID: String

    var body: some View {
        let hints = state.people(in: assetID)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Who’s in this photo?").font(.headline)
                Spacer()
                ShowInPhotosButton(assetID: assetID)
            }
            if hints.isEmpty {
                Text("Nobody here is named in Photos yet. Click Show in Photos and name them there; they show up here when you come back. Their birth year, and how old they look, date the photo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(hints) { hint in
                if let person = state.people.first(where: { $0.id == hint.personID }) {
                    row(person, hint, hints)
                }
            }
        }
    }

    private func row(_ person: PersonInfo, _ hint: GroupPersonHint, _ hints: [GroupPersonHint]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .foregroundStyle(Theme.accent)
            Text(person.name.isEmpty ? "Unnamed" : person.name).fontWeight(.medium)
            if person.birthYear == nil {
                Text("born").foregroundStyle(.secondary)
                NumberField(title: "year", value: birthYear(person.id), range: 1850...YearBounds.currentYear(), width: 60)
                    .help("Needed before this person can date photos")
            } else {
                Text("looks about").foregroundStyle(.secondary)
                NumberField(title: "age", value: Binding(
                    get: { hint.approximateAge },
                    set: { age in
                        state.setPhotoPeople(assetID, hints.map { h in
                            var h = h
                            if h.personID == hint.personID { h.approximateAge = age }
                            return h
                        })
                    }), range: 0...110, width: 50)
                Text("years old").foregroundStyle(.secondary)
            }
            Spacer()
            if !hint.fromPhotos {
                // Added by hand in an earlier version of the app.
                Button {
                    state.setPhotoPeople(assetID, hints.filter { $0.personID != hint.personID })
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove from this photo (wasn’t tagged in Photos)")
            }
        }
    }

    private func birthYear(_ id: UUID) -> Binding<Int?> {
        Binding(
            get: { state.people.first { $0.id == id }?.birthYear },
            set: { year in state.updateBirthday(id) { $0.birthYear = year } })
    }
}

/// Undated photos that look like they're from the same event, with a way to date them all at once.
struct SameEventStrip: View {
    @Environment(AppState.self) private var state
    var assetID: String
    var _editing = State<EventDraft?>(initialValue: nil)
    private var editing: EventDraft? { get { _editing.wrappedValue } nonmutating set { _editing.wrappedValue = newValue } }

    var body: some View {
        let suggestion = state.eventSuggestion(containing: assetID) ?? []
        let links = state.estimates[assetID]?.matches ?? []
        var seen = Set([assetID])
        let matches = (suggestion + links).filter { seen.insert($0).inserted }
        let group = state.groupFor(assetID)
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Text("Same event").font(.headline)
                Spacer()
                if group?.kind != .sameEvent {
                    Button {
                        editing = EventDraft(ids: [assetID] + matches)
                    } label: {
                        Label("Date This Event…", systemImage: "calendar.badge.plus")
                    }
                    .help("Pick the photos from the same event and give them all one date")
                } else if let group {
                    Text("In the event “\(group.name)”").foregroundStyle(.secondary)
                }
            }
            if matches.isEmpty {
                Text("No look-alikes found yet. Date This Event lets you look for more from the same day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("These look like they’re from the same day or occasion, even if they were scanned at different times.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(matches, id: \.self) { id in
                            VStack(spacing: 2) {
                                AssetThumbnail(assetID: id, side: 72, cornerRadius: 6)
                                Text(state.effectiveEstimate(id)?.displayString ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 72)
                        }
                    }
                }
            }
        }
        .sheet(item: _editing.projectedValue) { draft in
            EventEditor(seed: draft.ids)
        }
    }
}
