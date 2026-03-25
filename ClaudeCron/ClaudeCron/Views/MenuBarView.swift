import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Query(sort: \ClaudeTask.createdAt) private var tasks: [ClaudeTask]

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
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
