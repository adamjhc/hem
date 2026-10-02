import XCTest

@testable import Hem

@MainActor
final class StoreTests: XCTestCase {
    private var folder: URL!

    private var stateURL: URL {
        folder.appendingPathComponent("state.json")
    }

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hem-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Loading

    func testLoadsSavedItems() throws {
        try writeState(
            """
            { "items": [
                { "id": "\(UUID())", "text": "one" },
                { "id": "\(UUID())", "text": "two", "completedAt": 1700000000 }
            ] }
            """)
        let store = Store(fileURL: stateURL)
        XCTAssertEqual(store.visibleItems.map(\.text), ["one"])
        XCTAssertEqual(store.completedItems.map(\.text), ["two"])
        XCTAssertEqual(store.completedItems[0].completedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testMigratesLegacyIsDone() throws {
        try writeState(
            """
            { "items": [
                { "id": "\(UUID())", "text": "open", "isDone": false },
                { "id": "\(UUID())", "text": "done", "isDone": true }
            ] }
            """)
        let store = Store(fileURL: stateURL)
        XCTAssertEqual(store.visibleItems.map(\.text), ["open"])
        XCTAssertEqual(store.completedItems.map(\.text), ["done"])
        XCTAssertNotNil(store.completedItems[0].completedAt)

        let saved = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertFalse(saved.contains("isDone"))
        XCTAssertEqual(Store(fileURL: stateURL).completedItems.map(\.text), ["done"])
    }

    func testMigratesISO8601CompletedAt() throws {
        try writeState(
            """
            { "items": [ { "id": "\(UUID())", "text" : "done", "completedAt" : "2023-11-14T22:13:20Z" } ] }
            """)
        let store = Store(fileURL: stateURL)
        XCTAssertEqual(store.completedItems[0].completedAt, Date(timeIntervalSince1970: 1_700_000_000))

        let saved = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertTrue(saved.contains("\"completedAt\" : 1700000000"))
    }

    func testLoadDropsEmptyRows() throws {
        try writeState(
            """
            { "items": [ { "id": "\(UUID())", "text": "  " }, { "id": "\(UUID())", "text": "keep" } ] }
            """)
        XCTAssertEqual(Store(fileURL: stateURL).visibleItems.map(\.text), ["keep"])
    }

    func testMissingFileStartsWithOneBlankRow() {
        let store = Store(fileURL: stateURL)
        XCTAssertEqual(store.visibleItems.map(\.text), [""])
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
    }

    func testUnreadableFileIsPreservedAndNotOverwritten() throws {
        let corrupt = "{ \"items\": [ { \"id\": \"not-a-uuid\", \"text\": \"precious\" } ] }"
        try writeState(corrupt)

        let store = Store(fileURL: stateURL)
        XCTAssertEqual(store.visibleItems.map(\.text), [""])

        store.setText("new", for: store.visibleItems[0].id)

        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix("state.unreadable-") }
        XCTAssertEqual(backups.count, 1)
        let preserved = try String(contentsOf: folder.appendingPathComponent(backups[0]), encoding: .utf8)
        XCTAssertEqual(preserved, corrupt)
        XCTAssertEqual(Store(fileURL: stateURL).visibleItems.map(\.text), ["new"])
    }

    // MARK: - Counting

    func testRealCountSkipsDividers() {
        let store = makeStore(["a", "---", " --- ", "b"])
        XCTAssertEqual(store.realCount, 2)
    }

    // MARK: - Reordering

    func testMoveUpAndDown() {
        let store = makeStore(["a", "b", "c"])
        store.moveUp(store.visibleItems[2].id)
        XCTAssertEqual(store.visibleItems.map(\.text), ["a", "c", "b"])
        store.moveDown(store.visibleItems[0].id)
        XCTAssertEqual(store.visibleItems.map(\.text), ["c", "a", "b"])
    }

    func testMoveUpAtTopAndDownAtBottomAreNoOps() {
        let store = makeStore(["a", "b"])
        store.moveUp(store.visibleItems[0].id)
        store.moveDown(store.visibleItems[1].id)
        XCTAssertEqual(store.visibleItems.map(\.text), ["a", "b"])
        XCTAssertFalse(store.undoManager.canUndo)
    }

    func testMoveSkipsCompletedRows() throws {
        try writeState(
            """
            { "items": [
                { "id": "\(UUID())", "text": "a" },
                { "id": "\(UUID())", "text": "done", "completedAt": 1700000000 },
                { "id": "\(UUID())", "text": "b" }
            ] }
            """)
        let store = Store(fileURL: stateURL)
        store.moveUp(store.visibleItems[1].id)
        XCTAssertEqual(store.visibleItems.map(\.text), ["b", "a"])
        XCTAssertEqual(store.completedItems.map(\.text), ["done"])
    }

    func testUndoMove() {
        let store = makeStore(["a", "b"])
        store.moveDown(store.visibleItems[0].id)
        store.undoManager.undo()
        XCTAssertEqual(store.visibleItems.map(\.text), ["a", "b"])
    }

    // MARK: - Delete

    func testDeleteFocusesNextRow() {
        let store = makeStore(["a", "b", "c"])
        let next = store.visibleItems[2].id
        store.delete(store.visibleItems[1].id)
        XCTAssertEqual(store.visibleItems.map(\.text), ["a", "c"])
        XCTAssertEqual(store.focusedID, next)
        XCTAssertEqual(store.pendingCaret, .end)
    }

    func testDeleteLastRowFocusesPrevious() {
        let store = makeStore(["a", "b"])
        let previous = store.visibleItems[0].id
        store.delete(store.visibleItems[1].id)
        XCTAssertEqual(store.focusedID, previous)
    }

    func testDeleteOnlyRowLeavesBlank() {
        let store = makeStore(["only"])
        store.delete(store.visibleItems[0].id)
        XCTAssertEqual(store.visibleItems.map(\.text), [""])
        XCTAssertEqual(store.focusedID, store.visibleItems[0].id)
    }

    func testDeleteOnlyBlankRowIsNoOp() {
        let store = makeStore([""])
        let id = store.visibleItems[0].id
        store.delete(id)
        XCTAssertEqual(store.visibleItems.map(\.id), [id])
        XCTAssertFalse(store.undoManager.canUndo)
    }

    func testUndoDelete() {
        let store = makeStore(["a", "b"])
        store.delete(store.visibleItems[0].id)
        store.undoManager.undo()
        XCTAssertEqual(store.visibleItems.map(\.text), ["a", "b"])
    }

    // MARK: - Compact

    func testCompactRemovesBlankRowsAndKeepsCompleted() {
        let store = makeStore(["a", "", "b", ""])
        store.checkOff(store.visibleItems[0].id)
        store.compact()
        XCTAssertEqual(store.visibleItems.map(\.text), ["b"])
        XCTAssertEqual(store.completedItems.map(\.text), ["a"])
    }

    func testCompactLeavesOneBlankWhenNothingIsLeft() {
        let store = makeStore(["", ""])
        store.compact()
        XCTAssertEqual(store.visibleItems.map(\.text), [""])
        XCTAssertEqual(store.focusedID, store.visibleItems[0].id)
    }

    func testCompactRefocusesWhenFocusedRowWasRemoved() {
        let store = makeStore(["a", ""])
        store.focusedID = store.visibleItems[1].id
        store.compact()
        XCTAssertEqual(store.focusedID, store.visibleItems[0].id)
    }

    func testCompactPersists() {
        let store = makeStore(["a", "", "b"])
        store.compact()
        XCTAssertEqual(Store(fileURL: stateURL).visibleItems.map(\.text), ["a", "b"])
    }

    func testCollapsedShowsTopThree() {
        let store = makeStore(["a", "b", "c", "d", "e"])
        store.collapsesOnOpen = true
        store.resetCollapse()
        XCTAssertEqual(store.displayedItems.map(\.text), ["a", "b", "c"])
        XCTAssertTrue(store.showsCollapseToggle)

        store.setCollapsed(false)
        XCTAssertEqual(store.displayedItems.map(\.text), ["a", "b", "c", "d", "e"])
    }

    func testCollapseOffShowsEverythingWithoutToggle() {
        let store = makeStore(["a", "b", "c", "d"])
        store.resetCollapse()
        XCTAssertEqual(store.displayedItems.count, 4)
        XCTAssertFalse(store.showsCollapseToggle)
    }

    func testNoToggleForThreeOrFewer() {
        let store = makeStore(["a", "b", "c"])
        store.collapsesOnOpen = true
        store.resetCollapse()
        XCTAssertFalse(store.showsCollapseToggle)
        XCTAssertEqual(store.displayedItems.count, 3)
    }

    func testMovingFocusPastThirdExpands() {
        let store = makeStore(["a", "b", "c", "d"])
        store.collapsesOnOpen = true
        store.resetCollapse()
        store.hopToNext(from: store.visibleItems[1].id, caret: .end)
        XCTAssertTrue(store.isCollapsed)
        store.hopToNext(from: store.visibleItems[2].id, caret: .end)
        XCTAssertFalse(store.isCollapsed)
        XCTAssertEqual(store.displayedItems.count, 4)
    }

    func testMovingThirdItemDownExpands() {
        let store = makeStore(["a", "b", "c", "d"])
        store.collapsesOnOpen = true
        store.resetCollapse()
        let third = store.visibleItems[2].id
        store.focusedID = third
        store.moveDown(third)
        XCTAssertFalse(store.isCollapsed)
    }

    func testCollapsingMovesHiddenFocusToLastShownRow() {
        let store = makeStore(["a", "b", "c", "d"])
        store.collapsesOnOpen = true
        store.focusedID = store.visibleItems[3].id
        store.setCollapsed(true)
        XCTAssertTrue(store.isCollapsed)
        XCTAssertEqual(store.focusedID, store.visibleItems[2].id)
    }

    // MARK: - Helpers

    private func writeState(_ json: String) throws {
        try json.write(to: stateURL, atomically: true, encoding: .utf8)
    }

    private func makeStore(_ texts: [String]) -> Store {
        let store = Store(fileURL: stateURL)
        var previous = store.visibleItems[0].id
        store.setText(texts[0], for: previous)
        for text in texts.dropFirst() {
            previous = store.insertBlank(after: previous)
            store.setText(text, for: previous)
        }
        store.focusedID = store.visibleItems.first?.id
        store.pendingCaret = nil
        store.undoManager.removeAllActions()
        return store
    }
}
