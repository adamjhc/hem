import SwiftUI

struct TodoListView: View {
    var store: Store
    var onHide: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Layout.rowSpacing) {
                ForEach(store.visibleItems) { item in
                    TodoRow(item: item, store: store, onHide: onHide)
                        .draggable(item.id.uuidString)
                        .dropDestination(for: String.self) { dropped, _ in
                            guard let raw = dropped.first, let source = UUID(uuidString: raw) else {
                                return false
                            }
                            store.move(id: source, onto: item.id)
                            return true
                        }
                }
            }
            .padding(Layout.padding)
        }
        .scrollDisabled(store.visibleItems.count < 10)
        .frame(width: Layout.panelWidth)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            if store.focusedID == nil {
                store.focusedID = store.visibleItems.first?.id
            }
        }
    }
}

private struct TodoRow: View {
    let item: TodoItem
    var store: Store
    var onHide: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(.secondary)
                .frame(width: Layout.bulletSize, height: Layout.bulletSize)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + CaretMetrics.font.xHeight / 2
                }
            CaretField(
                text: textBinding,
                isFocused: store.focusedID == item.id,
                pendingCaret: store.focusedID == item.id ? store.pendingCaret : nil,
                onFocus: { store.focusedID = item.id },
                onCaretApplied: { store.clearPendingCaret() },
                onCommand: { handleCommand($0) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: Layout.rowHeight)
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { store.items.first(where: { $0.id == item.id })?.text ?? "" },
            set: { store.setText($0, for: item.id) }
        )
    }

    private func handleCommand(_ command: CaretCommand) {
        switch command {
        case .moveLeftAtStart:
            store.hopToPrevious(from: item.id, caret: .end)
        case .moveRightAtEnd:
            store.hopToNext(from: item.id, caret: .char(0))
        case .moveUp(let x):
            store.hopToPrevious(from: item.id, caret: .x(x))
        case .moveDown(let x):
            store.hopToNext(from: item.id, caret: .x(x))
        case .enter(let caret):
            if store.performEnter(id: item.id, at: caret) {
                onHide()
            }
        case .smartBackspace:
            store.smartBackspace(id: item.id)
        }
    }
}

enum Layout {
    static let panelWidth: CGFloat = 380
    static let rowHeight: CGFloat = 36
    static let rowSpacing: CGFloat = 2
    static let padding: CGFloat = 12
    static let fontSize: CGFloat = 16
    static let bulletSize: CGFloat = 5

    static func panelHeight(forItemCount count: Int, maxHeight: CGFloat) -> CGFloat {
        let items = CGFloat(max(count, 1))
        let content = padding * 2 + items * rowHeight + max(items - 1, 0) * rowSpacing
        return min(content, maxHeight)
    }
}
