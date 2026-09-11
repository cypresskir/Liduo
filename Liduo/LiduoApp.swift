import SwiftUI
import AppKit

@main struct LiduoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let controller = AppController.shared
    var body: some Scene {
        Window("Liduo", id: "effect") {
            SettingsView(model: controller.model, controller: controller)
                .frame(width: 840, height: 630)
                .onExitCommand { controller.stopDemo() }
        }
        .defaultSize(width: 840, height: 630)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Проверить обновления…") { controller.updater.checkForUpdates() }
                    .disabled(!controller.updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                SettingsMenuCommand()
            }
            CommandMenu("Эффект") {
                Button(controller.model.toggleActionTitle) {
                    controller.toggleEnabled()
                }.keyboardShortcut("b", modifiers: [.command, .option])
            }
        }
        Window("Общие настройки", id: "general") {
            GeneralSettingsView(model: controller.model, controller: controller)
                .frame(width: 500, height: 520)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        MenuBarExtra("Liduo", systemImage: controller.model.preferences.enabled ? "macbook" : "pause.circle") {
            MenuContent(model: controller.model, controller: controller)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct SettingsMenuCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Настройки Liduo…") {
            openWindow(id: "general"); NSApp.activate(ignoringOtherApps: true)
        }.keyboardShortcut(",", modifiers: .command)
    }
}

private struct MenuContent: View {
    @Bindable var model: AppModel
    let controller: AppController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Liduo · \(model.angle.map { "\(Int($0))°" } ?? "—")")
        Text(model.status)
        Divider()
        if !model.demoActive {
            Button("\(model.toggleActionTitle)  ⌘⌥B") { controller.toggleEnabled() }
        }
        Button("Настроить эффект…") {
            openWindow(id: "effect"); NSApp.activate(ignoringOtherApps: true)
        }
        Button("Общие настройки…") {
            openWindow(id: "general"); NSApp.activate(ignoringOtherApps: true)
        }
        Button(model.demoActive ? "Остановить демонстрацию  ⌘⌥B" : "Показать эффект") {
            if model.demoActive { controller.stopDemo() }
            else {
                openWindow(id: "effect"); NSApp.activate(ignoringOtherApps: true)
                controller.startDemo()
            }
        }.disabled(!model.permissionGranted)
        Divider()
        Button("Проверить обновления…") { controller.updater.checkForUpdates() }
            .disabled(!controller.updater.canCheckForUpdates)
        Button("Выйти из Liduo") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
