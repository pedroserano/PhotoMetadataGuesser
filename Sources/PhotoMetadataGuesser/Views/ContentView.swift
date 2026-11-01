import SwiftUI
import DateGuessCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case scan, know, review, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scan: return "Find Undated Photos"
        case .know: return "What You Know"
        case .review: return "Review & Apply"
        case .history: return "History"
        }
    }

    var icon: String {
        switch self {
        case .scan: return "magnifyingglass"
        case .know: return "person.2"
        case .review: return "checkmark.circle"
        case .history: return "clock.arrow.circlepath"
        }
    }

    var step: Int? {
        switch self {
        case .scan: return 1
        case .know: return 2
        case .review: return 3
        case .history: return nil
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state
    var _selection = State<SidebarItem?>(initialValue: .scan)
    private var selection: SidebarItem? { get { _selection.wrappedValue } nonmutating set { _selection.wrappedValue = newValue } }
    var _columnVisibility = State<NavigationSplitViewVisibility>(initialValue: .all)
    private var columnVisibility: NavigationSplitViewVisibility { get { _columnVisibility.wrappedValue } nonmutating set { _columnVisibility.wrappedValue = newValue } }

    var body: some View {
        Group {
            if state.isAuthorized {
                NavigationSplitView(columnVisibility: _columnVisibility.projectedValue) {
                    sidebar
                } detail: {
                    detail
                        // A fixed minimum keeps any screen's content from forcing the sidebar
                        // to collapse (which left no way back to the other steps).
                        .frame(minWidth: Self.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .background(Theme.background)
                }
                .onChange(of: selection) { _, _ in columnVisibility = .all }
                .sheet(isPresented: Binding(
                    get: { state.needsLibrarySetup || state.needsContactsSetup },
                    set: { shown in
                        guard !shown else { return }
                        if state.needsLibrarySetup { state.settings.skippedLibrarySetup = true }
                        if state.needsContactsSetup { state.settings.skippedContactsSetup = true }
                    })) {
                    SetupView()
                }
            } else {
                WelcomeView()
            }
        }
        .overlay(alignment: .bottom) { BannerView() }
    }

    private var sidebar: some View {
        List(selection: _selection.projectedValue) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Photo Date Guesser")
                    .font(.headline)
                Text("Finding when your memories happened")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .selectionDisabled()

            Section("Steps") {
                ForEach(SidebarItem.allCases.filter { $0.step != nil }) { item in
                    NavigationLink(value: item) {
                        Label {
                            Text(item.title)
                        } icon: {
                            Image(systemName: item.icon)
                        }
                        .badge(badge(for: item))
                    }
                }
            }
            Section {
                NavigationLink(value: SidebarItem.history) {
                    Label(SidebarItem.history.title, systemImage: SidebarItem.history.icon)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240)
    }

    private func badge(for item: SidebarItem) -> Int {
        switch item {
        case .scan: return state.undatedSorted.count
        case .know: return state.people.count + state.groups.count
        case .review: return state.selectedForApply.count
        case .history: return 0
        }
    }

    static let detailMinWidth: CGFloat = 640

    /// Steps that only make sense after a scan.
    private func needsScan(_ item: SidebarItem) -> Bool {
        state.scan.lastScan == nil && item == .review
    }

    @ViewBuilder private var detail: some View {
        let item = selection ?? .scan
        if needsScan(item) {
            NeedsScanView(step: item, goToScan: { selection = .scan })
        } else {
            stepView(item)
        }
    }

    @ViewBuilder private func stepView(_ item: SidebarItem) -> some View {
        switch item {
        case .scan: ScanView(goNext: { selection = .review })
        case .know: KnowView(goNext: { selection = .review })
        case .review: ReviewView(goToKnow: { selection = .know })
        case .history: HistoryView()
        }
    }
}

/// Shown when a later step is opened before the library has been scanned.
struct NeedsScanView: View {
    var step: SidebarItem
    var goToScan: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: step.icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Let’s find your undated photos first")
                .font(.title.weight(.semibold))
            Text("“\(step.title)” works with the photos the scan finds. Start with step 1 — you can come back here any time.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button {
                goToScan()
            } label: {
                Label("Go to Step 1: Find Undated Photos", systemImage: "magnifyingglass")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WelcomeView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 160, height: 160)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            Text("Hi! Let’s find the dates of your old photos.")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Photo Date Guesser looks through your Photos library for pictures that don’t have a real date — like scanned prints — and makes a careful guess for each one. You review every guess before anything changes.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
            if state.authorization == .denied || state.authorization == .restricted {
                VStack(spacing: 8) {
                    Text("Photos access is turned off for this app.")
                        .font(.headline)
                    Text("Open System Settings ▸ Privacy & Security ▸ Photos and turn on Photo Date Guesser, then reopen the app.")
                        .foregroundStyle(.secondary)
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } else {
                Button {
                    Task { await state.requestAccess() }
                } label: {
                    Label("Allow Access to Photos", systemImage: "photo.on.rectangle.angled")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Text("Your photos stay in your library. Dates are changed only when you click Apply, and every change can be undone.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

struct BannerView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let text = state.banner {
            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .foregroundStyle(Theme.accent)
                Text(text)
                    .lineLimit(3)
                Button {
                    state.banner = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// First-run steps after Photos access: point the app at the library file once (for the names
/// you've tagged in Photos), then allow Contacts (for birthdays). Each step can be skipped.
struct SetupView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if state.needsLibrarySetup {
                libraryStep
            } else {
                contactsStep
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func header(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
    }

    private var libraryStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("person.crop.rectangle.stack", "Choose your Photos library",
                   "So the app can use the people you’ve named in Photos.")
            Text("Photos access lets the app see your pictures and dates, but not the names of the people in them. Those live in your library file, and macOS asks you to point to it once. It’s usually in your Pictures folder, or on the drive where you keep your library. It’s only read, never changed.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Not Now") { state.settings.skippedLibrarySetup = true }
                Spacer()
                Button {
                    LibraryPicker.choose(state)
                } label: {
                    Text("Choose Library…").padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            Text("You can also do this later from What You Know ▸ People ▸ Import from Photos.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var contactsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("person.crop.circle.badge.clock", "Use birthdays from Contacts",
                   "So you don’t have to type everyone’s birth year.")
            Text("When Photos has linked someone to a contact card, the app reads the birthday from it and works out how old they are in each photo. Contacts are only changed if you turn that on in Settings.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Not Now") { state.settings.skippedContactsSetup = true }
                Spacer()
                Button {
                    Task { await state.requestContactsAccess() }
                } label: {
                    Text("Allow Contacts…").padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            Text("You can also do this later from What You Know ▸ People ▸ Birthdays from Contacts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
