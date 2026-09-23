import Foundation
import Observation

struct TodoItem: Identifiable, Equatable, Hashable {
    var id: UUID
    var text: String
    var completedAt: Date?

    init(id: UUID = UUID(), text: String, completedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.completedAt = completedAt
    }

    var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension TodoItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, text, completedAt, isDone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        if let seconds = try? container.decode(Double.self, forKey: .completedAt) {
            completedAt = Date(timeIntervalSince1970: seconds)
        } else if let string = try? container.decode(String.self, forKey: .completedAt),
                  let parsed = ISO8601DateFormatter().date(from: string) {
            completedAt = parsed
        } else if try container.decodeIfPresent(Bool.self, forKey: .isDone) == true {
            completedAt = Date()
        } else {
            completedAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        if let completedAt {
            try container.encode(Int(completedAt.timeIntervalSince1970), forKey: .completedAt)
        }
    }
}

private struct PersistedState: Codable {
    var items: [TodoItem]
}

@MainActor
@Observable
final class Store {
    private(set) var items: [TodoItem] = []
    var focusedID: UUID?
    var pendingCaret: CaretTarget?
    var onChange: (() -> Void)?

    let undoManager = UndoManager()

    var visibleItems: [TodoItem] {
        items.filter { $0.completedAt == nil }
    }

    var completedItems: [TodoItem] {
        items
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var realCount: Int {
        items.filter { $0.completedAt == nil && $0.hasText }.count
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
        ensureBlankIfEmpty()
    }

    func setText(_ text: String, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let before = realCount
        items[index].text = text
        persist()
        if realCount != before {
            onChange?()
        }
    }

    func checkOff(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].hasText, items[index].completedAt == nil else { return }
        let next = visibleNeighbor(of: id)
        let before = items
        var item = items.remove(at: index)
        item.completedAt = Date()
        items.append(item)
        ensureBlankIfEmpty()
        registerUndo(before: before, name: "Complete")
        persist()
        onChange?()
        focusVisible(next, caret: .end)
    }

    func delete(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        if visibleItems.count == 1, visibleItems.first?.hasText != true {
            return
        }
        let next = visibleNeighbor(of: id)
        replaceItems(removing: id, actionName: "Delete")
        focusVisible(next, caret: .end)
    }

    func insertBlank(before id: UUID) -> UUID {
        let blank = TodoItem(text: "")
        let snapshot = items
        if let index = items.firstIndex(where: { $0.id == id }) {
            items.insert(blank, at: index)
        } else {
            items.insert(blank, at: 0)
        }
        registerUndo(before: snapshot, name: "Insert")
        persist()
        onChange?()
        focusVisible(id, caret: .char(0))
        return blank.id
    }

    func insertBlank(after id: UUID) -> UUID {
        let blank = TodoItem(text: "")
        let snapshot = items
        if let index = items.firstIndex(where: { $0.id == id }) {
            items.insert(blank, at: index + 1)
        } else {
            items.append(blank)
        }
        registerUndo(before: snapshot, name: "Insert")
        persist()
        onChange?()
        focusVisible(blank.id, caret: .char(0))
        return blank.id
    }

    func insertAfterOrHide(id: UUID) -> Bool {
        let visible = visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return false }
        if !visible[index].hasText, index == visible.count - 1 {
            return true
        }
        _ = insertBlank(after: id)
        return false
    }

    func split(id: UUID, at caret: Int) {
        guard let itemIndex = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[itemIndex].completedAt == nil else { return }
        let ns = items[itemIndex].text as NSString
        guard caret > 0, caret < ns.length else { return }

        let left = ns.substring(to: caret).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = ns.substring(from: caret).trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty && right.isEmpty {
            return
        }

        let snapshot = items
        items[itemIndex].text = left
        let created = TodoItem(text: right)
        items.insert(created, at: itemIndex + 1)
        registerUndo(before: snapshot, name: "Split")
        persist()
        onChange?()
        focusVisible(created.id, caret: .char(0))
    }

    func smartBackspace(id: UUID) {
        let visible = visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return }
        let current = visible[index]

        if visible.count == 1 {
            guard current.hasText else { return }
            let snapshot = items
            if let itemIndex = items.firstIndex(where: { $0.id == id }) {
                items[itemIndex].text = ""
            }
            registerUndo(before: snapshot, name: "Delete")
            persist()
            onChange?()
            focusVisible(id, caret: .char(0))
            return
        }

        if index == 0 {
            guard !current.hasText else { return }
            let next = visible[1].id
            replaceItems(removing: id, actionName: "Delete")
            focusVisible(next, caret: .end)
            return
        }

        let previous = visible[index - 1]
        if !previous.hasText {
            replaceItems(removing: previous.id, actionName: "Delete")
            focusVisible(id, caret: .char(0))
            return
        }

        let snapshot = items
        guard let previousIndex = items.firstIndex(where: { $0.id == previous.id }),
              let currentIndex = items.firstIndex(where: { $0.id == id })
        else { return }
        let join = (items[previousIndex].text as NSString).length
        items[previousIndex].text += items[currentIndex].text
        items.remove(at: currentIndex)
        registerUndo(before: snapshot, name: "Merge")
        persist()
        onChange?()
        focusVisible(previous.id, caret: .char(join))
    }

    func performEnter(id: UUID, at caret: Int) -> Bool {
        guard let item = items.first(where: { $0.id == id }), item.completedAt == nil else {
            return false
        }
        let length = (item.text as NSString).length
        if caret == 0, length > 0 {
            insertBlank(before: id)
            return false
        }
        if caret > 0, caret < length {
            split(id: id, at: caret)
            return false
        }
        return insertAfterOrHide(id: id)
    }

    func hopToPrevious(from id: UUID, caret: CaretTarget) {
        guard let previous = itemBefore(id) else { return }
        focusVisible(previous, caret: caret)
    }

    func hopToNext(from id: UUID, caret: CaretTarget) {
        guard let next = itemAfter(id) else { return }
        focusVisible(next, caret: caret)
    }

    func clearPendingCaret() {
        pendingCaret = nil
    }

    func ensureBlankIfEmpty() {
        if items.contains(where: { $0.completedAt == nil && $0.hasText }) {
            return
        }
        items.removeAll { $0.completedAt == nil && !$0.hasText }
        items.insert(TodoItem(text: ""), at: 0)
    }

    func move(id sourceID: UUID, onto targetID: UUID) {
        guard sourceID != targetID,
              let from = items.firstIndex(where: { $0.id == sourceID })
        else { return }
        let before = items
        var next = items
        let moved = next.remove(at: from)
        if let to = next.firstIndex(where: { $0.id == targetID }) {
            next.insert(moved, at: to)
        } else {
            next.append(moved)
        }
        items = next
        registerUndo(before: before, name: "Reorder")
        persist()
        onChange?()
    }

    func moveListed(from source: IndexSet, to destination: Int) {
        guard !items.isEmpty else { return }
        let before = items
        items.move(fromOffsets: source, toOffset: destination)
        registerUndo(before: before, name: "Reorder")
        persist()
        onChange?()
    }

    func moveUp(_ id: UUID) {
        let visible = items.enumerated().filter { $0.element.completedAt == nil }
        guard let position = visible.firstIndex(where: { $0.element.id == id }), position > 0 else { return }
        swapItems(visible[position].offset, visible[position - 1].offset)
    }

    func moveDown(_ id: UUID) {
        let visible = items.enumerated().filter { $0.element.completedAt == nil }
        guard let position = visible.firstIndex(where: { $0.element.id == id }), position + 1 < visible.count else { return }
        swapItems(visible[position].offset, visible[position + 1].offset)
    }

    func itemAfter(_ id: UUID) -> UUID? {
        let visible = visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return nil }
        let next = index + 1
        guard next < visible.count else { return nil }
        return visible[next].id
    }

    func itemBefore(_ id: UUID) -> UUID? {
        let visible = visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        return visible[index - 1].id
    }

    func compact() {
        items = items.filter(\.hasText)
        ensureBlankIfEmpty()
        persist()
        onChange?()
        if focusedID == nil || !visibleItems.contains(where: { $0.id == focusedID }) {
            focusedID = visibleItems.first?.id
        }
    }

    private let fileURL: URL

    private func swapItems(_ a: Int, _ b: Int) {
        let before = items
        items.swapAt(a, b)
        registerUndo(before: before, name: "Reorder")
        persist()
        onChange?()
    }

    private func replaceItems(removing id: UUID, actionName: String) {
        let before = items
        items.removeAll { $0.id == id }
        ensureBlankIfEmpty()
        registerUndo(before: before, name: actionName)
        persist()
        onChange?()
    }

    private func focusVisible(_ id: UUID?, caret: CaretTarget? = nil) {
        if let caret {
            pendingCaret = caret
        }
        let target = id ?? visibleItems.first?.id
        focusedID = target
        DispatchQueue.main.async { [weak self] in
            self?.focusedID = target
        }
    }

    private func visibleNeighbor(of id: UUID) -> UUID? {
        let visible = visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return visible.last?.id }
        if index + 1 < visible.count {
            return visible[index + 1].id
        }
        if index > 0 {
            return visible[index - 1].id
        }
        return nil
    }

    private func registerUndo(before: [TodoItem], name: String) {
        let after = items
        undoManager.registerUndo(withTarget: self) { store in
            store.restore(after, becoming: before)
        }
        undoManager.setActionName(name)
    }

    private func restore(_ current: [TodoItem], becoming previous: [TodoItem]) {
        items = previous
        ensureBlankIfEmpty()
        persist()
        onChange?()
        undoManager.registerUndo(withTarget: self) { store in
            store.restore(previous, becoming: current)
        }
        if focusedID == nil || !visibleItems.contains(where: { $0.id == focusedID }) {
            focusedID = visibleItems.first?.id
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            items = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            items = state.items.filter(\.hasText)
            if let raw = String(data: data, encoding: .utf8),
               raw.contains("\"isDone\"") || raw.contains("\"completedAt\" : \"") {
                persist()
            }
        } catch {
            items = []
        }
    }

    private func persist() {
        let state = PersistedState(items: items.filter(\.hasText))
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Hem: failed to write state: \(error.localizedDescription)")
        }
    }

    private static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = root.appendingPathComponent("Hem", isDirectory: true)
        let file = directory.appendingPathComponent("state.json")
        copyLegacyStateIfNeeded(to: file, directory: directory, root: root)
        return file
    }

    private static func copyLegacyStateIfNeeded(to file: URL, directory: URL, root: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: file.path) else { return }
        let legacy = root.appendingPathComponent("hotlist2", isDirectory: true)
            .appendingPathComponent("state.json")
        guard fm.fileExists(atPath: legacy.path) else { return }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try fm.copyItem(at: legacy, to: file)
        } catch {
            NSLog("Hem: failed to copy tasks from hotlist2: \(error.localizedDescription)")
        }
    }
}
