import SwiftUI

struct TodoListView: View {
    var store: Store
    var onHide: () -> Void

    @State private var hiddenEdges = HiddenEdges()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Layout.rowSpacing) {
                    ForEach(store.displayedItems) { item in
                        TodoRow(item: item, store: store, onHide: onHide)
                    }
                }
                .padding(.horizontal, Layout.padding)
                .padding(.top, Layout.padding)
                .padding(.bottom, store.showsCollapseToggle ? Layout.rowSpacing : Layout.padding)
            }
            .scrollDisabled(store.displayedItems.count <= Layout.maxVisibleRows)
            .onScrollGeometryChange(for: HiddenEdges.self) { geometry in
                HiddenEdges(
                    top: geometry.visibleRect.minY > 1,
                    bottom: geometry.visibleRect.maxY < geometry.contentSize.height - 1
                )
            } action: { _, edges in
                hiddenEdges = edges
            }
            .mask { EdgeFadeMask(edges: hiddenEdges) }

            if store.showsCollapseToggle {
                CollapseToggle(store: store)
                    .padding(.horizontal, Layout.padding)
                    .padding(.bottom, Layout.padding)
            }
        }
        .frame(width: Layout.panelWidth)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            if store.focusedID == nil {
                store.focusedID = store.visibleItems.first?.id
            }
        }
    }
}

/// Which ends of the list have rows scrolled out of view.
private struct HiddenEdges: Equatable {
    var top = false
    var bottom = false
}

/// Fades the list out at any end that has more rows past it, so it reads as scrollable.
private struct EdgeFadeMask: View {
    let edges: HiddenEdges

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: edges.top ? Layout.fadeHeight : 0)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: edges.bottom ? Layout.fadeHeight : 0)
        }
        .animation(.easeOut(duration: 0.15), value: edges)
    }
}

private struct CollapseToggle: View {
    var store: Store

    var body: some View {
        Button {
            store.setCollapsed(!store.isCollapsed)
        } label: {
            Image(systemName: store.isCollapsed ? "chevron.down" : "chevron.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: Layout.toggleHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(store.isCollapsed ? "Show all tasks" : "Show only the top \(Store.collapsedCount) tasks")
    }
}

private struct TodoRow: View {
    let item: TodoItem
    var store: Store
    var onHide: () -> Void

    private var isFocused: Bool { store.focusedID == item.id }

    private var showsSeparator: Bool {
        !isFocused && item.isDivider
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Layout.bulletColor)
                .frame(width: Layout.bulletSize, height: Layout.bulletSize)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + CaretMetrics.font.xHeight / 2
                }
                .opacity(showsSeparator ? 0 : 1)
            CaretField(
                text: textBinding,
                isFocused: isFocused,
                pendingCaret: isFocused ? store.pendingCaret : nil,
                onFocus: { store.focusedID = item.id },
                onCaretApplied: { store.clearPendingCaret() },
                onCommand: { handleCommand($0) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(showsSeparator ? 0 : 1)
        }
        .frame(minHeight: Layout.rowHeight)
        .overlay {
            if showsSeparator {
                Rectangle()
                    .fill(Layout.dividerColor)
                    .frame(height: 2)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { store.focusedID = item.id }
            }
        }
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
    static let toggleHeight: CGFloat = 20
    static let fadeHeight: CGFloat = rowHeight / 2

    // The list is masked for its edge fades, which cuts it off from the material's
    // vibrancy, so semantic styles like .separator render as a flat grey that
    // ignores what is behind the panel. Plain translucent colours blend normally.
    static let bulletColor = Color.primary.opacity(0.5)
    static let dividerColor = Color.primary.opacity(0.12)
    static let footerHeight: CGFloat = toggleHeight + padding

    /// The most rows the panel shows before the list scrolls.
    static let maxVisibleRows = 12

    /// Past `maxVisibleRows`, or past what fits in `maxHeight`, the panel shows whole
    /// rows plus half of the next one, so the bottom fade always lands on a cut-off
    /// row. The collapse toggle sits in a footer below the rows so it stays visible.
    static func panelHeight(forItemCount count: Int, showsToggle: Bool, maxHeight: CGFloat) -> CGFloat {
        let stride = rowHeight + rowSpacing
        let footer = showsToggle ? footerHeight : 0
        let fitting = Int(((maxHeight - footer - padding - rowHeight / 2) / stride).rounded(.down))
        let limit = max(min(maxVisibleRows, fitting), 1)
        let rows = max(count, 1)
        guard rows > limit else {
            let bottomPadding = showsToggle ? rowSpacing : padding
            return padding + CGFloat(rows) * stride - rowSpacing + bottomPadding + footer
        }
        return padding + CGFloat(limit) * stride + rowHeight / 2 + footer
    }
}
