import AppKit
import SwiftUI

@main
struct PhotoMetadataGuesserApp: App {
    var _state = State<AppState>(initialValue: AppState())
    private var state: AppState { get { _state.wrappedValue } nonmutating set { _state.wrappedValue = newValue } }

    var body: some Scene {
        WindowGroup("Photo Date Guesser") {
            ContentView()
                .environment(state)
                .frame(minWidth: 1020, minHeight: 700)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    state.saveEverything()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    state.appBecameActive()
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts  /") {
                    NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
