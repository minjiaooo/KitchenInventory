import SwiftUI
import SwiftData

/// 拍小票后的「预览校对页」：OCR 噪声大，先让用户增删改，确认后才入库。
/// 英文小票按三层降级转中文：① 词典(init 同步) → ② FoundationModels 模型(异步) → ③ 手动。
/// 这是录入校对，不是「确认吗」拦截弹窗——入库后仍给整批撤销。
struct ReceiptReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Supermarket.name) private var stores: [Supermarket]

    let parsed: ParsedReceipt
    var onImported: (ActionResult) -> Void

    @State private var rows: [ReviewRow]
    @State private var storeName: String
    @State private var date: Date
    @State private var renamingRow: ReviewRow?
    @State private var renameText = ""

    init(parsed: ParsedReceipt, onImported: @escaping (ActionResult) -> Void) {
        self.parsed = parsed
        self.onImported = onImported
        // 一级降级：进页面先用本地词典同步转中文，命中就直接显示中文
        _rows = State(initialValue: parsed.items.map { item in
            ReviewRow(name: FoodDictionary.lookup(item) ?? item, original: item, include: true)
        })
        _storeName = State(initialValue: parsed.storeName ?? "")
        _date = State(initialValue: parsed.date ?? Date())
    }

    private var chosenCount: Int { rows.filter { $0.include }.count }

    var body: some View {
        NavigationStack {
            Form {
                storeSection
                Section("购买时间") {
                    DatePicker("买于", selection: $date, displayedComponents: .date)
                }
                itemsSection
            }
            .navigationTitle("核对小票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("改个名字", isPresented: Binding(
                get: { renamingRow != nil },
                set: { if !$0 { renamingRow = nil } })) {
                TextField("名称", text: $renameText)
                Button("保存") { applyRename() }
                Button("取消", role: .cancel) { renamingRow = nil }
            }
            .task { await translateEnglishRows() }
        }
    }

    @ViewBuilder
    private var storeSection: some View {
        Section("归到哪家店") {
            TextField("店名（留空 = 不限超市）", text: $storeName)
            if !stores.isEmpty {
                Menu("从已有超市选") {
                    ForEach(stores) { s in
                        Button(s.name) { storeName = s.name }
                    }
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var itemsSection: some View {
        Section {
            if rows.isEmpty {
                Text("没识别到商品，可关闭后手动添加").foregroundStyle(.secondary)
            }
            ForEach($rows) { $row in
                HStack(spacing: 12) {
                    Button { row.include.toggle() } label: {
                        Image(systemName: row.include ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(row.include ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).foregroundStyle(row.include ? .primary : .secondary)
                        if row.fromModel {
                            Text("自动转自「\(row.original)」")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if row.translating { ProgressView() }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    renameText = row.name
                    renamingRow = row
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        rows.removeAll { $0.id == row.id }
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
        } header: {
            Text("识别到的商品")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let note = parsed.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                Text("英文会自动转中文（词典 / 模型），可能不准——点名字可改、左滑可删。校对后再入库。")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(chosenCount > 0 ? "入库 \(chosenCount) 样" : "入库") { confirmImport() }
                .disabled(chosenCount == 0)
        }
    }

    // 二级降级：词典没命中的英文项，异步调 FoundationModels 翻译，成功则回灌词典缓存
    private func translateEnglishRows() async {
        guard FoodTranslator.isAvailable else { return }   // 模型不可用 → 全留英文待手动
        let targets = rows
            .filter { needsTranslation($0.name) }
            .map { (id: $0.id, original: $0.original) }
        for t in targets {
            guard let i = rows.firstIndex(where: { $0.id == t.id }) else { continue }
            rows[i].translating = true
            let zh = await FoodTranslator.toChinese(t.original)
            guard let j = rows.firstIndex(where: { $0.id == t.id }) else { continue }
            if let zh {
                rows[j].name = zh
                rows[j].fromModel = true
                FoodDictionary.remember(english: t.original, chinese: zh)
            }
            rows[j].translating = false
        }
    }

    private func needsTranslation(_ s: String) -> Bool {
        let hasHan = s.range(of: "\\p{Han}", options: .regularExpression) != nil
        let hasLatin = s.range(of: "[A-Za-z]", options: .regularExpression) != nil
        return !hasHan && hasLatin
    }

    private func applyRename() {
        if let r = renamingRow,
           let idx = rows.firstIndex(where: { $0.id == r.id }) {
            let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                rows[idx].name = t
                rows[idx].fromModel = false   // 用户手动改过，不再标“自动转”
            }
        }
        renamingRow = nil
    }

    private func confirmImport() {
        let chosen = rows.filter { $0.include }.map { $0.name }
        let trimmedStore = storeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = GroceryActions.importReceipt(
            items: chosen,
            storeName: trimmedStore.isEmpty ? nil : trimmedStore,
            boughtAt: date,
            in: context)
        onImported(result)
        dismiss()
    }
}

struct ReviewRow: Identifiable {
    let id = UUID()
    var name: String
    var original: String
    var include: Bool
    var translating: Bool = false
    var fromModel: Bool = false
}
