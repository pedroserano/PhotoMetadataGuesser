import AppKit
import SwiftUI
import DateGuessCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ScanSettingsView()
                .tabItem { Label("Scanning", systemImage: "magnifyingglass") }
        }
        .frame(width: 560, height: 560)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var state
    var _confirmReset = State<Bool>(initialValue: false)
    private var confirmReset: Bool { get { _confirmReset.wrappedValue } nonmutating set { _confirmReset.wrappedValue = newValue } }

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Apple Intelligence") {
                Toggle("Use Apple Intelligence to spot seasons and occasions", isOn: Binding(
                    get: { state.settings.useAppleIntelligence != false },
                    set: { state.settings.useAppleIntelligence = $0 ? nil : false }))
                    .disabled(!OnDeviceModel.isAvailable)
                Text(OnDeviceModel.isAvailable
                     ? "Runs on this Mac; nothing is sent anywhere. It looks for snow, leaves, holiday decorations and occasions like Christmas or a beach day. It’s slower (a few seconds per photo) and only a gentle hint, so it never decides the year."
                     : "Needs macOS 27 or later with Apple Intelligence turned on in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("People") {
                Toggle("Save birthdays I enter to the person’s Contacts card", isOn: Binding(
                    get: { state.settings.writeBirthdaysToContacts == true },
                    set: { state.settings.writeBirthdaysToContacts = $0 ? true : nil }))
                Text("Only for people Photos has linked to a contact. The year you type replaces the card’s year; the card’s month and day are kept unless you enter them. Contacts needs a month and day to store a birthday.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dates") {
                HStack {
                    Text("No photos before")
                    NumberField(title: "Any year", value: Binding(
                        get: { state.settings.earliestYear },
                        set: { state.settings.earliestYear = $0 }),
                        range: YearBounds.earliestPhotoYear...YearBounds.currentYear(), width: 80)
                    if state.settings.earliestYear != nil {
                        Button("Clear") { state.settings.earliestYear = nil }
                    }
                }
                Text("If you know your oldest photo is from, say, 1940, enter that year and nothing will be guessed earlier. Leave it empty if you’re not sure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Use the exact month when a clear date or holiday is found", isOn: $state.settings.allowExactMonth)
                Text("Otherwise each guess uses the season’s month: January (winter), March (spring), June (summer) or September (fall). Dates are set to noon on the 1st (or the exact day, when a full date is found).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                HStack {
                    Button("Show Data Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([JSONStore.shared.directory])
                    }
                    Button("Clear All Estimates…", role: .destructive) { confirmReset = true }
                }
                Text("Scan results, groups, people, estimates and the undo history are stored on this Mac only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Clear all estimates?", isPresented: _confirmReset.projectedValue) {
            Button("Clear", role: .destructive) {
                state.analyses = [:]
                state.saveAnalysesNow()
                state.recomputeEstimates()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your groups, people and history are kept. Guesses are made again in the background.")
        }
    }
}
