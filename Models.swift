import Foundation
import SwiftData

// MARK: - 枚举

enum GroceryType: String, Codable, CaseIterable {
    case staple   // 常备：油盐酱醋米面，默认就是“有”，不该天天维护
    case dry      // 干货：香菇木耳紫菜粉丝等，耐放但会用完
    case fresh    // 生鲜：本周买的、会坏的，需要照看
}

enum GroceryStatus: String, Codable, CaseIterable {
    case have        // 有
    case runningLow  // 快没了
    case none        // 没了（不在库存里）
}

// MARK: - 超市 / 采购地点

@Model
final class Supermarket {
    @Attribute(.unique) var name: String
    var createdAt: Date

    // 删除超市时只把食材的 store 置空（变回“不限超市”），绝不连带删除食材
    @Relationship(deleteRule: .nullify, inverse: \Grocery.store)
    var groceries: [Grocery]?

    init(name: String) {
        self.name = name
        self.createdAt = Date()
    }
}

// MARK: - 食材（清单与库存共用一行，靠状态驱动）

@Model
final class Grocery {
    // 食材身份：同名即同一样东西，天然去重
    @Attribute(.unique) var name: String

    var typeValue: String          // GroceryType
    var statusValue: String        // GroceryStatus
    var isOnShoppingList: Bool

    var store: Supermarket?         // nil = 不限超市
    var isStorePinned: Bool

    var addedToListAt: Date?
    var boughtAt: Date?
    var createdAt: Date

    var type: GroceryType {
        get { GroceryType(rawValue: typeValue) ?? .fresh }
        set { typeValue = newValue.rawValue }
    }
    var status: GroceryStatus {
        get { GroceryStatus(rawValue: statusValue) ?? .none }
        set { statusValue = newValue.rawValue }
    }

    init(name: String,
         type: GroceryType = .fresh,
         store: Supermarket? = nil,
         isOnShoppingList: Bool = true) {
        self.name = name
        self.typeValue = type.rawValue
        self.statusValue = GroceryStatus.none.rawValue
        self.isOnShoppingList = isOnShoppingList
        self.store = store
        self.isStorePinned = false
        self.addedToListAt = Date()
        self.createdAt = Date()
    }
}
