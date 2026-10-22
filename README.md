# FocusPilot

FocusPilot is a native macOS 15+ menu-bar task planner built to keep the work you intended to do visible, concrete, and difficult to forget. It combines hierarchical tasks, Calendar-aware planning, focus reminders, deliberate breaks, encrypted JSON storage, and automatic Git history.

FocusPilot is productivity software, not a diagnostic or medical tool.

## Features

### Menu-bar workflow

- Capture a task without leaving the app you are using.
- See every currently running approved task and its individual remaining focus time.
- Pause, resume, and stop overlapping tasks independently from the menu bar.
- See the next scheduled task when no focus session is active.
- Launch automatically when you sign in to macOS.

### Tasks and projects

- Create an arbitrarily deep hierarchy of tasks and subtasks.
- Complete parent and child checkboxes independently.
- Reparent children safely when deleting a parent task.
- Add notes, priorities, active-time estimates, deadlines, and recurrence.
- Repeat tasks daily or on weekdays.
- Assign a persistent weekly hour target to long-running work.
- Record focus sessions and completed active minutes.

### Calendar-aware planning

- Read busy intervals from user-selected Apple Calendar sources using EventKit.
- Keep Calendar access read-only; FocusPilot never edits Calendar events.
- Show timed and all-day Calendar events as individually approvable suggestions.
- Keep approved Calendar blocks synchronized with renamed, moved, and deleted source events.
- Generate a rolling seven-day plan inside configurable working hours.
- Avoid Calendar events and already approved task blocks.
- Prioritize urgent work, deadlines, and outstanding weekly commitments.
- Suggest one high-priority deep-thinking block of at least two active hours per workday when feasible.
- Automatically approve every schedulable block for tasks you create directly.
- Require explicit approval for deep-thinking and other remaining suggestions.
- Show tasks that could not fit into the available week.
- Include planned five-minute breaks when calculating wall-clock block lengths.
- Edit the start and end times of approved task and deep-thinking blocks.
- Automatically start every due approved block, including overlaps, while FocusPilot is running.

### Focus and break reminders

- Run multiple independent active-time countdowns at once.
- Send one combined Time Sensitive reminder for all active tasks every 15 focus minutes by default.
- Keep the reminder interval configurable from 5 to 60 minutes.
- Pause all running clocks on one shared five-minute break after 30 wall-clock focus minutes by default.
- Configure focus intervals and break lengths independently.
- Suppress task nags during breaks and resume the same task afterward.
- Present reminders even while FocusPilot is in the foreground and report disabled notification permissions.

### Widgets

- Provide small and medium widgets for the macOS desktop and Notification Center.
- Show multiple running tasks, countdowns, finished count, unfinished count, and recent tasks.
- Hide task titles with a privacy setting.
- Share a platform-neutral widget projection suitable for a future iOS lock-screen widget.

macOS does not support third-party Mac lock-screen widgets. Lock-screen presentation will require the planned iOS app.

### Encrypted JSON vault

- Serialize app-owned domain data as versioned JSON.
- Encrypt each immutable operation independently with AES-256-GCM.
- Store the vault key in macOS Keychain.
- Export and import a JSON recovery-key file for future devices.
- Keep Calendar contents, authorization state, and operating-system secrets out of the repository.
- Resolve duplicate and concurrent operations deterministically.
- Bootstrap new clients from an encrypted snapshot plus subsequent operations.

### Git history and cleanup

- Create or open a separate Git repository for personal vault data.
- Save encrypted operations immediately, then group nearby edits into a commit after 30 quiet seconds.
- Use existing Git credential helpers when an origin is configured.
- Fetch, rebase, reload remote encrypted operations, and push from the app.
- Automatically compact at 500 operation files or 10 MB, or compact manually from Settings.
- Create, commit, decrypt, and verify a full snapshot before deleting anything.
- Delete covered operation files and superseded snapshots from the latest branch only after verification.
- Preserve deleted files in ordinary Git history for audit and recovery.
- Refuse compaction when unrelated changes or Git conflicts make cleanup unsafe.

### Future web and mobile synchronization

- Include stable envelope and manifest JSON schemas.
- Document a Netlify-compatible encrypted read contract.
- Keep encryption keys exclusively on user devices.
- Reserve authenticated Netlify Functions or a Git-provider API for future writes because static hosting is read-only.

## Requirements

- macOS 15 or newer
- Xcode 16.4 or newer
- Git, included with Xcode Command Line Tools
- XcodeGen 2.46 or newer when regenerating the project
- An Apple Developer signing identity only for Developer ID distribution and notarization

## Install for local use

1. Clone or download this repository.
2. Install XcodeGen if it is not installed:

   ```sh
   brew install xcodegen
   ```

3. Regenerate the Xcode project after changing `project.yml`:

   ```sh
   xcodegen generate
   ```

4. Open `FocusPilot.xcodeproj` in Xcode.
5. Select the `FocusPilot` scheme and the `My Mac` destination.
6. Press **Run**.
7. Approve notification and Calendar access when requested.
8. Choose an empty folder for the separate encrypted vault repository.
9. Export the recovery key from Settings and store it somewhere outside both repositories.

The checked-in project keeps Xcode signing disabled because restricted capabilities require an Apple provisioning profile. The included local build script signs the finished app and widget ad hoc after compilation, using a local entitlement set that omits the restricted Time Sensitive capability so the app can run without an Apple Developer certificate. The app still requests and marks Time Sensitive alerts through UserNotifications; a Developer-signed build is required for guaranteed Focus-mode bypass behavior.

## Install the built app

Build and ad-hoc sign the local application from Terminal:

```sh
./scripts/build-local.sh
```

Then copy the app into Applications and launch it:

```sh
ditto .build/XcodeDerivedData/Build/Products/Release/FocusPilot.app /Applications/FocusPilot.app
open /Applications/FocusPilot.app
```

The first launch may require Control-clicking the app and choosing **Open** because an ad-hoc signed app is not notarized.

To add the widget, Control-click the macOS desktop, choose **Edit Widgets**, search for **FocusPilot**, and add the small or medium widget. The same widget is available in Notification Center.

## Developer ID distribution

To distribute the app to other Macs without the local security warning:

1. Join the Apple Developer Program and install a `Developer ID Application` certificate in Keychain.
2. In Xcode, select both `FocusPilotApp` and `FocusPilotWidget`.
3. Under **Signing & Capabilities**, choose your team and enable automatic signing.
4. Change `CODE_SIGNING_ALLOWED` to `YES`, add your `DEVELOPMENT_TEAM` to both targets in `project.yml`, and regenerate the project.
5. Archive the `FocusPilot` scheme, export a Developer ID application, and submit it to Apple for notarization.

The current machine has no valid Apple signing identity, so this repository can produce a locally signed build but cannot create a Developer ID-signed or notarized release until a certificate is installed.

## Command-line development

The application and shared packages can also be built and tested without generating the Xcode project:

```sh
swift test --disable-sandbox
swift run --disable-sandbox FocusPilot
```

Swift Package Manager does not package the WidgetKit extension or permission descriptions. Use the Xcode project for normal app usage.

## Vault safety

- Never commit the exported recovery-key file.
- Losing every copy of the recovery key makes the encrypted vault unrecoverable.
- Normal compaction does not erase Git history. Restore an older commit if a deleted operation or snapshot is needed.
- A static Netlify deployment exposes encrypted envelopes and repository metadata; it never receives plaintext or the recovery key.

## Repository structure

- `Sources/FocusPilot`: macOS application and user interface
- `Sources/FocusPilotCore`: shared JSON domain model and deterministic reducer
- `Sources/FocusPilotPlanner`: seven-day scheduling engine
- `Sources/FocusPilotVault`: encryption, Keychain, Git, snapshots, and compaction
- `FocusPilotWidget`: WidgetKit extension
- `Schemas`: portable JSON schemas
- `docs/sync-contract.md`: future Netlify/mobile synchronization contract
- `Tests`: domain, planner, encryption, compaction, and multi-clone Git sync tests

## License

FocusPilot is available under the MIT License. See `LICENSE`.
