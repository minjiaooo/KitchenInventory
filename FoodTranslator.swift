import Foundation
import FoundationModels

/// 用 iOS 自带 FoundationModels（设备端 ~3B LLM）把英文小票商品名还原成简洁中文食材名。
/// 它是三层降级里的第二层：词典没命中才调它；调不动（旧机 / 没开 Apple Intelligence /
/// 模型没就绪）就返回 nil，交回校对页手动改。
@available(iOS 26.0, *)
enum FoodTranslator {

    /// 结构化输出：让模型直接给「中文名 + 是否食材」，免得再解析自由文本。
    @Generable
    struct Guess {
        @Guide(description: "简洁的中文食材名，去掉品牌、规格、数量、单位；如果这一行不是食物就留空")
        let chineseName: String

        @Guide(description: "这一行是否是可食用的食材或食品")
        let isFood: Bool
    }

    /// 设备 + 系统是否具备运行条件（机型 / Apple Intelligence 开关 / 模型就绪）。
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// 英文商品名 → 中文食材名；不可用、非食材或失败都返回 nil（降级到手动）。
    static func toChinese(_ english: String) async -> String? {
        guard isAvailable else { return nil }
        let session = LanguageModelSession {
            """
            你是厨房库存助手。用户会给你美国超市小票上的英文商品名，
            常带缩写、品牌、规格和数量（例如 BNLS CHKN BRST、GV 2% MILK GAL、ORG SPINACH）。
            请还原成最简洁的中文食材名（例如 鸡胸肉、牛奶、菠菜），
            只保留食材本身，去掉品牌、规格、数量和单位。
            """
        }
        do {
            let result = try await session.respond(to: english, generating: Guess.self)
            let guess = result.content
            guard guess.isFood else { return nil }
            let name = guess.chineseName.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        } catch {
            return nil
        }
    }
}
