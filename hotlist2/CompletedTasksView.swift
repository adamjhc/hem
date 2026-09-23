import SwiftUI

struct CompletedTasksView: View {
    var store: Store

    var body: some View {
        Group {
            if store.completedItems.isEmpty {
                Text("No completed tasks")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.completedItems) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.text)
                            .font(.system(size: Layout.fontSize))
                            .textSelection(.enabled)
                        if let completedAt = item.completedAt {
                            Text(completedAt, format: Self.completedStamp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 320)
    }

    private static let completedStamp = Date.FormatStyle(date: .abbreviated, time: .shortened)
}
