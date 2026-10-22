@preconcurrency import EventKit
import Foundation
import FocusPilotPlanner

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var selectedCalendarIDs = Set<String>() {
        didSet { UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: "selectedCalendarIDs") }
    }

    private let eventStore = EKEventStore()

    init() {
        selectedCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: "selectedCalendarIDs") ?? [])
    }

    var calendars: [EKCalendar] {
        guard hasFullAccess else { return [] }
        return eventStore.calendars(for: .event).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    var authorizationDescription: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Calendar access has not been requested."
        case .restricted:
            return "Calendar access is restricted by macOS."
        case .denied:
            return "Calendar access is denied. Enable it in System Settings → Privacy & Security → Calendars."
        case .fullAccess:
            return "Calendar access is enabled."
        case .writeOnly:
            return "FocusPilot needs full calendar access to find free time."
        default:
            return "Calendar authorization status is unavailable."
        }
    }

    func requestAccess() async throws -> Bool {
        let granted = try await eventStore.requestFullAccessToEvents()
        refreshAuthorizationStatus()
        if granted && selectedCalendarIDs.isEmpty {
            selectedCalendarIDs = Set(calendars.map(\.calendarIdentifier))
        }
        return granted
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func busyIntervals(from start: Date, to end: Date) -> [BusyInterval] {
        guard hasFullAccess else { return [] }
        let selected = calendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: selected)
        return eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { BusyInterval(start: $0.startDate, end: $0.endDate) }
    }
}
