import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var onWillTerminate: (() -> Void)?
    static var onReopen: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppDelegate.onReopen?()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.onWillTerminate?()
    }
}

@main
struct DiscordStatusModifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Profile") {
                    model.beginNewProfile()
                    if !NSApp.windows.contains(where: { $0.canBecomeMain && $0.isVisible }) {
                        AppDelegate.onReopen?()
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        MenuBarExtra("Discord Status Modifier", systemImage: "gamecontroller.fill") {
            MenuBarView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.menu)
    }
}
