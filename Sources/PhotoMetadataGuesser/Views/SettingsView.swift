import AppKit
import SwiftUI
import DateGuessCore

struct SettingsView: View {
    @Environment(AppState.self) private var state
    var _keyDraft = State<String>(initialValue: "")
    private var keyDraft: String { get { _keyDraft.wrappedValue } nonmutating set { _keyDraft.wrappedValue = newValue } }
    var _confirmReset = State<Bool>(initialValue: false)
    private var confirmReset: Bool { get { _confirmReset.wrappedValue } nonmutating set { _confirmReset.wrappedValue = newValue } }

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Claude visual analysis") {
                Text("Optional. With a key, Review & Apply shows an “Ask Claude to Look Closer” button. Nothing is sent until you click it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    SecureField("Anthropic API key", text: _keyDraft.projectedValue, prompt: Text(state.hasAPIKey ? "Saved in your Keychain" : "sk-ant-…"))
                    Button("Save") {
                        state.saveAPIKey(keyDraft)
                        keyDraft = ""
                    }
                    .disabled(keyDraft.isEmpty)
                    if state.hasAPIKey {
                        Button("Remove", role: .destructive) { state.saveAPIKey("") }
                    }
                }
                Link("Get an API key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
                Picker("Model", selection: $state.settings.ai.model) {
                    ForEach(AIModelOption.all) { option in
                        Text("\(option.name) — \(option.blurb)").tag(option.id)
                    }
                }
                Picker("Thoroughness", selection: $state.settings.ai.effort) {
                    Text("Quick").tag("low")
                    Text("Balanced").tag("medium")
                    Text("Thorough").tag("high")
                }
                Picker("Image detail", selection: $state.settings.ai.imageMaxEdge) {
                    Text("Standard (768 px)").tag(768)
                    Text("High (1024 px)").tag(1024)
                    Text("Very high (1568 px)").tag(1568)
                }
                Stepper("Photos per request: \(state.settings.ai.photosPerRequest)", value: $state.settings.ai.photosPerRequest, in: 1...10)
                Stepper("Requests at once: \(state.settings.ai.concurrentRequests)", value: $state.settings.ai.concurrentRequests, in: 1...8)
                Text("Higher detail and thoroughness are more accurate but cost more. Larger batches are cheaper per photo; grouped photos are always sent together.")
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
        .frame(width: 560)
        .padding(.vertical, 8)
        .alert("Clear all estimates?", isPresented: _confirmReset.projectedValue) {
            Button("Clear", role: .destructive) {
                state.analyses = [:]
                state.saveAnalysesNow()
                state.recomputeEstimates()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your groups, people and history are kept. You’ll need to run Estimate Dates again.")
        }
    }
}
