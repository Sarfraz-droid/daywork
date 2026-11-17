import XCTest
@testable import Notch

final class StoreTests: XCTestCase {
    @MainActor func testClearingAndUndoPreserveTaskDetails() {
        let suite = "notch.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = Store(defaults: defaults)
        store.add("  First task  ")
        store.add("Second task")
        let second = store.tasks[0]
        store.edit(second, title: "Priority task", important: true)
        store.move(second, to: .done)
        store.clear(completedOnly: true)
        XCTAssertEqual(store.tasks.map(\.title), ["First task"])
        store.undo()
        XCTAssertEqual(store.tasks.count, 2)
        XCTAssertEqual(store.tasks[0].title, "Priority task")
        XCTAssertEqual(store.tasks[0].important, true)
        XCTAssertEqual(store.tasks[0].stage, .done)
        store.clear(completedOnly: false)
        XCTAssertTrue(store.tasks.isEmpty)
        store.undo()
        XCTAssertEqual(Store(defaults: defaults).tasks.count, 2)
        XCTAssertNil(store.previous)
    }

    @MainActor func testLegacyTasksLoadAndBlankInputIsIgnored() throws {
        let suite = "notch.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let legacy = "[{\"id\":\"\(id.uuidString)\",\"title\":\"Existing task\",\"stage\":\"In progress\",\"created\":0}]"
        defaults.set(Data(legacy.utf8), forKey: "notch.tasks.v1")
        let store = Store(defaults: defaults)
        XCTAssertEqual(store.tasks.first?.id, id)
        XCTAssertEqual(store.tasks.first?.stage, .doing)
        XCTAssertNotEqual(store.tasks.first?.important, true)
        store.add(" \n ")
        store.edit(store.tasks[0], title: " ", important: true)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks[0].title, "Existing task")
        XCTAssertNil(store.previous)
    }
}
