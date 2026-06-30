import Foundation

/// 极简本地断句：把“买西红柿、鸡蛋还有牛肉”拆成 ["西红柿","鸡蛋","牛肉"]。
struct TextParser {
    static let separators = ["、", "，", ",", "；", ";", "还有", "以及", "加上", "再来", "跟", "和"]
    static let leadingStopwords = ["我想买", "我要买", "帮我记一下", "帮我记", "需要买", "记一下", "买点", "买"]

    static func parse(text: String) -> [String] {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for w in leadingStopwords where s.hasPrefix(w) {
            s.removeFirst(w.count)
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        for sep in separators {
            s = s.replacingOccurrences(of: sep, with: "|")
        }
        var seen = Set<String>()
        return s.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { collapseRepeats($0) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    static func collapseRepeats(_ s: String) -> String {
        let chars = Array(s)
        let len = chars.count
        guard len > 1 else { return s }
        for d in 1...(len / 2) {
            guard len % d == 0 else { continue }
            let unit = chars[0..<d]
            if (1..<(len / d)).allSatisfy({ i in chars[(i * d)..<((i + 1) * d)].elementsEqual(unit) }) {
                return String(unit)
            }
        }
        return s
    }
}

// MARK: - 语音指令

enum VoiceCommand {
    case add([String])                              // 默认：买 X
    case delete([String])                           // 删除 X
    case assignStore(items: [String], store: String) // 把 X 放进 Y
    case markOut([String])                          // X 用完了 / 没了
}

/// 轻量关键词规则把一句话解析成结构化指令。够覆盖最常用的几类，
/// 等说法越来越多再换成本地小模型（v1）。
enum VoiceCommandParser {
    static let deleteKeywords = ["删除", "删掉", "删了", "移除", "去掉", "不买了", "不要了"]
    static let dirKeywords    = ["放进", "放到", "放在", "归到", "归入", "归类到"]
    static let outSuffixes    = ["用完了", "用光了", "吃完了", "没有了", "用完", "没了"]

    static func parse(_ raw: String) -> VoiceCommand {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "。.！!？?，, "))
        guard !s.isEmpty else { return .add([]) }

        // 1) 归店：把 X 放进 Y
        for kw in dirKeywords {
            if let r = s.range(of: kw) {
                var left = String(s[s.startIndex..<r.lowerBound])
                let right = String(s[r.upperBound...])
                for lead in ["把", "将"] where left.hasPrefix(lead) { left.removeFirst(lead.count) }
                let items = TextParser.parse(text: left)
                // 只去掉两端空白和标点，别动“中超”里的“中”等字
                let store = right.trimmingCharacters(in: CharacterSet(charactersIn: "。.！!？?，, "))
                if !items.isEmpty && !store.isEmpty {
                    return .assignStore(items: items, store: store)
                }
            }
        }

        // 2) 删除
        for kw in deleteKeywords where s.contains(kw) {
            var rest = s.replacingOccurrences(of: kw, with: "")
            for lead in ["把", "将"] where rest.hasPrefix(lead) { rest.removeFirst(lead.count) }
            let items = TextParser.parse(text: rest)
            if !items.isEmpty { return .delete(items) }
        }

        // 3) 用完了 / 没了
        for suf in outSuffixes where s.hasSuffix(suf) {
            let itemPart = String(s.dropLast(suf.count))
            let items = TextParser.parse(text: itemPart)
            if !items.isEmpty { return .markOut(items) }
        }

        // 4) 默认：加入待买
        return .add(TextParser.parse(text: s))
    }
}

// 已知局限（v0 可接受）：
// - “和/跟”作分隔符可能误伤极少数含字食材（如“和牛”）。
// - 中英混说受单一 locale 限制，识别一般。英文店名建议说中文（如“全食”）或在归店页手动建。
// - 规则按“归店 → 删除 → 用完了 → 加入”的顺序判断，命中即返回。
