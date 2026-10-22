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
        eventStore.calendars(for: .event).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func requestAccess() async throws -> Bool {
        let granted = try await eventStore.requestFullAccessToEvents()
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if granted && selectedCalendarIDs.isEmpty {
            selectedCalendarIDs = Set(calendars.map(\.calendarIdentifier))
        }
        return granted
    }

    func busyIntervals(from start: Date, to end: Date) -> [BusyInterval] {
        guard authorizationStatus == .fullAccess else { return [] }
        let selected = calendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: selected)
        return eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { BusyInterval(start: $0.startDate, end: $0.endDate) }
    }
}
