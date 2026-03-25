import SwiftUI
import SwiftData
import AppKit
import UserNotifications

struct MenuBarView: View {
    @Query(sort: \ClaudeTask.createdAt) private var tasks: [ClaudeTask]
    @State private var cliInstalled = false

    var body: some View {
        ForEach(tasks) { task in
            Button("\(task.isEnabled ? "●" : "○") \(task.name)") {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        Divider()
        Button("Open Claude Cron") {
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button(cliInstalled
            ? "Uninstall Command Line Tool (ccron)"
            : "Install Command Line Tool (ccron)"
        ) {
            toggleCLIInstall()
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        .onAppear {
            cliInstalled = CLIInstallService.isInstalled
        }
    }

    private func toggleCLIInstall() {
        do {
            if cliInstalled {
                try CLIInstallService.uninstall()
                cliInstalled = false
            } else {
                try CLIInstallService.install()
                cliInstalled = true
            }
        } catch {
            let command = cliInstalled
                ? CLIInstallService.manualUninstallCommand
                : CLIInstallService.manualInstallCommand
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)

            let content = UNMutableNotificationContent()
            content.title = "CLI Install Failed"
            content.body = "Command copied to clipboard: \(command)"
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
