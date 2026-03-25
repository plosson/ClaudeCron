import SwiftUI
import SwiftData
import AppKit
import UserNotifications

struct MenuBarView: View {
    @Query(sort: \ClaudeTask.createdAt) private var tasks: [ClaudeTask]
    @EnvironmentObject private var updateService: UpdateService
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
        Button("Check for Updates...") {
            updateService.checkForUpdates()
        }
        .disabled(!updateService.canCheckForUpdates)
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
                showAlert(title: "CLI Uninstalled", message: "ccron has been removed")
            } else {
                try CLIInstallService.install()
                cliInstalled = true
                showAlert(title: "CLI Installed", message: "ccron is now available in your terminal.\nRestart your terminal if this is the first install.")
            }
        } catch {
            let command = cliInstalled
                ? CLIInstallService.manualUninstallCommand
                : CLIInstallService.manualInstallCommand
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            showAlert(
                title: "Permission Required",
                message: "Run this command in your terminal (copied to clipboard):\n\n\(command)",
                style: .warning
            )
        }
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style = .informational) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
