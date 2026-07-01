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

    // MARK: - 整单提取（主路径）：整张小票文本一次交给模型，直接吐中文食材列表

    @Generable
    struct Receipt {
        @Guide(description: "小票上所有食品/食材的简洁中文名；已忽略店名、地址、税费、非食品、乱码、水印")
        let foods: [String]
    }

    /// 整单提取失败时的最后错误，用于在校对页显示、诊断真机问题。
    static var lastError: String?

    /// 整张小票 OCR 文本 → 中文食材名列表。模型不可用返回 nil（调用方回退规则解析）。
    static func extractFoods(from lines: [String]) async -> [String]? {
        guard isAvailable else { lastError = "Apple Intelligence 不可用"; return nil }
        // 预清洗：去掉纯数字 / 条码 / 符号行，只留含字母或中文的行，给设备端小模型减负
        let cleaned = lines.filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.count >= 2 && t.range(of: "[A-Za-z一-龥]", options: .regularExpression) != nil
        }
        let text = cleaned.joined(separator: "\n")
        let session = LanguageModelSession {
            """
            下面是一张购物小票的 OCR 文本，可能有噪声和缩写。
            只提取其中的【食品 / 食材】，逐一还原成简洁的中文名。
            必须忽略：店名、地址、电话、会员号、日期时间、小计/税/合计/找零、
            支付与卡号、条码流水号、非食品（肥皂/沐浴/护理/日用品）、看不懂的乱码、图片水印。
            美国小票缩写要还原：如 BNLS SKNLS CKN=鸡胸肉、ORG=有机、KS 或 Kirkland 等自牌前缀去掉。
            拿不准是不是食品就宁可不放。只输出食品的中文名。
            """
        }
        do {
            let result = try await session.respond(to: text, generating: Receipt.self)
            lastError = nil
            return result.content.foods
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }
}
