# Changelog

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
