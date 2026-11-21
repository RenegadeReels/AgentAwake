import SwiftUI
import AppKit

@main
struct AgentAwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AwakeController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(controller)
        } label: {
            Image(systemName: controller.isHoldingAwake ? "sun.max.fill" : "moon.zzz")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Always hand sleep back to macOS when the app quits.
        AwakeController.shared.shutdown()
    }
}

struct MenuContent: View {
    @EnvironmentObject private var c: AwakeController

    var body: some View {
        Text(c.statusText)
        if let error = c.lastError {
            Text(error)
        }
        Divider()

        Toggle("Keep Mac Awake", isOn: $c.enabled)
            .keyboardShortcut("a")
        Toggle("Only Run When Connected to Power", isOn: $c.onlyOnPower)
        Toggle("Stay Awake With Lid Closed", isOn: $c.lidClosedMode)
        Toggle("Keep Display On", isOn: $c.keepDisplayOn)

        if c.lidClosedMode && !c.passwordFreeReady {
            Divider()
            Button("Finish Lid-Closed Setup (asks for your password once)…") {
                c.setUpLidMode()
            }
        }

        Divider()
        Toggle("Open at Login", isOn: $c.launchAtLogin)
        Divider()
        Button("Quit AgentAwake") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
