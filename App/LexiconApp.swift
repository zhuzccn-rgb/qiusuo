import SwiftUI
import AppKit
import LexiconCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        state?.persistRecordingOnExit()
        return .terminateNow
    }
}

@main
struct LexiconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    private let statusItem = StatusItemController()

    var body: some Scene {
        WindowGroup(L10n.text("求索")) {
            ContentView()
                .environmentObject(state)
                .onAppear {
                    appDelegate.state = state
                    statusItem.attach(state)
                }
        }
        .defaultSize(width: 1040, height: 700)
        .defaultPosition(.center)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L10n.text("导入收件箱全部文件")) {
                    state.importAllInbox()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsPane()
                .environmentObject(state)
                .frame(width: 520, height: 560)
        }
    }
}
