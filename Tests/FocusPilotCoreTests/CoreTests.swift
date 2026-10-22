import Foundation
import Testing
@testable import FocusPilotCore

@Test func modelsRoundTripAsJSON() throws {
    let task = TaskItem(title: "Write proposal", priority: .high, estimatedMinutes: 90)
    var state = AppState()
    state.tasks[task.id] = task

    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(AppState.self, from: data)

    #expect(decoded == state)
}

@Test func widgetProjectionStoreRoundTripsSharedJSON() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "FocusPilotWidgetProjectionTests-\(UUID().uuidString)")
    let url = directory.appending(path: WidgetProjectionStore.filename)
    defer { try? FileManager.default.removeItem(at: directory) }

    let generatedAt = Date(timeIntervalSince1970: 10_000)
    let projection = WidgetProjection(
        generatedAt: generatedAt,
        currentTitle: "Write proposal",
        currentEnd: generatedAt.addingTimeInterval(1_800),
        completedCount: 1,
        totalCount: 2,
        tasks: [
            WidgetTask(id: UUID(), title: "Write proposal", isCompleted: false),
            WidgetTask(id: UUID(), title: "Review notes", isCompleted: true)
        ],
        hideTitles: false,
        runningTasks: [
            WidgetRunningTask(
                id: UUID(),
                title: "Write proposal",
                projectedEnd: generatedAt.addingTimeInterval(1_800),
                isPaused: false
            )
        ]
    )

    try WidgetProjectionStore.write(projection, to: url)
    let decoded = try WidgetProjectionStore.read(from: url)

    #expect(decoded == projection)
}

@Test func calendarLinksAndLegacyOptionalFieldsDecode() throws {
    let start = Date(timeIntervalSince1970: 1_000)
    let reference = CalendarEventReference(
        calendarIdentifier: "calendar",
        eventIdentifier: "event",
        externalIdentifier: "external",
        occurrenceStart: start
    )
    let proposal = ProposedBlock(
        taskID: nil,
        title: "Calendar event",
        start: start,
        end: start.addingTimeInterval(3_600),
        activeMinutes: 60,
        kind: .calendarEvent,
        calendarEventReference: reference
    )
    let approved = ApprovedBlock(proposal: proposal)
    let session = FocusSession(
        taskID: nil,
        approvedBlockID: approved.id,
        title: approved.title
    )

    let approvedData = try JSONEncoder().encode(approved)
    let decodedApproved = try JSONDecoder().decode(ApprovedBlock.self, from: approvedData)
    #expect(decodedApproved.calendarEventReference == reference)

    var legacySessionObject = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any]
    )
    legacySessionObject.removeValue(forKey: "approvedBlockID")
    let legacySessionData = try JSONSerialization.data(withJSONObject: legacySessionObject)
    let decodedLegacySession = try JSONDecoder().decode(FocusSession.self, from: legacySessionData)
    #expect(decodedLegacySession.approvedBlockID == nil)
}

@Test func parentAndChildCompletionRemainIndependent() {
    let deviceID = UUID()
    let parent = TaskItem(title: "Parent", isCompleted: true)
    let child = TaskItem(parentID: parent.id, title: "Child", isCompleted: false)
    let operations = [
        VaultOperation(deviceID: deviceID, deviceSequence: 1, timestamp: .init(milliseconds: 1), mutation: .upsertTask(parent)),
        VaultOperation(deviceID: deviceID, deviceSequence: 2, timestamp: .init(milliseconds: 2), mutation: .upsertTask(child))
    ]

    let result = StateReducer.reduce(operations: operations)

    #expect(result.state.tasks[parent.id]?.isCompleted == true)
    #expect(result.state.tasks[child.id]?.isCompleted == false)
}

@Test func duplicateOperationsAreIdempotent() {
    let deviceID = UUID()
    let task = TaskItem(title: "One task")
    let operation = VaultOperation(
        deviceID: deviceID,
        deviceSequence: 1,
        timestamp: .init(milliseconds: 1),
        mutation: .upsertTask(task)
    )

    let result = StateReducer.reduce(operations: [operation, operation])

    #expect(result.state.tasks.count == 1)
    #expect(result.frontier[deviceID] == 1)
}
