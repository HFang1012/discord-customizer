import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(model.connectionTitle) {}
            .disabled(true)

        if let active = model.profiles.first(where: { $0.id == model.activeProfileID }) {
            Button(active.listTitle) {}
                .disabled(true)
        } else {
            Button("No status") {}
                .disabled(true)
        }

        Button("Stop") { model.stop() }
            .disabled(model.activeProfileID == nil)

        Divider()

        if model.profiles.isEmpty {
            Button("No profiles") {}
                .disabled(true)
        } else {
            ForEach(model.profiles) { profile in
                Button {
                    model.select(profile)
                } label: {
                    if model.activeProfileID == profile.id {
                        Label(profile.listTitle, systemImage: "checkmark")
                    } else {
                        Text(profile.listTitle)
                    }
                }
            }
        }

        Divider()

        Button("New Profile") {
            showMainWindow()
            model.beginNewProfile()
        }

        Button("Open Discord Status Modifier") {
            showMainWindow()
        }

        Divider()

        Button("Quit Discord Status Modifier") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
        let visibleMain = NSApp.windows.contains { $0.canBecomeMain && $0.isVisible }
        if !visibleMain {
            openWindow(id: "main")
        }
    }
}
