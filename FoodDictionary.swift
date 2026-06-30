import Foundation

/// 英文小票商品名 → 中文食材名的本地词典（三层降级第一层）。
/// 快、确定、离线；模型翻过的结果回灌到缓存，下次直接命中、不再调模型。
enum FoodDictionary {

    /// 常见食材 英文关键词(小写) → 中文。单词按 token 精确匹配（避免 price→rice 误伤），
    /// 多词短语（soy sauce）按子串匹配。
    static let builtin: [String: String] = [
        "milk": "牛奶", "egg": "鸡蛋", "eggs": "鸡蛋",
        "tomato": "西红柿", "tomatoes": "西红柿", "spinach": "菠菜",
        "chicken": "鸡肉", "chkn": "鸡肉", "beef": "牛肉", "pork": "猪肉",
        "fish": "鱼", "shrimp": "虾", "tofu": "豆腐",
        "rice": "米", "noodle": "面条", "noodles": "面条", "flour": "面粉",
        "onion": "洋葱", "garlic": "蒜", "ginger": "姜", "potato": "土豆",
        "carrot": "胡萝卜", "cabbage": "卷心菜", "lettuce": "生菜",
        "cucumber": "黄瓜", "pepper": "辣椒", "broccoli": "西兰花",
        "mushroom": "蘑菇", "scallion": "葱", "celery": "芹菜", "eggplant": "茄子",
        "apple": "苹果", "banana": "香蕉", "orange": "橙子", "grape": "葡萄",
        "lemon": "柠檬", "strawberry": "草莓", "watermelon": "西瓜",
        "butter": "黄油", "cheese": "奶酪", "yogurt": "酸奶",
        "oil": "油", "salt": "盐", "sugar": "糖", "vinegar": "醋",
        "soy sauce": "酱油", "bread": "面包"
    ]

    private static let cacheKey = "foodDictCache"

    /// 模型翻译积累的缓存（英文小写 → 中文），回灌后越用越快。
    private static var cache: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: cacheKey) }
    }

    /// 查词典：命中返回中文，未命中 nil（交给模型兜底）。
    static func lookup(_ english: String) -> String? {
        let lower = english.lowercased()
        if let hit = cache[lower] { return hit }
        // 多词关键词（soy sauce）先整体子串匹配
        for (k, v) in builtin where k.contains(" ") && lower.contains(k) { return v }
        // 单词关键词按 token 精确匹配，避免 price→rice 之类误伤
        let tokens = lower.split { !$0.isLetter }.map(String.init)
        for t in tokens where builtin[t] != nil { return builtin[t] }
        return nil
    }

    /// 回灌：把模型翻译过的结果记进缓存。
    static func remember(english: String, chinese: String) {
        let e = english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c = chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, !c.isEmpty else { return }
        var current = cache
        current[e] = c
        cache = current
    }
}
