import XCTest
@testable import Hem

@MainActor
final class StoreCaretTests: XCTestCase {
    func testInsertBeforeKeepsFocusOnCurrentRow() {
        let store = makeStore(["task"])
        let current = store.visibleItems[0].id

        XCTAssertFalse(store.performEnter(id: current, at: 0))

        XCTAssertEqual(store.visibleItems.map(\.text), ["", "task"])
        XCTAssertEqual(store.focusedID, current)
        XCTAssertEqual(store.pendingCaret, .char(0))
    }

    func testInsertAfterFocusesNewRow() {
        let store = makeStore(["task"])
        let current = store.visibleItems[0].id

        XCTAssertFalse(store.performEnter(id: current, at: 4))

        XCTAssertEqual(store.visibleItems.map(\.text), ["task", ""])
        XCTAssertEqual(store.focusedID, store.visibleItems[1].id)
        XCTAssertEqual(store.pendingCaret, .char(0))
    }

    func testEnterOnLastEmptyHides() {
        let store = makeStore(["task", ""])
        let last = store.visibleItems[1].id

        XCTAssertTrue(store.performEnter(id: last, at: 0))
        XCTAssertEqual(store.visibleItems.map(\.text), ["task", ""])
    }

    func testEnterOnSingleEmptyHides() {
        let store = makeStore([""])
        XCTAssertTrue(store.performEnter(id: store.visibleItems[0].id, at: 0))
        XCTAssertEqual(store.visibleItems.map(\.text), [""])
    }

    func testEnterAtEndInsertsAfter() {
        let store = makeStore(["task"])
        let current = store.visibleItems[0].id

        XCTAssertFalse(store.performEnter(id: current, at: 4))
        XCTAssertEqual(store.visibleItems.map(\.text), ["task", ""])
        XCTAssertEqual(store.focusedID, store.visibleItems[1].id)
    }

    func testSplitAtCaretTrimsBothSides() {
        let store = makeStore(["hello world"])
        let original = store.visibleItems[0].id

        XCTAssertFalse(store.performEnter(id: original, at: 6))

        XCTAssertEqual(store.visibleItems.map(\.text), ["hello", "world"])
        XCTAssertEqual(store.visibleItems[0].id, original)
        XCTAssertEqual(store.focusedID, store.visibleItems[1].id)
        XCTAssertEqual(store.pendingCaret, .char(0))
    }

    func testSplitThatCreatesTwoEmptiesIsNoOp() {
        let store = makeStore(["   "])
        let original = store.visibleItems[0].id
        store.split(id: original, at: 1)
        XCTAssertEqual(store.visibleItems.map(\.text), ["   "])
        XCTAssertEqual(store.focusedID, original)
    }

    func testUndoSplitRestoresOriginalRow() {
        let store = makeStore(["hello world"])
        let original = store.visibleItems[0].id
        store.split(id: original, at: 5)
        XCTAssertEqual(store.visibleItems.map(\.text), ["hello", "world"])

        store.undoManager.undo()
        XCTAssertEqual(store.visibleItems.map(\.text), ["hello world"])
        XCTAssertEqual(store.visibleItems[0].id, original)
    }

    func testSmartBackspaceOnOneRowClearsPlaceholder() {
        let store = makeStore(["only"])
        let id = store.visibleItems[0].id
        store.smartBackspace(id: id)
        XCTAssertEqual(store.visibleItems.map(\.text), [""])
        XCTAssertEqual(store.focusedID, id)
        XCTAssertEqual(store.pendingCaret, .char(0))
    }

    func testSmartBackspaceDeletesPreviousEmpty() {
        let store = makeStore(["", "keep"])
        let current = store.visibleItems[1].id
        store.smartBackspace(id: current)
        XCTAssertEqual(store.visibleItems.map(\.text), ["keep"])
        XCTAssertEqual(store.focusedID, current)
        XCTAssertEqual(store.pendingCaret, .char(0))
    }

    func testSmartBackspaceMergesOntoPrevious() {
        let store = makeStore(["hello", "world"])
        let current = store.visibleItems[1].id
        store.smartBackspace(id: current)
        XCTAssertEqual(store.visibleItems.map(\.text), ["helloworld"])
        XCTAssertEqual(store.focusedID, store.visibleItems[0].id)
        XCTAssertEqual(store.pendingCaret, .char(5))
    }

    func testSmartBackspaceDeletesEmptyRowAndFocusesPrevious() {
        let store = makeStore(["keep", ""])
        store.smartBackspace(id: store.visibleItems[1].id)
        XCTAssertEqual(store.visibleItems.map(\.text), ["keep"])
        XCTAssertEqual(store.focusedID, store.visibleItems[0].id)
        XCTAssertEqual(store.pendingCaret, .char(4))
    }

    func testUndoMergeRestoresBothRows() {
        let store = makeStore(["hello", "world"])
        store.smartBackspace(id: store.visibleItems[1].id)
        store.undoManager.undo()
        XCTAssertEqual(store.visibleItems.map(\.text), ["hello", "world"])
    }

    func testLeftHopFromFirstRowIsNoOp() {
        let store = makeStore(["one", "two"])
        let first = store.visibleItems[0].id
        store.focusedID = first
        store.hopToPrevious(from: first, caret: .end)
        XCTAssertEqual(store.focusedID, first)
    }

    func testLeftHopLandsOnPreviousEnd() {
        let store = makeStore(["one", "two"])
        store.hopToPrevious(from: store.visibleItems[1].id, caret: .end)
        XCTAssertEqual(store.focusedID, store.visibleItems[0].id)
        XCTAssertEqual(store.pendingCaret, .end)
    }

    func testRightHopFromLastRowIsNoOp() {
        let store = makeStore(["one", "two"])
        let last = store.visibleItems[1].id
        store.focusedID = last
        store.hopToNext(from: last, caret: .char(0))
        XCTAssertEqual(store.focusedID, last)
    }

    func testCompletedItemsNewestFirst() {
        let store = makeStore(["older", "newer"])
        store.checkOff(store.visibleItems[0].id)
        store.checkOff(store.visibleItems[0].id)

        XCTAssertEqual(store.completedItems.map(\.text), ["newer", "older"])
        XCTAssertEqual(store.completedItems.count, 2)
        XCTAssertNotNil(store.completedItems[0].completedAt)
        XCTAssertNotNil(store.completedItems[1].completedAt)
        XCTAssertGreaterThanOrEqual(
            store.completedItems[0].completedAt!,
            store.completedItems[1].completedAt!
        )
    }

    func testHopsSkipCompletedRows() {
        let store = makeStore(["one", "done", "three"])
        store.checkOff(store.visibleItems[1].id)
        XCTAssertEqual(store.visibleItems.map(\.text), ["one", "three"])

        let first = store.visibleItems[0].id
        store.hopToNext(from: first, caret: .char(0))
        XCTAssertEqual(store.focusedID, store.visibleItems[1].id)
        XCTAssertEqual(store.visibleItems.first(where: { $0.id == store.focusedID })?.text, "three")

        store.hopToPrevious(from: store.visibleItems[1].id, caret: .end)
        XCTAssertEqual(store.focusedID, first)
    }

    func testUpDownUseVisualXNotCharacterIndex() {
        let narrow = CaretMetrics.width(of: "iii")
        let indexInWide = CaretMetrics.index(in: "WWWWWW", closestToX: narrow)
        XCTAssertLessThan(indexInWide, 3)
        XCTAssertEqual(CaretMetrics.index(in: "hello", closestToX: 0), 0)
        XCTAssertEqual(CaretMetrics.index(for: .end, in: "hello"), 5)
        XCTAssertEqual(CaretMetrics.index(for: .char(3), in: "hello"), 3)
        XCTAssertEqual(CaretMetrics.index(for: .char(99), in: "hello"), 5)
    }

    func testFirstLastAndOneRowWalk() {
        let firstLast = makeStore(["alpha", "beta", "gamma"])
        let first = firstLast.visibleItems[0].id
        let last = firstLast.visibleItems[2].id
        firstLast.hopToPrevious(from: first, caret: .end)
        XCTAssertEqual(firstLast.focusedID, first)
        firstLast.focusedID = last
        firstLast.hopToNext(from: last, caret: .char(0))
        XCTAssertEqual(firstLast.focusedID, last)
        XCTAssertTrue(firstLast.insertAfterOrHide(id: {
            firstLast.setText("", for: firstLast.visibleItems[2].id)
            return firstLast.visibleItems[2].id
        }()))

        let one = makeStore(["solo"])
        one.hopToPrevious(from: one.visibleItems[0].id, caret: .end)
        one.hopToNext(from: one.visibleItems[0].id, caret: .char(0))
        XCTAssertEqual(one.visibleItems.count, 1)
        one.smartBackspace(id: one.visibleItems[0].id)
        XCTAssertEqual(one.visibleItems.map(\.text), [""])
        XCTAssertTrue(one.performEnter(id: one.visibleItems[0].id, at: 0))
    }

    private func makeStore(_ texts: [String]) -> Store {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Hem-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = Store(fileURL: folder.appendingPathComponent("state.json"))
        store.undoManager.removeAllActions()

        if texts.isEmpty {
            return store
        }

        let first = store.visibleItems[0].id
        store.setText(texts[0], for: first)
        var previous = first
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
