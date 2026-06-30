import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var context
    @Query private var all: [Grocery]

    // 三层：生鲜需照看；干货、常备耐放
    private var fresh: [Grocery] {
        all.filter { $0.type == .fresh && $0.status != .none }
           .sorted { ($0.boughtAt ?? .distantPast) < ($1.boughtAt ?? .distantPast) }
    }
    private var dry: [Grocery] {
        all.filter { $0.type == .dry && $0.status != .none }
           .sorted { $0.name < $1.name }
    }
    private var staples: [Grocery] {
        all.filter { $0.type == .staple && $0.status != .none }
           .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if fresh.isEmpty {
                        Text("本周还没有生鲜入库").foregroundStyle(.secondary)
                    }
                    ForEach(fresh) { row($0) }
                } header: {
                    Text("本周生鲜 · 需要照看")
                } footer: {
                    Text("点一下循环：有 → 快没了 → 没了（标“没了”会自动回到待买清单）。长按可移动分类。")
                }

                if !dry.isEmpty {
                    Section("干货 · 耐放") {
                        ForEach(dry) { row($0) }
                    }
                }

                if !staples.isEmpty {
                    Section("常备 · 免维护") {
                        ForEach(staples) { row($0) }
                    }
                }
            }
            .navigationTitle("智能库存")
        }
    }

    @ViewBuilder
    private func row(_ item: Grocery) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color(item.status)).frame(width: 12, height: 12)
            Text(item.name)
            Spacer()
            Text(label(item.status)).font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { GroceryActions.cycleStatus(item) } }
        .contextMenu {
            Button { GroceryActions.setType(item, .fresh, in: context) } label: { Label("移到生鲜", systemImage: "leaf") }
            Button { GroceryActions.setType(item, .dry, in: context) } label: { Label("移到干货", systemImage: "shippingbox") }
            Button { GroceryActions.setType(item, .staple, in: context) } label: { Label("移到常备", systemImage: "cabinet") }
        }
    }

    private func color(_ s: GroceryStatus) -> Color {
        switch s {
        case .have: .green
        case .runningLow: .orange
        case .none: .gray
        }
    }
    private func label(_ s: GroceryStatus) -> String {
        switch s {
        case .have: "有"
        case .runningLow: "快没了"
        case .none: "没了"
        }
    }
}
