# Planador

A native macOS day planner for software engineers. Keep tasks in a backlog, choose what to do today, focus with a timer and task notes, then review completed work and focused time.

## Requirements

- macOS 14 or later
- Xcode 27 or later to build from source

## Build and run

Open `Planador.xcodeproj` in Xcode and run the **Planador** scheme. The project has no third-party dependencies.

For a release build from the command line:

```sh
xcodebuild -project Planador.xcodeproj -scheme Planador -configuration Release \
  -derivedDataPath DerivedData -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

The app is produced at `DerivedData/Build/Products/Release/Planador.app`. Builds from this repository are unsigned. Signing and notarization are required before distributing the app to other Macs.

## Tests

```sh
xcodebuild -project Planador.xcodeproj -scheme Planador -configuration Debug \
  -derivedDataPath DerivedData -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

## Data

Tasks, notes, timer state, and focus sessions are saved as JSON at `~/Library/Application Support/Planador/data.json`. The app keeps a copy if it finds a data file it cannot decode. No account or network service is used.

## Workflow

- **Plan:** Add and edit tasks, set estimates, move tasks between Today and Backlog, and reorder them from a task's context menu.
- **Focus:** Pick one task, start or pause a configurable focus timer, reset it, complete the task, and keep notes. Paused and completed intervals count toward the daily total.
- **Review:** See today's completions, unfinished tasks, and focused time. Send unfinished tasks to tomorrow or back to the backlog.

The illustration in the request informed the interface; it is not embedded in the app.
