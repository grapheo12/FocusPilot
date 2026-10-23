# Changelog

## Unreleased - 2026-10-22

### Added

- Split the Tasks pane into dedicated One-off Tasklist and Recurring Tasklist sections based on whether a task has a positive weekly commitment.
- Added live Monday-through-Sunday focused-time totals for recurring tasks, displayed against each task's configured weekly target.
- Added versioned task completion timestamps with backward-compatible decoding for existing encrypted vault operations and snapshots.
- Added reusable working-week and completed-task retention policies with coverage for Monday boundaries, local-midnight cleanup, and legacy task data.

### Changed

- Removed completion checkboxes from recurring tasks so persistent weekly work cannot be permanently completed by mistake.
- Promoted tasks to the root of their own section when their parent belongs to the other tasklist, while preserving the stored hierarchy relationship.
- Automatically revive completed one-off tasks when a positive weekly commitment converts them into recurring tasks.
- Stopped the planner from proposing additional recurring work after the current week's commitment has been met.
- Preserved historical focus sessions and completion records when deleting task records so tracked work history remains available.

### Fixed

- Automatically delete completed one-off tasks after the next local midnight, including cleanup after vault opening, synchronization, app activation, and wake.
- Reparent surviving descendants safely when completed parents are removed and clean up linked approved blocks and stale weekly commitments.
- Prevent overlapping maintenance runs from emitting duplicate deletion operations around midnight.
- Made the app and widget derive their shared App Group from the active Apple Developer team, allowing Personal Team provisioning profiles to sign both targets and share widget data correctly.

### Validation

- Added regression coverage for legacy JSON decoding, midnight retention, Monday-based weekly totals, live running-session totals, and fulfilled weekly commitments.
- Verified all Swift package tests, a clean signed Release build, embedded widget validation, installed-bundle signatures, single widget registration, and a successful launch from `/Applications`.

## 1.0.1 - 2026-10-22

### Fixed

- Made task Play buttons start a visibly updating countdown in the main window and menu bar.
- Added foreground notification presentation, permission diagnostics, test delivery, and Time Sensitive accountability nags.
- Automatically approved all current planner blocks for newly created tasks.
- Prevented approved task and deep-thinking blocks from reappearing as duplicate suggestions.
- Registered the WidgetKit extension correctly so FocusPilot appears in the macOS Add Widget gallery.
- Reloaded widget timelines after task and focus changes and replaced production preview data with an empty state.

## 1.0.0 - 2026-10-22

### Added

- Native macOS 15 SwiftUI application with a menu-bar workflow and full management window.
- Hierarchical tasks with independent checkboxes, priorities, notes, estimates, deadlines, recurrence, and weekly commitments.
- Read-only EventKit integration and a rolling seven-day planner that accounts for working hours, busy events, approved blocks, task urgency, weekly targets, and focus breaks.
- Approval-based deep-thinking proposals of at least two active hours per workday when feasible.
- Configurable focus reminders and automatic five-minute break cycles.
- Small and medium WidgetKit views for current work and daily progress.
- Versioned JSON domain models and deterministic event reduction for future multi-device clients.
- AES-256-GCM operation encryption, Keychain storage, and portable recovery-key export/import.
- App-owned vault repositories with immediate durable writes and debounced Git commits.
- Remote fetch/rebase/reload/push synchronization through existing Git credential helpers.
- Verified snapshot compaction with safe deletion of covered operation files and superseded snapshots from the current branch.
- JSON schemas and a documented encrypted Netlify/mobile synchronization contract.
- Unit and integration coverage for model serialization, hierarchy semantics, planning, encryption, compaction, retained Git history, and two-clone remote synchronization.
- XcodeGen project definition, application and widget entitlements, Calendar permission descriptions, and a reproducible local ad-hoc signing script.
- MIT License and complete installation, signing, recovery, and architecture documentation.
