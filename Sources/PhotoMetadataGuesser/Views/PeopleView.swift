import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DateGuessCore

/// One list of everyone, edited in place. The people who appear in the most undated photos come
/// first, so filling in the top few birth years helps the most.
struct PeopleView: View {
    @Environment(AppState.self) private var state
    var _search = State<String>(initialValue: "")
    private var search: String { get { _search.wrappedValue } nonmutating set { _search.wrappedValue = newValue } }
    var _onlyMissing = State<Bool>(initialValue: false)
    private var onlyMissing: Bool { get { _onlyMissing.wrappedValue } nonmutating set { _onlyMissing.wrappedValue = newValue } }

    struct Counts { var tagged = 0; var undated = 0 }

    var body: some View {
        let counts = personCounts
        let rows = visiblePeople(counts)
        VStack(alignment: .leading, spacing: 0) {
            toolbar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            if state.taggedPeople.isEmpty { importCard.padding(.horizontal, 20).padding(.bottom, 12) }
            Divider()
            if state.people.isEmpty {
                ContentUnavailableView("No people yet", systemImage: "person.2",
                                       description: Text("Name people in Photos, then import them here."))
            } else {
                summary(counts)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { person in
                            PersonRow(personID: person.id, counts: counts[person.id] ?? Counts())
                            Divider().padding(.leading, 64)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .overlay {
                    if rows.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Search people", text: _search.projectedValue)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Toggle("Missing birth year", isOn: _onlyMissing.projectedValue)
                .toggleStyle(.checkbox)
            Spacer(minLength: 8)
            if canAskContacts {
                Button {
                    Task { await state.fillBirthdaysFromContacts() }
                } label: {
                    Label("Birthdays from Contacts", systemImage: "person.crop.circle.badge.clock")
                }
                .help("Fill in missing birth years from the contact cards your Photos people are linked to")
            }
            Menu {
                Button("Choose a Different Library…") { chooseLibrary() }
            } label: {
                Label(state.taggedPeople.isEmpty ? "Import from Photos" : "Update from Photos",
                      systemImage: "person.crop.rectangle.stack")
            } primaryAction: {
                importPeople()
            }
            .fixedSize()
            .disabled(state.isImportingPeople)
        }
    }

    private var canAskContacts: Bool {
        let linked = Set(state.taggedPeople.filter { $0.contactID != nil || $0.contactMatch != nil }.map(\.id))
        return state.people.contains { $0.birthYear == nil && $0.photosPersonID.map(linked.contains) == true }
    }

    private var importCard: some View {
        Card {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Already named people in Photos?").font(.headline)
                    Text("Bring them in with the photos they’re tagged in. Then add a birth year, and every tagged photo of them gets a “not before they were born” limit.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if state.isImportingPeople {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Import from Photos") { importPeople() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func summary(_ counts: [UUID: Counts]) -> some View {
        let withYear = state.people.filter { $0.birthYear != nil }.count
        let waiting = state.people.filter { $0.birthYear == nil }.reduce(0) { $0 + (counts[$1.id]?.undated ?? 0) }
        return HStack(spacing: 6) {
            Text("\(state.people.count) people · \(withYear) with a birth year")
            if waiting > 0 {
                Text("· adding the missing ones would help with up to \(waiting.formatted()) undated photos")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// Tagged and undated photo counts per person (tags from Photos plus photos the user marked).
    private var personCounts: [UUID: Counts] {
        var out: [UUID: Counts] = [:]
        let tagged = state.taggedAssetsByPerson
        for (id, assets) in tagged {
            out[id] = Counts(tagged: assets.count, undated: assets.filter { state.scan.undated[$0] != nil }.count)
        }
        for (asset, hints) in state.photoPeople where state.scan.undated[asset] != nil {
            for h in hints where !(tagged[h.personID]?.contains(asset) ?? false) {
                out[h.personID, default: Counts()].undated += 1
                out[h.personID, default: Counts()].tagged += 1
            }
        }
        return out
    }

    private func visiblePeople(_ counts: [UUID: Counts]) -> [PersonInfo] {
        state.people
            .filter { p in
                (search.isEmpty || p.name.localizedCaseInsensitiveContains(search)) && (!onlyMissing || p.birthYear == nil)
            }
            .sorted { a, b in
                let ua = counts[a.id]?.undated ?? 0, ub = counts[b.id]?.undated ?? 0
                if ua != ub { return ua > ub }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    /// Uses the library chosen before; asks only the first time (or if it moved).
    private func importPeople() {
        if let url = state.savedLibraryURL, FileManager.default.fileExists(atPath: url.path) {
            state.importTaggedPeople(from: url)
        } else {
            chooseLibrary()
        }
    }

    private func chooseLibrary() { LibraryPicker.choose(state) }
}

/// Asks for the Photos library file, which the sandbox requires once before the app may read names
/// from it. The choice is remembered.
@MainActor
enum LibraryPicker {
    static func choose(_ state: AppState) {
        let panel = NSOpenPanel()
        panel.message = "Choose your Photos library (the file ending in “.photoslibrary”). You only do this once; it’s only read, never changed."
        panel.prompt = "Use This Library"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        if let type = UTType("com.apple.photos.library") { panel.allowedContentTypes = [type] }
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.importTaggedPeople(from: url)
    }
}

/// One person, editable in place: name, birth year and month, and how much they're helping.
struct PersonRow: View {
    @Environment(AppState.self) private var state
    var personID: UUID
    var counts: PeopleView.Counts

    private var person: Binding<PersonInfo>? {
        guard let current = state.people.first(where: { $0.id == personID }) else { return nil }
        let state = self.state, id = personID
        return Binding(
            get: { state.people.first { $0.id == id } ?? current },
            set: { new in
                if let i = state.people.firstIndex(where: { $0.id == id }), state.people[i] != new { state.people[i] = new }
            })
    }

    var body: some View {
        if let person {
            HStack(spacing: 12) {
                avatar(person.wrappedValue)
                VStack(alignment: .leading, spacing: 2) {
                    if person.wrappedValue.photosPersonID == nil {
                        // Added by hand in an earlier version of the app.
                        TextField("Name", text: person.name, prompt: Text("Name"))
                            .textFieldStyle(.plain)
                            .font(.body.weight(.medium))
                    } else {
                        Text(person.wrappedValue.name)
                            .font(.body.weight(.medium))
                            .help("Rename in Photos; the new name shows up here when you come back")
                    }
                    Text(detail(person.wrappedValue))
                        .font(.caption)
                        .foregroundStyle(person.wrappedValue.birthYear == nil && counts.undated > 0 ? .orange : .secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                Text("Born").foregroundStyle(.secondary)
                NumberField(title: "Year", value: Binding(
                    get: { person.wrappedValue.birthYear },
                    set: { year in state.updateBirthday(personID) { $0.birthYear = year } }),
                    range: 1850...YearBounds.currentYear(), width: 64)
                    .help(person.wrappedValue.birthdayFromContacts == true ? "From their Contacts card" : "")
                Picker("Month", selection: Binding(
                    get: { person.wrappedValue.birthMonth },
                    set: { month in state.updateBirthday(personID) { $0.birthMonth = month; if month == nil { $0.birthDay = nil } } })) {
                    Text("Month?").tag(Int?.none)
                    ForEach(1...12, id: \.self) { m in
                        Text(DateEstimate.monthNames[m - 1]).tag(Int?.some(m))
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                Picker("Day", selection: Binding(
                    get: { person.wrappedValue.birthDay },
                    set: { day in state.updateBirthday(personID) { $0.birthDay = day } })) {
                    Text("Day?").tag(Int?.none)
                    ForEach(1...31, id: \.self) { d in Text("\(d)").tag(Int?.some(d)) }
                }
                .labelsHidden()
                .frame(width: 70)
                .disabled(person.wrappedValue.birthMonth == nil)
                Button(role: .destructive) {
                    state.removePerson(personID)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(person.wrappedValue.photosPersonID == nil ? "Remove" : "Remove (Update from Photos brings them back)")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func avatar(_ p: PersonInfo) -> some View {
        Group {
            if let ref = p.referenceAssetIDs.first {
                AssetThumbnail(assetID: ref, side: 36, cornerRadius: 18)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.blush)
            }
        }
        .frame(width: 36, height: 36)
    }

    private func detail(_ p: PersonInfo) -> String {
        var parts: [String] = []
        if p.birthdayFromContacts == true { parts.append("birthday from Contacts") }
        if p.photosPersonID != nil { parts.append("in \(counts.tagged.formatted()) photos") }
        if counts.undated > 0 { parts.append("\(counts.undated.formatted()) undated") }
        if p.birthYear == nil && counts.undated > 0 { parts.append("add a birth year to use") }
        if parts.isEmpty { return p.photosPersonID == nil ? "Not in Photos: name them there to link their photos" : "No undated photos" }
        return parts.joined(separator: " · ")
    }
}
