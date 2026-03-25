import SwiftUI
import SwiftData

@main
struct ClaudeCronApp: App {
    @State private var cliMode = false
    @State private var folderRegistry = FolderRegistry()

    static let sharedContainer: ModelContainer = {
        let schema = Schema([ClaudeTask.self, TaskRun.self])
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema changed — delete old store and retry
            let url = config.url
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
            return try! ModelContainer(for: schema, configurations: [config])
        }
    }()

    init() {
        let args = CommandLine.arguments
        let isCLI = args[0].hasSuffix("/\(CLIInstallService.cliName)")

        if isCLI && !CLIInstallService.validateAppBundle(symlinkAt: args[0]) {
            print("Claude Cron app not found. It may have been uninstalled.")
            print("To remove this CLI tool, run: rm \(args[0])")
            exit(1)
        }

        if isCLI {
            cliMode = true
            CLIHandler.run(container: Self.sharedContainer)
            // CLIHandler.run() calls exit(), so we never reach here
        }

        if args.contains("--run-task") {
            cliMode = true
            CLIHandler.run(container: Self.sharedContainer)
        }
    }

    var body: some Scene {
        WindowGroup {
            if !cliMode {
                ContentView()
                    .environment(folderRegistry)
            }
        }
        .modelContainer(Self.sharedContainer)

        MenuBarExtra("Claude Cron", image: "MenuBarIcon") {
            MenuBarView()
                .modelContainer(Self.sharedContainer)
                .environment(folderRegistry)
        }
    }
}
