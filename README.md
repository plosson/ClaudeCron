# Claude Cron

A native macOS task scheduler for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Schedule prompts to run automatically via launchd — daily, weekly, monthly, or on a fixed interval.

Inspired by [Run Claude Run](https://runclauderun.com/).

## Requirements

- macOS 14.0+
- Xcode 16+
- [xcodegen](https://github.com/yonaskolb/XcodeGen)
- Claude Code CLI (`claude`) installed and available in your PATH

## Getting Started

Install xcodegen if you don't have it:

```bash
brew install xcodegen
```

Generate the Xcode project:

```bash
cd ClaudeCron
xcodegen generate
```

### Run from Xcode

```bash
open ClaudeCron.xcodeproj
```

Then press **Cmd+R** to build and run.

### Run from the command line

```bash
cd ClaudeCron
xcodebuild -scheme ClaudeCron -destination 'platform=macOS' -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/ClaudeCron-*/Build/Products/Debug/Claude\ Cron.app
```

## Running Tests

```bash
cd ClaudeCron
xcodebuild test -scheme ClaudeCron -destination 'platform=macOS' -only-testing:ClaudeCronTests
```

47 unit tests covering models, schedule calculation, plist generation, and session ID parsing.

## How It Works

Each task is a Claude Code prompt with a schedule. When a task is enabled, Claude Cron installs a launchd LaunchAgent plist in `~/Library/LaunchAgents/`. At the scheduled time, launchd launches the app in headless mode (`--run-task <UUID>`), which executes the Claude CLI and records the output.

### Features

- **Schedule types:** manual, daily, weekly, monthly, fixed interval
- **Claude models:** Opus, Sonnet, Haiku
- **Permission modes:** default, bypass, plan, accept edits
- **Session management:** new, resume, or fork existing sessions
- **Tool control:** allowed/disallowed tool lists per task
- **Notifications:** optional alerts on task start and completion
- **Menu bar:** quick access to tasks from the menu bar
- **Run history:** view output, raw JSON stream, and errors for each run

## Project Structure

```
ClaudeCron/
  project.yml              # xcodegen project spec
  ClaudeCron/
    ClaudeCronApp.swift     # App entry point + headless CLI mode
    Models/
      ClaudeTask.swift      # Task model (SwiftData)
      TaskRun.swift         # Run model (SwiftData)
      ScheduleType.swift    # Schedule enums and struct
    Services/
      ClaudeService.swift   # Spawns claude CLI process
      LaunchdService.swift  # Manages launchd plists
      ScheduleCalculator.swift  # Computes next run dates
    Views/
      ContentView.swift     # Main 3-column layout
      TaskListView.swift    # Sidebar task list
      TaskDetailView.swift  # Task info + runs list
      TaskFormView.swift    # Create/edit task form
      RunDetailView.swift   # Run output viewer
      SettingsView.swift    # App preferences
      MenuBarView.swift     # Menu bar dropdown
  ClaudeCronTests/          # Unit tests
App/
  Info.plist
  entitlements.plist
.github/workflows/
  build.yml                 # CI: build, sign, notarize, release
```

## CI / Release

Pushing a `v*` tag triggers the GitHub Actions workflow which builds, signs, notarizes, and publishes a DMG to GitHub Releases. See `.github/workflows/build.yml` for details.

## License

MIT
