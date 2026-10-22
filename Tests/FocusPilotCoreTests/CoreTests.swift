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
