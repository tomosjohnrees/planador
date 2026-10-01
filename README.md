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

- **Plan:** Add tasks inline in Today or Backlog, edit them, move them between lists, and reorder them from a task's context menu.
- **Focus:** Pick one task and start a focus session. At the end, a chime plays, the Dock icon asks for attention, and the timer stops on a clear pause screen. Click **Start break** when you are ready, or skip it. A second chime marks the end of the break; the next focus session waits for you to click Start. You can pause or reset a running timer and keep task notes. Only focus time counts toward the daily total.
- **Review:** See today's completions, unfinished tasks, and focused time. Expand notes inline on completed tasks, including work finished on earlier days. Send unfinished tasks to tomorrow or back to the backlog.

Set the default focus and break lengths in **Settings**. Changes take effect when the next timer starts. The app includes distinct focus and break completion chimes.

The illustration in the request informed the interface; it is not embedded in the app.
