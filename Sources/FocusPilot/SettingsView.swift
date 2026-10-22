import FocusPilotCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var notificationStatus = "Checking notification status…"

    var body: some View {
        Form {
            Section("General") {
                Toggle("Start FocusPilot at login", isOn: Binding(
                    get: { model.startAtLogin },
                    set: { model.setStartAtLogin($0) }
                ))
                if !model.startAtLogin {
                    Text("Enable Start at Login so approved tasks can auto-start on schedule after you sign in.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Working hours") {
                ForEach(Array(model.state.plannerSettings.workingHours.enumerated()), id: \.element.weekday) { index, hours in
                    WorkingHoursRow(model: model, index: index, hours: hours)
                }
            }

            Section("Notifications") {
                Stepper("Ask every \(model.state.notificationSettings.nagIntervalMinutes) minutes", value: nagBinding, in: 5...60, step: 5)
                Stepper("Break after \(model.state.notificationSettings.focusIntervalMinutes) focus minutes", value: focusBinding, in: 15...90, step: 5)
                Stepper("Break for \(model.state.notificationSettings.breakMinutes) minutes", value: breakBinding, in: 1...30)
                Text(notificationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Allow Notifications") {
                        Task {
                            await model.requestNotificationAccess()
                            await refreshNotificationStatus()
                        }
                    }
                    Button("Send Test Nag") {
                        Task {
                            await model.sendTestNotification()
                            await refreshNotificationStatus()
                        }
                    }
                }
            }

            Section("Calendar") {
                Button("Allow Calendar Access") {
                    Task { await model.requestCalendarAccess() }
                }
                Text(model.calendarService.authorizationDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(model.calendarService.calendars, id: \.calendarIdentifier) { calendar in
                    Toggle(calendar.title, isOn: Binding(
                        get: { model.calendarService.selectedCalendarIDs.contains(calendar.calendarIdentifier) },
                        set: { selected in
                            if selected {
                                model.calendarService.selectedCalendarIDs.insert(calendar.calendarIdentifier)
                            } else {
                                model.calendarService.selectedCalendarIDs.remove(calendar.calendarIdentifier)
                            }
                            Task { await model.refreshPlan() }
                        }
                    ))
                }
            }

            Section("Privacy") {
                Toggle("Hide task titles in widgets", isOn: $model.hideWidgetTitles)
            }

            Section("Widgets") {
                Text(model.widgetSyncStatus)
                    .foregroundStyle(model.widgetLastUpdated == nil ? .orange : .secondary)
                if let updated = model.widgetLastUpdated {
                    Text("Last updated \(updated.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Widgets require both targets to be signed by the same Apple Developer team with the FocusPilot App Group enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Encrypted Git vault") {
                HStack {
                    Button("Sync") { Task { await model.sync() } }
                    Button("Compact and Delete Older Files") { Task { await model.compact() } }
                }
                if let message = model.lastCompactionMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Button("Export Recovery Key…") { exportKey() }
            }
        }
        .formStyle(.grouped)
        .task { await refreshNotificationStatus() }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await model.notificationStatusDescription()
    }

    private var nagBinding: Binding<Int> {
        Binding(
            get: { model.state.notificationSettings.nagIntervalMinutes },
            set: { value in
                var settings = model.state.notificationSettings
                settings.nagIntervalMinutes = value
                Task { await model.updateNotificationSettings(settings) }
            }
        )
    }

    private var focusBinding: Binding<Int> {
        Binding(
            get: { model.state.notificationSettings.focusIntervalMinutes },
            set: { value in
                var settings = model.state.notificationSettings
                settings.focusIntervalMinutes = value
                Task { await model.updateNotificationSettings(settings) }
            }
        )
    }

    private var breakBinding: Binding<Int> {
        Binding(
            get: { model.state.notificationSettings.breakMinutes },
            set: { value in
                var settings = model.state.notificationSettings
                settings.breakMinutes = value
                Task { await model.updateNotificationSettings(settings) }
            }
        )
    }

    private func exportKey() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "focuspilot-recovery-key.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportRecoveryKey(to: url)
    }
}

private struct WorkingHoursRow: View {
    @ObservedObject var model: AppModel
    let index: Int
    let hours: DailyWorkingHours

    var body: some View {
        HStack {
            Toggle(hours.weekday.shortName, isOn: enabledBinding)
                .frame(width: 80, alignment: .leading)
            DatePicker("Start", selection: startBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .disabled(!hours.isEnabled)
            Text("to").foregroundStyle(.secondary)
            DatePicker("End", selection: endBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .disabled(!hours.isEnabled)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { hours.isEnabled }, set: { update(isEnabled: $0) })
    }

    private var startBinding: Binding<Date> {
        Binding(get: { date(for: hours.startMinute) }, set: { update(startMinute: minute(of: $0)) })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { date(for: hours.endMinute) }, set: { update(endMinute: minute(of: $0)) })
    }

    private func update(isEnabled: Bool? = nil, startMinute: Int? = nil, endMinute: Int? = nil) {
        var settings = model.state.plannerSettings
        guard settings.workingHours.indices.contains(index) else { return }
        if let isEnabled { settings.workingHours[index].isEnabled = isEnabled }
        if let startMinute { settings.workingHours[index].startMinute = startMinute }
        if let endMinute { settings.workingHours[index].endMinute = endMinute }
        Task { await model.updatePlannerSettings(settings) }
    }

    private func date(for minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
    }

    private func minute(of date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }
}
