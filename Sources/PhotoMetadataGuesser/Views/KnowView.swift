import SwiftUI
import DateGuessCore

/// Step 2: everything the user knows that the photos can't tell us. People come first, because
/// groups (and single photos) refer to them.
struct KnowView: View {
    @Environment(AppState.self) private var state
    var goNext: () -> Void
    var _tab = State<Tab>(initialValue: .people)
    private var tab: Tab { get { _tab.wrappedValue } nonmutating set { _tab.wrappedValue = newValue } }

    enum Tab: String, CaseIterable, Identifiable {
        case people = "People"
        case groups = "Groups"
        case cameras = "Cameras"
        var id: String { rawValue }
    }

    private var subtitle: String {
        switch tab {
        case .people: return "Who’s in your photos, and when were they born?"
        case .groups: return "Photos that go together, and what you remember about them."
        case .cameras: return "When you used each camera."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Picker("", selection: _tab.projectedValue) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Done", action: goNext)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            switch tab {
            case .people: PeopleView()
            case .groups: GroupsView()
            case .cameras: CamerasView()
            }
        }
    }
}
