import Foundation
import SwiftData

// MARK: - 分类启发式（命中干货词 → dry；命中常备词 → staple；否则 fresh）

enum StapleHeuristic {
    static let dryKeywords: Set<String> = [
        "香菇", "木耳", "紫菜", "海带", "粉丝", "粉条", "腐竹", "银耳", "干贝", "虾米",
        "红枣", "枸杞", "桂圆", "莲子", "花生", "黄豆", "绿豆", "红豆", "干辣椒", "桂皮",
        "茶", "核桃", "杏仁", "腰果", "干香菇", "笋干", "梅干"
    ]
    static let stapleKeywords: Set<String> = [
        "盐", "糖", "油", "酱油", "生抽", "老抽", "醋", "蚝油", "料酒", "胡椒",
        "米", "面", "面粉", "淀粉", "酱", "蜂蜜", "花椒", "八角", "鸡精", "味精",
        "salt", "sugar", "oil", "soy sauce", "vinegar", "rice", "flour", "honey"
    ]
    static func type(for name: String) -> GroceryType {
        let lower = name.lowercased()
        if dryKeywords.contains(where: { lower.contains($0) }) { return .dry }
        if stapleKeywords.contains(where: { lower.contains($0) }) { return .staple }
        return .fresh
    }
}

// MARK: - 加入结果（撤销时区分新建 / 复用）

struct AddedGrocery: Identifiable {
    let grocery: Grocery
    let wasNew: Bool
    var id: PersistentIdentifier { grocery.id }
}

// MARK: - 动作结果（提示文案 + 可选撤销）

struct ActionResult {
    let message: String
    let undo: (() -> Void)?
}

// MARK: - 核心动作

@MainActor
enum GroceryActions {

    // ===== 语音指令统一入口 =====
    static func perform(_ command: VoiceCommand, in context: ModelContext) -> ActionResult {
        switch command {
        case .add(let names):                     return doAdd(names, in: context)
        case .delete(let names):                  return doDelete(names, in: context)
        case .assignStore(let items, let store):  return doAssign(items, storeName: store, in: context)
        case .markOut(let names):                 return doMarkOut(names, in: context)
        }
    }

    // 加入
    private static func doAdd(_ names: [String], in context: ModelContext) -> ActionResult {
        let added = addToShoppingList(names: names, in: context)
        guard let first = added.first else {
            return ActionResult(message: "没听清要买什么", undo: nil)
        }
        let msg = added.count == 1 ? "已加入「\(first.grocery.name)」"
                                   : "已加入「\(first.grocery.name)」等 \(added.count) 样"
        return ActionResult(message: msg, undo: { undo(added, in: context) })
    }

    // 删除（软删：移出清单，可撤销）
    private static func doDelete(_ names: [String], in context: ModelContext) -> ActionResult {
        var affected: [Grocery] = []
        for n in names {
            if let g = fetch(name: n, in: context), g.isOnShoppingList {
                g.isOnShoppingList = false
                affected.append(g)
            }
        }
        try? context.save()
        guard let first = affected.first else {
            return ActionResult(message: "清单里没找到要删的东西", undo: nil)
        }
        let msg = affected.count == 1 ? "已删除「\(first.name)」" : "已删除 \(affected.count) 样"
        return ActionResult(message: msg, undo: {
            for g in affected { g.isOnShoppingList = true }
            try? context.save()
        })
    }

    // 归店（把 X 放进 Y；找不到超市就新建，找不到食材就创建并加入）
    private static func doAssign(_ items: [String], storeName: String, in context: ModelContext) -> ActionResult {
        let store = findOrCreateStore(named: storeName, in: context)
        var snapshots: [(g: Grocery, prevStore: Supermarket?, prevPinned: Bool)] = []
        for n in items {
            let g: Grocery
            if let found = fetch(name: n, in: context) {
                g = found
            } else {
                g = Grocery(name: n, type: StapleHeuristic.type(for: n))
                context.insert(g)
            }
            snapshots.append((g, g.store, g.isStorePinned))
            g.store = store
            g.isStorePinned = true
        }
        try? context.save()
        let label = items.first ?? ""
        let msg = items.count == 1 ? "已把「\(label)」放进 \(store.name)"
                                   : "已把 \(items.count) 样放进 \(store.name)"
        return ActionResult(message: msg, undo: {
            for s in snapshots { s.g.store = s.prevStore; s.g.isStorePinned = s.prevPinned }
            try? context.save()
        })
    }

    // 用完了 / 没了 → 标记没了并加回待买
    private static func doMarkOut(_ names: [String], in context: ModelContext) -> ActionResult {
        var snapshots: [(g: Grocery, status: GroceryStatus, onList: Bool)] = []
        for n in names {
            if let g = fetch(name: n, in: context) {
                snapshots.append((g, g.status, g.isOnShoppingList))
                g.status = .none
                g.isOnShoppingList = true
                g.addedToListAt = Date()
            }
        }
        try? context.save()
        guard let first = snapshots.first else {
            return ActionResult(message: "没找到这样东西", undo: nil)
        }
        return ActionResult(message: "「\(first.g.name)」标记没了，已加回待买", undo: {
            for s in snapshots { s.g.status = s.status; s.g.isOnShoppingList = s.onList }
            try? context.save()
        })
    }

    // ===== 手动操作 =====

    // 重命名（修正识别错字）；目标名已存在则合并去重
    static func rename(_ g: Grocery, to newNameRaw: String, in context: ModelContext) {
        let newName = newNameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName.lowercased() != g.name.lowercased() else { return }
        if let existing = fetch(name: newName, in: context), existing !== g {
            if g.isOnShoppingList { existing.isOnShoppingList = true }
            context.delete(g)
        } else {
            g.name = newName
        }
        try? context.save()
    }

    // 单条移出清单（侧滑删除）
    static func removeFromList(_ g: Grocery, in context: ModelContext) {
        g.isOnShoppingList = false
        try? context.save()
    }

    // 改变分类（在 生鲜 / 干货 / 常备 间移动）
    static func setType(_ g: Grocery, _ t: GroceryType, in context: ModelContext) {
        g.type = t
        try? context.save()
    }

    static func findOrCreateStore(named name: String, in context: ModelContext) -> Supermarket {
        let target = name.lowercased()
        let all = (try? context.fetch(FetchDescriptor<Supermarket>())) ?? []
        if let exact = all.first(where: { $0.name.lowercased() == target }) { return exact }
        if let fuzzy = all.first(where: {
            $0.name.lowercased().contains(target) || target.contains($0.name.lowercased())
        }) { return fuzzy }
        let s = Supermarket(name: name)
        context.insert(s)
        return s
    }

    // ===== 原有基础动作 =====

    @discardableResult
    static func addToShoppingList(names: [String], in context: ModelContext) -> [AddedGrocery] {
        var result: [AddedGrocery] = []
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if let existing = fetch(name: name, in: context) {
                existing.isOnShoppingList = true
                existing.addedToListAt = Date()
                result.append(AddedGrocery(grocery: existing, wasNew: false))
            } else {
                let g = Grocery(name: name, type: StapleHeuristic.type(for: name))
                context.insert(g)
                result.append(AddedGrocery(grocery: g, wasNew: true))
            }
        }
        try? context.save()
        return result
    }

    static func undo(_ added: [AddedGrocery], in context: ModelContext) {
        for a in added {
            if a.wasNew { context.delete(a.grocery) }
            else { a.grocery.isOnShoppingList = false }
        }
        try? context.save()
    }

    static func fetch(name: String, in context: ModelContext) -> Grocery? {
        let target = name.lowercased()
        let all = (try? context.fetch(FetchDescriptor<Grocery>())) ?? []
        return all.first { $0.name.lowercased() == target }
    }

    static func markBought(_ g: Grocery) {
        g.isOnShoppingList = false
        g.status = .have
        g.boughtAt = Date()
    }

    static func cycleStatus(_ g: Grocery) {
        switch g.status {
        case .have:
            g.status = .runningLow
        case .runningLow:
            g.status = .none
            g.isOnShoppingList = true
            g.addedToListAt = Date()
        case .none:
            g.status = .have
        }
    }

    // ===== 拍小票入库（C1）=====

    /// 把小票校对后的商品批量入库：置「有」、移出待买、盖购买时间戳、按需归店。
    /// 返回带「整批撤销」的结果，沿用语音指令同一套提示 + 撤销机制。
    static func importReceipt(items: [String], storeName: String?, boughtAt: Date,
                              in context: ModelContext) -> ActionResult {
        let store = storeName
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : findOrCreateStore(named: $0, in: context) }

        // 每项入库前的快照，供整批撤销还原
        struct Snapshot {
            let g: Grocery
            let wasNew: Bool
            let status: GroceryStatus
            let onList: Bool
            let boughtAt: Date?
            let store: Supermarket?
            let pinned: Bool
        }
        var snapshots: [Snapshot] = []

        for raw in items {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let existing = fetch(name: name, in: context)
            let g = existing ?? Grocery(name: name, type: StapleHeuristic.type(for: name), isOnShoppingList: false)
            if existing == nil { context.insert(g) }
            snapshots.append(Snapshot(g: g, wasNew: existing == nil,
                                      status: g.status, onList: g.isOnShoppingList,
                                      boughtAt: g.boughtAt, store: g.store, pinned: g.isStorePinned))
            g.status = .have
            g.isOnShoppingList = false
            g.boughtAt = boughtAt
            if let store, !g.isStorePinned { g.store = store }   // 不覆盖用户手动钉的店
        }
        try? context.save()

        guard let first = snapshots.first else {
            return ActionResult(message: "没识别到可入库的商品", undo: nil)
        }
        let msg = snapshots.count == 1 ? "已入库「\(first.g.name)」"
                                       : "已入库 \(snapshots.count) 样"
        return ActionResult(message: msg, undo: {
            for s in snapshots {
                if s.wasNew {
                    context.delete(s.g)
                } else {
                    s.g.status = s.status
                    s.g.isOnShoppingList = s.onList
                    s.g.boughtAt = s.boughtAt
                    s.g.store = s.store
                    s.g.isStorePinned = s.pinned
                }
            }
            try? context.save()
        })
    }

    // ===== 超市管理 =====

    static func deleteSupermarket(_ s: Supermarket, in context: ModelContext) {
        context.delete(s)
        try? context.save()
    }

    static func renameSupermarket(_ s: Supermarket, to newNameRaw: String, in context: ModelContext) {
        let newName = newNameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName.lowercased() != s.name.lowercased() else { return }
        let all = (try? context.fetch(FetchDescriptor<Supermarket>())) ?? []
        if let existing = all.first(where: { $0.name.lowercased() == newName.lowercased() && $0 !== s }) {
            for g in s.groceries ?? [] { g.store = existing }
            context.delete(s)
        } else {
            s.name = newName
        }
        try? context.save()
    }

    // ===== 首次启动预置常备品 =====

    static func seedDefaultStaplesIfNeeded(in context: ModelContext) {
        let key = "hasSeededDefaults"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let defaults = ["盐", "糖", "油", "酱油", "生抽", "老抽", "醋", "蚝油", "料酒", "米", "面粉", "淀粉"]
        for name in defaults {
            if fetch(name: name, in: context) == nil {
                let g = Grocery(name: name, type: .staple, isOnShoppingList: false)
                g.status = .have
                context.insert(g)
            }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}
