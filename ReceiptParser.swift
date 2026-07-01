import Foundation

// MARK: - 小票解析结果

/// 一张小票 OCR 后解析出的结构化信息。识别天然有噪声，这里只作为
/// 「预览校对页」的初值，最终以用户校对后的结果为准。
struct ParsedReceipt: Identifiable {
    let id = UUID()
    var storeName: String?
    var date: Date?
    var items: [String]
    var note: String? = nil   // 提取来源 / 失败原因，显示在校对页底部便于诊断
}

// MARK: - 小票解析（纯规则，不接模型，可单测）

/// 把 OCR 出来的文本行解析成 商品名 + 店名 + 日期。
/// 规则启发式，必然有误判 —— 所以下游一定要走「预览校对页」让用户增删改，
/// 绝不直接入库（OCR 噪声会把价格行误当食材塞进库存）。
enum ReceiptParser {

    /// 噪声行：含这些词的整行直接丢弃（金额汇总 / 支付方式 / 门店信息）。
    static let noiseKeywords: Set<String> = [
        "小计", "合计", "总计", "总额", "应收", "实收", "实付", "找零", "现金",
        "会员", "积分", "余额", "税", "优惠", "折扣", "满减", "谢谢", "欢迎光临",
        "电话", "地址", "收银", "单号", "流水", "时间", "日期", "数量",
        "subtotal", "total", "tax", "cash", "change", "visa", "debit",
        "credit", "balance", "thank", "member", "savings", "discount",
        "tel", "qty", "amount", "card"
    ]

    static func parse(lines rawLines: [String]) -> ParsedReceipt {
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let store = guessStore(lines)
        return ParsedReceipt(storeName: store,
                             date: guessDate(lines),
                             items: collectItems(lines, excluding: store))
    }

    // 店名：顶部前 4 行里，第一条「不含数字、不像噪声、长度合适」的行。
    private static func guessStore(_ lines: [String]) -> String? {
        for line in lines.prefix(4) {
            guard !isNoise(line) else { continue }
            guard line.rangeOfCharacter(from: .decimalDigits) == nil else { continue }
            if (2...16).contains(line.count) { return line }
        }
        return nil
    }

    // 日期：扫每行的空白分隔 token，命中常见日期格式即返回。
    private static func guessDate(_ lines: [String]) -> Date? {
        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd",
                       "MM/dd/yyyy", "MM-dd-yyyy", "yyyy年MM月dd日"]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        for line in lines {
            for token in line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "　" }) {
                let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "，,。.；;：: "))
                for f in formats {
                    fmt.dateFormat = f
                    if let d = fmt.date(from: t) { return d }
                }
            }
        }
        return nil
    }

    // 商品行：逐行清洗，去价格 / 数量 / 条码后保留像名字的部分；去重保序。
    private static func collectItems(_ lines: [String], excluding store: String?) -> [String] {
        var seen = Set<String>()
        return lines.compactMap { itemName(from: $0) }
                    .filter { store == nil || $0 != store }   // 别把店名当成商品
                    .filter { seen.insert($0.lowercased()).inserted }
    }

    private static func itemName(from line: String) -> String? {
        guard !isNoise(line) else { return nil }
        var s = line
        s = s.replace(#"[¥$￥]\s*\d+(\.\d{1,2})?"#)   // 去货币金额 ¥12.30 / $3.99
        s = s.replace(#"[\d.,*xX×]+\s*$"#)            // 去行尾价格 / 数量列
        s = s.replace(#"^\d{4,}\s*"#)                 // 去行首条码 / 编号
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // 必须含中文或字母、长度合理，才算商品名
        let hasWord = s.range(of: #"[一-龥A-Za-z]"#, options: .regularExpression) != nil
        guard hasWord, (2...20).contains(s.count) else { return nil }
        return s
    }

    private static func isNoise(_ line: String) -> Bool {
        let lower = line.lowercased()
        return noiseKeywords.contains { lower.contains($0) }
    }
}

private extension String {
    /// 正则替换便捷方法（默认替换为空串）。
    func replace(_ pattern: String, with replacement: String = "") -> String {
        replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
}
