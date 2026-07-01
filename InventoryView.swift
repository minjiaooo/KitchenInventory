import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var context
    @Query private var all: [Grocery]

    // 删除的提示 + 撤销（与采购清单同一套）
    @State private var toastMessage: String?
    @State private var undoAction: (() -> Void)?
    @State private var toastID = 0

    // 改名（修正识别/翻译错字）
    @State private var renamingGrocery: Grocery?
    @State private var renameText = ""

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
            ZStack(alignment: .bottom) {
                List {
                    Section {
                        if fresh.isEmpty {
                            Text("本周还没有生鲜入库").foregroundStyle(.secondary)
                        }
                        ForEach(fresh) { row($0) }
                    } header: {
                        Text("本周生鲜 · 需要照看")
                    } footer: {
                        Text("点一下循环：有 → 快没了 → 没了（标“没了”会自动回到待买清单）。长按移动分类，左滑删除或改名。")
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

                if let toastMessage { toastView(toastMessage) }
            }
            .navigationTitle("智能库存")
            .alert("改个名字", isPresented: Binding(
                get: { renamingGrocery != nil },
                set: { if !$0 { renamingGrocery = nil } })) {
                TextField("名称", text: $renameText)
                Button("保存") {
                    if let g = renamingGrocery {
                        GroceryActions.rename(g, to: renameText, in: context)
                    }
                    renamingGrocery = nil
                }
                Button("取消", role: .cancel) { renamingGrocery = nil }
            }
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
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                let result = GroceryActions.deleteGrocery(item, in: context)
                presentToast(result)
            } label: { Label("删除", systemImage: "trash") }
            Button {
                renameText = item.name
                renamingGrocery = item
            } label: { Label("改名", systemImage: "pencil") }.tint(.orange)
        }
        .contextMenu {
            Button { GroceryActions.setType(item, .fresh, in: context) } label: { Label("移到生鲜", systemImage: "leaf") }
            Button { GroceryActions.setType(item, .dry, in: context) } label: { Label("移到干货", systemImage: "shippingbox") }
            Button { GroceryActions.setType(item, .staple, in: context) } label: { Label("移到常备", systemImage: "cabinet") }
        }
    }

    private func toastView(_ msg: String) -> some View {
        HStack {
            Text(msg).font(.subheadline)
            if undoAction != nil {
                Spacer()
                Button("撤销") {
                    undoAction?()
                    withAnimation { toastMessage = nil; undoAction = nil }
                }.font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 24)
        .transition(.opacity)
    }

    private func presentToast(_ result: ActionResult) {
        guard !result.message.isEmpty else { return }
        toastID += 1
        let myID = toastID
        withAnimation { toastMessage = result.message; undoAction = result.undo }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if toastID == myID {
                withAnimation { toastMessage = nil; undoAction = nil }
            }
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
