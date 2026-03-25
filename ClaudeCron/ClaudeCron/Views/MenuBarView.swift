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
                sendNotification(title: "CLI Uninstalled", body: "ccron has been removed from /usr/local/bin")
            } else {
                try CLIInstallService.install()
                cliInstalled = true
                sendNotification(title: "CLI Installed", body: "ccron is now available in your terminal")
            }
        } catch {
            let command = cliInstalled
                ? CLIInstallService.manualUninstallCommand
                : CLIInstallService.manualInstallCommand
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            sendNotification(title: "CLI Install Failed", body: "Run manually: \(command) (copied to clipboard)")
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
