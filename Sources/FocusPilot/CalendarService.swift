@preconcurrency import EventKit
import Combine
import Foundation
import FocusPilotCore
import FocusPilotPlanner

struct CalendarEventSnapshot: Identifiable, Hashable {
    var id: String {
        let sourceID = reference.externalIdentifier ?? reference.eventIdentifier ?? "unknown"
        return "\(reference.calendarIdentifier)|\(sourceID)|\(reference.occurrenceStart.timeIntervalSince1970)"
    }

    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarTitle: String
    var reference: CalendarEventReference
}

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var revision = 0
    @Published var selectedCalendarIDs = Set<String>() {
        didSet { UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: "selectedCalendarIDs") }
    }

    private let eventStore = EKEventStore()
    private var eventStoreObserver: AnyCancellable?

    init() {
        selectedCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: "selectedCalendarIDs") ?? [])
        eventStoreObserver = NotificationCenter.default.publisher(
            for: .EKEventStoreChanged,
            object: eventStore
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.revision += 1
        }
    }

    var calendars: [EKCalendar] {
        guard hasFullAccess else { return [] }
        return eventStore.calendars(for: .event).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
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

    func events(from start: Date, to end: Date) -> [CalendarEventSnapshot] {
        guard hasFullAccess else { return [] }
        let selected = calendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: selected)
        return eventStore.events(matching: predicate)
            .map(snapshot)
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
    }

    func busyIntervals(from events: [CalendarEventSnapshot]) -> [BusyInterval] {
        events
            .filter { !$0.isAllDay }
            .map { BusyInterval(start: $0.start, end: $0.end) }
    }

    func match(
        reference: CalendarEventReference,
        in events: [CalendarEventSnapshot]
    ) -> CalendarEventSnapshot? {
        if let eventIdentifier = reference.eventIdentifier,
           let match = (events.filter { $0.reference.eventIdentifier == eventIdentifier })
            .min(by: {
                distance($0.start, reference.occurrenceStart) < distance($1.start, reference.occurrenceStart)
            }) {
            return match
        }

        guard let externalIdentifier = reference.externalIdentifier else { return nil }
        return events
            .filter {
                $0.reference.externalIdentifier == externalIdentifier
                    && $0.reference.calendarIdentifier == reference.calendarIdentifier
                    && distance($0.start, reference.occurrenceStart) < 60
            }
            .first
    }

    func representsSameOccurrence(
        reference: CalendarEventReference,
        event: CalendarEventSnapshot
    ) -> Bool {
        guard reference.calendarIdentifier == event.reference.calendarIdentifier,
              distance(reference.occurrenceStart, event.start) < 1 else { return false }
        if let externalIdentifier = reference.externalIdentifier {
            return externalIdentifier == event.reference.externalIdentifier
        }
        return reference.eventIdentifier == event.reference.eventIdentifier
    }

    func resolve(
        reference: CalendarEventReference,
        in events: [CalendarEventSnapshot]
    ) -> CalendarEventSnapshot? {
        if let match = match(reference: reference, in: events) {
            return match
        }
        guard let eventIdentifier = reference.eventIdentifier,
              let event = eventStore.event(withIdentifier: eventIdentifier),
              selectedCalendarIDs.contains(event.calendar.calendarIdentifier) else { return nil }
        return snapshot(event)
    }

    private func snapshot(_ event: EKEvent) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            title: event.title.isEmpty ? "Untitled calendar event" : event.title,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar.title,
            reference: CalendarEventReference(
                calendarIdentifier: event.calendar.calendarIdentifier,
                eventIdentifier: event.eventIdentifier,
                externalIdentifier: event.calendarItemExternalIdentifier,
                occurrenceStart: event.startDate
            )
        )
    }

    private func distance(_ lhs: Date, _ rhs: Date) -> TimeInterval {
        abs(lhs.timeIntervalSince(rhs))
    }
}
