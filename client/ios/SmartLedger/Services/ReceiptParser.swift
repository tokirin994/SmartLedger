import Foundation

struct ReceiptParser {
    struct Rule {
        let keyword: String
        let tokens: [String]
        let path: [String]
    }

    private let rules: [Rule] = [
        .init(keyword: "奶茶咖啡", tokens: ["瑞幸", "库迪", "星巴克", "咖啡", "奶茶", "喜茶", "茶百道", "霸王茶姬", "蜜雪冰城"], path: ["餐饮", "奶茶咖啡"]),
        .init(keyword: "日常吃饭", tokens: ["餐饮", "午饭", "晚饭", "早餐", "外卖", "快餐", "饭店", "美团", "猪脚饭", "烧腊", "米线", "面馆", "快餐店", "小吃", "烧烤", "盖饭", "粉面", "烤肉", "自助餐"], path: ["餐饮", "日常吃饭"]),
        .init(keyword: "吃好的", tokens: ["火锅", "烤肉", "自助", "海鲜", "西餐"], path: ["餐饮", "吃好的"]),
        .init(keyword: "水果零食", tokens: ["水果", "零食", "盒马", "山姆", "超市", "便利店"], path: ["水果零食"]),
        .init(keyword: "买菜做饭", tokens: ["买菜", "菜市场", "朴朴", "叮咚买菜", "生鲜"], path: ["餐饮", "买菜做饭"]),
        .init(keyword: "打车", tokens: ["滴滴", "打车", "专车", "出租车", "代驾"], path: ["交通", "打车"]),
        .init(keyword: "地铁公交", tokens: ["地铁", "公交", "乘车码"], path: ["交通", "地铁公交"]),
        .init(keyword: "火车机票", tokens: ["火车票", "机票", "12306", "航旅", "南航", "东航", "国航"], path: ["交通", "火车机票"]),
        .init(keyword: "房租", tokens: ["房租", "租金"], path: ["居住", "房租"]),
        .init(keyword: "水电网", tokens: ["电费", "水费", "燃气", "宽带", "话费"], path: ["居住", "水电网"]),
        .init(keyword: "日用品", tokens: ["日用品", "纸巾", "洗发水", "沐浴露", "淘宝", "天猫", "乐高"], path: ["购物", "日用品"]),
        .init(keyword: "服饰", tokens: ["优衣库", "服饰", "鞋", "裤", "衣服"], path: ["购物", "服饰"]),
        .init(keyword: "数码", tokens: ["数码", "手机", "电脑", "耳机", "京东", "Apple"], path: ["购物", "数码"]),
        .init(keyword: "电影演出", tokens: ["电影", "演出", "猫眼", "影院", "电影资料馆", "小西天", "影城", "票务"], path: ["娱乐", "电影演出"]),
        .init(keyword: "旅行", tokens: ["酒店", "旅行", "携程"], path: ["娱乐", "旅行"]),
        .init(keyword: "运动健身", tokens: ["健身", "瑜伽", "羽毛球", "游泳", "Keep"], path: ["娱乐", "运动健身"]),
        .init(keyword: "书籍资料", tokens: ["当当", "书店", "图书"], path: ["学习", "书籍资料"]),
        .init(keyword: "课程培训", tokens: ["课程", "培训", "知识星球", "极客时间"], path: ["学习", "课程培训"]),
        .init(keyword: "礼物", tokens: ["礼物", "礼品"], path: ["人情往来", "礼物"]),
        .init(keyword: "红包", tokens: ["红包", "份子钱"], path: ["人情往来", "红包"]),
        .init(keyword: "工资", tokens: ["工资", "薪资", "salary"], path: ["收入", "工资"]),
        .init(keyword: "奖金", tokens: ["奖金", "绩效", "年终奖"], path: ["收入", "奖金"]),
        .init(keyword: "退款入账", tokens: ["退款", "退回", "返还"], path: ["收入", "退款入账"]),
        .init(keyword: "转账收入", tokens: ["转账", "收款", "朋友转来"], path: ["收入", "转账收入"]),
    ]

    private let detailFieldLabels = ["当前状态", "支付时间", "商品", "商品说明", "商户全称", "收单机构", "支付方式", "付款方式", "支付渠道", "交易单号", "商户单号", "订单号", "优惠", "原价", "收款方", "收款方备注", "交易对方", "商家", "转账时间", "转账单号", "零钱余额", "扣款说明"]

    func parse(rawText: String) -> OCRImportResult {
        let lines = normalizedLines(from: rawText)
        if isWeChatTransferDetailPage(lines) {
            return parseWeChatTransferDetail(lines: lines)
        }
        if isAlipayDetailPage(lines) {
            return parseAlipayDetail(lines: lines)
        }
        if isLikelyDetailPage(lines) {
            return parseDetail(lines: lines)
        }
        if isAlipayListPage(lines), let first = parseAlipayList(lines: lines).first {
            return first
        }
        if let first = parseMultiple(rawText: rawText).first {
            return first
        }
        return parseFallback(lines: lines)
    }

    func parseMultiple(rawText: String) -> [OCRImportResult] {
        let lines = normalizedLines(from: rawText)
        if isWeChatTransferDetailPage(lines) {
            return [parseWeChatTransferDetail(lines: lines)]
        }
        if isAlipayDetailPage(lines) {
            return [parseAlipayDetail(lines: lines)]
        }
        if isLikelyDetailPage(lines) {
            return [parseDetail(lines: lines)]
        }
        if isAlipayListPage(lines) {
            return parseAlipayList(lines: lines)
        }
        return parseList(lines: lines)
    }

    private func normalizedLines(from rawText: String) -> [String] {
        rawText
            .split(whereSeparator: \.isNewline)
            .map { normalizeLine(String($0)) }
            .filter { !$0.isEmpty }
    }

    private func normalizeLine(_ input: String) -> String {
        input
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "‑", with: "-")
            .replacingOccurrences(of: "‑", with: "-")
            .replacingOccurrences(of: "¥70‑00", with: "¥70.00")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLikelyDetailPage(_ lines: [String]) -> Bool {
        let score = detailFieldLabels.reduce(0) { partial, field in
            partial + (lines.contains(where: { $0.contains(field) }) ? 1 : 0)
        }
        return score >= 4
    }

    private func isWeChatTransferDetailPage(_ lines: [String]) -> Bool {
        lines.contains(where: { $0.contains("零钱明细") }) &&
        lines.contains(where: { $0.contains("转账时间") || $0.contains("收款方备注") })
    }

    private func isAlipayDetailPage(_ lines: [String]) -> Bool {
        lines.contains(where: { $0.contains("账单详情") }) &&
        lines.contains(where: { $0.contains("付款方式") || $0.contains("扣款说明") })
    }

    private func isAlipayListPage(_ lines: [String]) -> Bool {
        lines.contains(where: { $0.contains("搜索交易记录") }) &&
        lines.contains(where: { $0.contains("收支分析") })
    }

    private func parseWeChatTransferDetail(lines: [String]) -> OCRImportResult {
        let text = lines.joined(separator: "\n")
        let fieldMap = makeFieldMap(lines: lines)
        let title = lines.first(where: { $0.contains("付款") || $0.contains("转给") }) ?? "转账详情"

        let amountLine = lines.first(where: { $0.range(of: #"^‑?\d+(?:\.\d{1,2})$"#, options: .regularExpression) != nil })
        let amount = extractCurrency(from: amountLine)
        let happenedAt = extractDate(from: extractWeChatTransferFieldValue(label: "转账时间", lines: lines) ?? fieldMap["转账时间"] ?? text)
        let paymentMethod = normalizePaymentMethod(extractWeChatTransferFieldValue(label: "支付方式", lines: lines) ?? fieldMap["支付方式"] ?? fieldMap["付款方式"] ?? "零钱")
        let merchant = normalizeListMerchant(title) ?? title
        let kind = inferKind(in: text, lines: lines, amountLine: amountLine, fallback: .expense)
        let detailKeys = ["当前状态", "收款方备注", "支付方式", "转账时间", "转账单号", "零钱余额"]
        let details = detailKeys
            .compactMap { (key: String) -> OCRLineItem? in
                let value = extractWeChatTransferFieldValue(label: key, lines: lines) ?? fieldMap[key]
                guard let value, !value.isEmpty else { return nil }
                return OCRLineItem(label: key, value: value)
            }
        let classified = normalizeClassifiedResult(kind: kind, classify(text: [title, merchant, paymentMethod, extractWeChatTransferFieldValue(label: "收款方备注", lines: lines), text].compactMap { $0 }.joined(separator: "\n")))

        return OCRImportResult(
            amount: amount,
            kind: kind,
            merchant: merchant,
            paymentMethod: paymentMethod,
            title: title,
            happenedAt: happenedAt,
            categoryKeyword: classified.keyword,
            categoryPath: classified.path,
            details: details,
            confidence: 0.96,
            rawLines: Array(lines.prefix(30)),
            originalAmount: nil,
            discountAmount: nil
        )
    }

    private func parseAlipayDetail(lines: [String]) -> OCRImportResult {
        let text = lines.joined(separator: "\n")
        let amountLine = lines.first(where: { $0.range(of: #"^‑?\d+(?:\.\d{1,2})$"#, options: .regularExpression) != nil })
        let amount = extractCurrency(from: amountLine)
        let happenedAt = lines.first(where: { $0.range(of: #"\d{4}-\d{2}-\d{2}\s*\d{2}:\d{2}(?::\d{2})?"#, options: .regularExpression) != nil }).flatMap { extractDate(from: $0) }
        let paymentMethod = extractAlipayDetailPaymentMethod(from: lines)
        let merchant = extractAlipayDetailMerchant(from: lines)
        let title = extractAlipayDetailTitle(from: lines) ?? merchant
        let kind = inferKind(in: text, lines: lines, amountLine: amountLine, fallback: .expense)
        let details = buildAlipayDetailItems(lines: lines, happenedAt: happenedAt, paymentMethod: paymentMethod)
        let classified = normalizeClassifiedResult(kind: kind, classify(text: [title, merchant, paymentMethod, text].compactMap { $0 }.joined(separator: "\n")))

        return OCRImportResult(
            amount: amount,
            kind: kind,
            merchant: merchant,
            paymentMethod: paymentMethod,
            title: title,
            happenedAt: happenedAt,
            categoryKeyword: classified.keyword,
            categoryPath: classified.path,
            details: details,
            confidence: 0.95,
            rawLines: Array(lines.prefix(40)),
            originalAmount: nil,
            discountAmount: nil
        )
    }

    private func parseAlipayList(lines: [String]) -> [OCRImportResult] {
        let filtered = lines.filter { !isAlipayListNoiseLine($0) }
        let currentYear = Calendar.current.component(.year, from: Date())
        var results: [OCRImportResult] = []

        for section in buildAlipayListSections(from: filtered) {
            let items = parseAlipayListItems(in: section.lines, expenseTotal: section.expenseTotal)
            for (itemIndex, item) in items.enumerated() {
                let rawAmount = item.amountText.flatMap { extractSignedAmount(from: $0) } ?? item.amountText.flatMap { text in extractCurrency(from: text).map { -$0 } } ?? {
                    if items.count == 1, let total = section.expenseTotal { return -abs(total) }
                    return nil
                }()
                guard let amount = rawAmount else { continue }
                let happenedAt = parseAlipayListDate(item.dateLine, fallbackYear: currentYear)

                let kind: FlowType = amount < 0 ? .expense : .income
                let merchant = meaningfulAlipayListMerchant(provider: item.provider, title: item.title)
                let paymentMethod: String? = "支付宝"
                let classified = normalizeClassifiedResult(kind: kind, classify(text: [item.title, merchant, item.category, item.provider].compactMap { $0 }.joined(separator: "\n")))

                results.append(
                    OCRImportResult(
                        amount: abs(amount),
                        kind: kind,
                        merchant: merchant,
                        paymentMethod: paymentMethod,
                        title: item.title,
                        happenedAt: happenedAt,
                        categoryKeyword: classified.keyword,
                        categoryPath: classified.path,
                        details: [
                            OCRLineItem(label: "识别来源", value: "支付宝列表页"),
                            OCRLineItem(label: "平台", value: item.provider ?? "支付宝"),
                            OCRLineItem(label: "分类", value: item.category ?? "未识别"),
                            OCRLineItem(label: "时间", value: item.dateLine)
                        ],
                        confidence: itemIndex == 0 && items.count == 1 ? 0.9 : 0.87,
                        rawLines: [item.provider ?? "", item.title, item.category ?? "", item.dateLine, item.amountText ?? ""],
                        originalAmount: nil,
                        discountAmount: nil
                    )
                )
            }
        }
        return results
    }

    private func parseDetail(lines: [String]) -> OCRImportResult {
        let text = lines.joined(separator: "\n")
        let fieldMap = makeFieldMap(lines: lines)
        let amount = extractDetailAmount(from: lines)
        let originalAmount = extractOriginalAmount(from: lines, fieldMap: fieldMap)
        let discountAmount = extractDiscountAmount(from: lines, fieldMap: fieldMap)
        let happenedAt = extractDate(from: fieldMap["支付时间"] ?? fieldMap["转账时间"] ?? text)
        let merchant = preferredDetailMerchant(fieldMap: fieldMap, lines: lines)
        let title = preferredDetailTitle(fieldMap: fieldMap, lines: lines, merchant: merchant)
        let paymentMethod = extractPaymentMethod(fieldMap: fieldMap, lines: lines)
        let kind = detectKind(in: text)
        let details = detailItems(from: fieldMap)
        let (categoryKeyword, categoryPath, categoryConfidence) = classify(text: [title, merchant, paymentMethod, fieldMap["商品"], fieldMap["商品说明"], text].compactMap { $0 }.joined(separator: "\n"))
        let confidence = min(0.45 + (amount != nil ? 0.2 : 0) + (merchant != nil ? 0.15 : 0) + categoryConfidence, 0.99)

        return OCRImportResult(
            amount: amount,
            kind: kind,
            merchant: merchant,
            paymentMethod: paymentMethod,
            title: title,
            happenedAt: happenedAt,
            categoryKeyword: categoryKeyword,
            categoryPath: categoryPath,
            details: details,
            confidence: confidence,
            rawLines: Array(lines.prefix(30)),
        originalAmount: originalAmount,
        discountAmount: discountAmount
    )
}

private func parseList(lines: [String]) -> [OCRImportResult] {
    var results: [OCRImportResult] = []
    var currentMonth = Calendar.current.component(.month, from: Date())
    let currentYear = Calendar.current.component(.year, from: Date())
    let cleaned = lines.filter { !isNoiseLine($0) }
    let pagePaymentMethod = inferListPaymentMethod(fromPageLines: lines)

    var records: [(title: String, dateLine: String, month: Int)] = []
    var index = 0
    while index < cleaned.count {
        let line = cleaned[index]

        if let month = extractMonthHeader(from: line) {
            currentMonth = month
            index += 1
            continue
        }

        guard index + 1 < cleaned.count else {
            index += 1
            continue
        }

        if isTransactionTitleLine(line), isListDateLine(cleaned[index + 1]) {
            records.append((title: line, dateLine: cleaned[index + 1], month: currentMonth))
            index += 2
        } else {
            index += 1
        }
    }

    let amountLines = cleaned.filter { line in
        extractSignedAmount(from: line) != nil && !isBalanceLine(line)
    }

    guard !records.isEmpty, amountLines.count >= records.count else {
        return []
    }

    for idx in records.indices {
        guard let amount = extractSignedAmount(from: amountLines[idx]),
              let happenedAt = parseListDate(records[idx].dateLine, fallbackYear: currentYear, monthOverride: records[idx].month) else {
            continue
        }

        let kind: FlowType = amount < 0 ? .expense : .income
        let displayAmount = abs(amount)
        let title = records[idx].title
        let merchant = normalizeListMerchant(title)
        let paymentMethod = inferListPaymentMethod(from: title, fallback: pagePaymentMethod)
        let classified = normalizeClassifiedResult(kind: kind, classify(text: [title, merchant, paymentMethod].compactMap { $0 }.joined(separator: "\n")))
        let categoryKeyword = classified.keyword
        let categoryPath = classified.path
        let categoryConfidence = classified.confidence

        results.append(
            OCRImportResult(
                amount: displayAmount,
                kind: kind,
                merchant: merchant,
                paymentMethod: paymentMethod,
                title: title,
                happenedAt: happenedAt,
                categoryKeyword: categoryKeyword,
                categoryPath: categoryPath,
                details: [
                    OCRLineItem(label: "识别来源", value: "列表页批量识别"),
                    OCRLineItem(label: "时间", value: records[idx].dateLine),
                    OCRLineItem(label: "金额", value: String(format: "%.2f", displayAmount))
                ],
                confidence: min(0.58 + categoryConfidence, 0.95),
                rawLines: [title, records[idx].dateLine, amountLines[idx]],
                originalAmount: nil,
                discountAmount: nil
            )
        )
    }

    return results
}

private func parseFallback(lines: [String]) -> OCRImportResult {
    let text = lines.joined(separator: "\n")
    let kind = detectKind(in: text)
    let amount = extractFallbackAmount(from: lines)
    let merchant = extractFallbackMerchant(from: lines)
    let paymentMethod = extractPaymentMethod(fieldMap: makeFieldMap(lines: lines), lines: lines)
    let details = extractFallbackDetails(from: lines)
    let happenedAt = extractDate(from: text)
    let classified = normalizeClassifiedResult(kind: kind, classify(text: [text, merchant, paymentMethod].compactMap { $0 }.joined(separator: "\n")))
    let categoryKeyword = classified.keyword
    let categoryPath = classified.path
    let categoryConfidence = classified.confidence
    let confidenceBase = (amount != nil ? 0.25 : 0.0) + (merchant != nil ? 0.15 : 0.0)
    let confidence = min(0.2 + confidenceBase + categoryConfidence, 0.98)
    let title = merchant ?? categoryPath.last ?? (kind == .expense ? "图片导入账单" : "图片导入收入")

    return OCRImportResult(
        amount: amount,
        kind: kind,
        merchant: merchant,
        paymentMethod: paymentMethod,
        title: title,
        happenedAt: happenedAt,
        categoryKeyword: categoryKeyword,
        categoryPath: categoryPath,
        details: details,
        confidence: confidence,
        rawLines: Array(lines.prefix(20)),
        originalAmount: nil,
        discountAmount: nil
    )
}

private func makeFieldMap(lines: [String]) -> [String: String] {
    var map: [String: String] = [:]
    var i = 0
    while i < lines.count {
        let current = lines[i]
        if detailFieldLabels.contains(current) {
            var labels: [String] = []
            var j = i
            while j < lines.count, detailFieldLabels.contains(lines[j]) {
                labels.append(lines[j])
                j += 1
            }

            var values: [String] = []
            var k = j
            while k < lines.count, !detailFieldLabels.contains(lines[k]), values.count < labels.count {
                let value = lines[k]
                if !isNoiseLine(value) {
                    values.append(value)
                }
                k += 1
            }

            for (offset, label) in labels.enumerated() where offset < values.count {
                map[label] = values[offset]
            }
            i = max(j, k)
            continue
        }
         i += 1
       }
       for (index, line) in lines.enumerated() {
         for label in detailFieldLabels where line == label || line.contains(label + ": ") || line.contains(label +
 ":") {
           if map[label]?.isEmpty == false { continue }
           if let inline = valueAfterColon(in: line), !inline.isEmpty {
             map[label] = inline
           } else if index + 1 < lines.count, !detailFieldLabels.contains(lines[index + 1]) {
             map[label] = lines[index + 1]
           }
         }
       }
       return map
     }
     private func valueAfterColon(in line: String) -> String? {
       let parts = line.components(separatedBy: CharacterSet(charactersIn: ":: "))
       guard parts.count >= 2 else { return nil }
       return parts.dropFirst().joined(separator: ": ").trimmingCharacters(in: .whitespacesAndNewlines)
     }

     private func extractDetailAmount(from lines: [String]) -> Double? {
       let strongCandidates = lines.compactMap { line -> Double? in
         guard line.contains("-") || line.contains("¥") || line.contains("￥") else { return nil }
         guard !line.contains("原价"), !line.contains("优惠"), !line.contains("余额") else { return nil }
         guard line.range(of: #"^-?\s*[¥￥]?\s*\d+(?:\.\d{1,2})?$"#, options: .regularExpression) != nil else { return
 nil }
         return extractCurrency(from: line)
       }
       if let amount = strongCandidates.first(where: { $0 > 0.01 }) {
         return amount
       }
       return extractFallbackAmount(from: lines)
     }

     private func extractOriginalAmount(from lines: [String], fieldMap: [String: String]) -> Double? {
       if let value = extractCurrency(from: fieldMap["原价"]) { return value }
       for (idx, line) in lines.enumerated() where line == "原价" {
         if idx + 1 < lines.count, let value = extractCurrency(from: lines[idx + 1]) { return value }
       }
       return nil
     }

     private func extractDiscountAmount(from lines: [String], fieldMap: [String: String]) -> Double? {
       if let directLine = lines.first(where: { $0.contains("优惠") && ($0.contains("¥") || $0.contains("￥")) &&
 !$0.contains("原价") }) {
         if let value = extractCurrency(from: directLine) { return value }
       }
       if let value = extractCurrency(from: fieldMap["优惠"]) {
         if value < 10_000 { return value }
       }
       for (idx, line) in lines.enumerated() where line == "优惠" {
         if idx + 1 < lines.count, let value = extractCurrency(from: lines[idx + 1]) { return value }
       }
       if let line = lines.first(where: { $0.contains("优惠") && ($0.contains("¥") || $0.contains("￥")) }) {
         return extractCurrency(from: line)
       }
       return nil
     }

     private func extractFallbackAmount(from lines: [String]) -> Double? {
       var candidates: [(Double, Int)] = []
       for (idx, line) in lines.enumerated() {
         if shouldIgnoreNumericLine(line) { continue }
         if let value = extractCurrency(from: line) {
           let weight = amountWeight(for: line, index: idx)
           candidates.append((value, weight))
         }
       }
       return candidates.sorted { lhs, rhs in
         lhs.1 == rhs.1 ? lhs.0 > rhs.0 : lhs.1 > rhs.1
       }.first?.0
     }

     private func amountWeight(for line: String, index: Int) -> Int {
       var weight = 100 - index
       if line.contains("支付") || line.contains("支出") || line.contains("收款") || line.contains("收入") ||
 line.contains("实付") || line.contains("合计") {
         weight += 200
       }
       if line.contains("-") { weight += 120 }
       if line.contains("¥") || line.contains("￥") { weight += 50 }
       if line == "账单" || line == "零钱明细" { weight -= 200 }
       return weight
     }

     private func shouldIgnoreNumericLine(_ line: String) -> Bool {
       if line.contains("单号") || line.contains("尾号") || line.contains("卡号") || line.contains("账单号") ||
 line.contains("余额") {
         return true
       }
       if line.range(of: #"^\d{1,2}月\d{2,4}$"#, options: .regularExpression) != nil { return true }
       if line.range(of: #"^\d{4}年\d{1,2}月(?:\s*\d{1,2})?(?:\.\d{2})?$"#, options:
 .regularExpression) != nil { return true }
       if line.range(of: #"^\d{1,2}月\d{1,2}日\s+\d{1,2}:\d{2}$"#, options: .regularExpression) != nil { return true }
       return false
     }

     private func extractCurrency(from text: String?) -> Double? {
       guard let text else { return nil }
       let normalized = text.replacingOccurrences(of: ",", with: "")
       if let range = normalized.range(of: #"^-?\s*[¥￥]?\s*\d+(?:\.\d{1,2})#"#, options: .regularExpression) {
         let value = String(normalized[range])
           .replacingOccurrences(of: "¥", with: "")
           .replacingOccurrences(of: "￥", with: "")
           .replacingOccurrences(of: " ", with: "")
         return abs(Double(value) ?? 0)
       }
       return nil
     }

     private func extractSignedAmount(from text: String) -> Double? {
       let normalized = text.replacingOccurrences(of: ",", with: "")
       guard let range = normalized.range(of: #"^[-+]\d+(?:\.\d{1,2})#"#, options: .regularExpression) else { return nil }
       return Double(String(normalized[range]))
     }

     private func detectKind(in text: String) -> FlowType {
       let incomeKeywords = ["收入", "收款", "退款", "入账", "到账", "转入"]
       let expenseKeywords = ["支出", "付款", "支付", "扣款", "消费"]
       let incomeScore = incomeKeywords.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }
       let expenseScore = expenseKeywords.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }
       return incomeScore > expenseScore ? .income : .expense
     }

     private func preferredDetailMerchant(fieldMap: [String: String], lines: [String]) -> String? {
       if let merchant = fieldMap["商户全称"], !merchant.isEmpty { return merchant }
       if let merchant = fieldMap["收款方"], !merchant.isEmpty { return merchant }
       if let merchant = fieldMap["交易对方"], !merchant.isEmpty { return merchant }
       return lines.first(where: { line in
         !isNoiseLine(line) &&
         !detailFieldLabels.contains(line) &&
         line.range(of: #"[\u4e00-\u9fffA-Za-z]"#, options: .regularExpression) != nil &&
         !["账单", "零钱明细", "账单服务", "支付成功"].contains(line)
       })
     }

     private func preferredDetailTitle(fieldMap: [String: String], lines: [String], merchant: String?) -> String? {
       if let head = lines.first(where: {
         $0 != "账单" &&
         $0.range(of: #"[\u4e00-\u9fffA-Za-z]"#, options: .regularExpression) != nil &&
         !isNoiseLine($0) &&
         !$0.contains("公司") &&
         !$0.contains("支付科技") &&
         !$0.contains("优惠") &&
         !$0.contains("支付成功") &&
         !$0.contains("信用卡") &&
         !$0.contains("银行卡")
       }) {
         return head
       }
       if let product = fieldMap["商品"], !product.isEmpty, !detailFieldLabels.contains(product),
 !product.contains("商户全称") {
         return product
       }
       if let product = fieldMap["商品说明"], !product.isEmpty, !detailFieldLabels.contains(product) {
         return product
       }
       return merchant
     }

     private func extractPaymentMethod(fieldMap: [String: String], lines: [String]) -> String? {
       for key in ["支付方式", "付款方式", "支付渠道"] {
         if let value = fieldMap[key], !value.isEmpty {
           return normalizePaymentMethod(value)
         }
       }
       if let hit = lines.first(where: { $0.contains("银行卡") || $0.contains("信用卡") || $0.contains("储蓄卡") ||
 $0.contains("微信零钱") || $0.contains("支付宝余额") || $0.contains("花呗") || $0.contains("微信支付") ||
 $0.contains("支付宝") || $0.contains("云闪付") }) {
         return normalizePaymentMethod(hit)
       }
       return nil
     }

     private func normalizePaymentMethod(_ raw: String) -> String {
       let text = raw
         .replacingOccurrences(of: "支付方式", with: "")
         .replacingOccurrences(of: "付款方式", with: "")
         .replacingOccurrences(of: "支付渠道", with: "")
         .replacingOccurrences(of: ":", with: "")
         .replacingOccurrences(of: "：", with: "")
         .replacingOccurrences(of: ">", with: "")
         .replacingOccurrences(of: "＞", with: "")
         .replacingOccurrences(of: ",", with: "")
         .trimmingCharacters(in: .whitespacesAndNewlines)

       if text.contains("微信零钱") { return "微信零钱" }
       if text.contains("支付宝余额") { return "支付宝余额" }
       if text.contains("微信支付") { return "微信支付" }
       if text.contains("花呗") { return "花呗" }
       if text.contains("支付宝") { return text }
       if text.contains("信用卡") || text.contains("储蓄卡") || text.contains("银行卡") { return text }
       if text.contains("云闪付") { return "云闪付" }
       return text
     }

     private func detailItems(from fieldMap: [String: String]) -> [OCRLineItem] {
       ["当前状态", "支付时间", "商品", "商品说明", "商户全称", "收单机构", "支付方式", "付款方式", "支付渠道", "原价", "优惠"]
         .compactMap { key in
           guard let value = fieldMap[key], !value.isEmpty else { return nil }
           return OCRLineItem(label: key, value: value)
         }
     }

     private func isListDateLine(_ line: String) -> Bool {
       line.range(of: #"^\d{1,2}月\d{1,2}日\s+\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
     }

     private func extractDate(from text: String?) -> Date? {
       guard let text else { return nil }
       let formats = [
         "yyyy年M月d日 HH:mm:ss",
         "yyyy年M月d日 HH:mm",
         "yyyy‑MM‑dd HH:mm:ss",
         "yyyy‑MM‑dd HH:mm",
         "yyyy-MM-dd HH:mm:ss",
         "yyyy-MM-dd HH:mm",
         "M月d日 HH:mm"
       ]
       for format in formats {
         let formatter = DateFormatter()
         formatter.locale = Locale(identifier: "zh_CN")
         formatter.timeZone = .current
         formatter.dateFormat = format
         if let date = formatter.date(from: text) {
           if format == "M月d日 HH:mm" {
             let calendar = Calendar.current
             let year = calendar.component(.year, from: Date())
             var comps = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
             comps.year = year
             return calendar.date(from: comps)
           }
           return date
         }
       }
       return nil
     }

     private func extractMonthHeader(from line: String) -> Int? {
       let regex = try? NSRegularExpression(pattern: #"^(\d{4})年(\d{1,2})月#"#)
       let ns = line as NSString
       guard let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
       match.numberOfRanges > 1 else {
         return nil
       }
       return Int(ns.substring(with: match.range(at: 1)))
     }

     private func parseListDate(_ line: String, fallbackYear: Int, monthOverride: Int) -> Date? {
       let regex = try? NSRegularExpression(pattern: #"^(\d{1,2})月(\d{1,2})日\s+(\d{1,2}):(\d{2})#"#)
       let ns = line as NSString
       guard let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
       match.numberOfRanges == 5 else {
         return nil
       }
       let month = Int(ns.substring(with: match.range(at: 1))) ?? monthOverride
       let day = Int(ns.substring(with: match.range(at: 2))) ?? 1
       let hour = Int(ns.substring(with: match.range(at: 3))) ?? 0
       let minute = Int(ns.substring(with: match.range(at: 4))) ?? 0
       var comps = DateComponents()
       comps.year = fallbackYear
       comps.month = month
       comps.day = day
       comps.hour = hour
       comps.minute = minute
       return Calendar.current.date(from: comps)
     }

     private func isTransactionTitleLine(_ line: String) -> Bool {
       guard line.range(of: #"[\u4e00-\u9fffA‑Za‑z]"#, options: .regularExpression) != nil else { return false }
       return !isNoiseLine(line) && !isBalanceLine(line) && extractMonthHeader(from: line) == nil && !line.contains("年")
     }

     private func normalizeListMerchant(_ title: String) -> String? {
       if title.contains("付款‑") {
         return title.components(separatedBy: "付款‑").last
       }
       if title.contains("转给") {
         return title.components(separatedBy: "转给").last
       }
       if title.contains("‑给") {
         return title.components(separatedBy: "‑给").last
       }
       return title
     }

     private func inferListPaymentMethod(from title: String, fallback: String?) -> String? {
       if title.contains("支付宝") { return "支付宝" }
       if title.contains("微信零钱") || title.contains("零钱") { return "微信零钱" }
       if title.contains("收款") || title.contains("扫码") || title.contains("微信") { return "微信" }
       return fallback
     }

     private func inferListPaymentMethod(fromPageLines lines: [String]) -> String? {
       let text = lines.joined(separator: "\n")
       if text.contains("支付宝") { return "支付宝" }
       if text.contains("微信零钱") || text.contains("零钱") { return "微信零钱" }
       if text.contains("微信") { return "微信" }
       return nil
     }

     private func inferKind(in text: String, lines: [String], amountLine: String?, fallback: FlowType) -> FlowType {
       if text.contains("付款") || text.contains("支出") || text.contains("支付成功") || text.contains("扫码付款") { return .expense }
       if text.contains("收款") && !text.contains("付款") { return .income }
       if let amountLine, amountLine.contains("-") { return .expense }
       return fallback
     }

     private func extractAlipayDetailMerchant(from lines: [String]) -> String? {
       if let nick = lines.first(where: { $0.range(of: #"^[A‑Za‑z0‑9*]{3,}$"#, options: .regularExpression) != nil }) {
         return nick
       }
       return lines.first(where: { $0.contains("淘宝") || $0.contains("天猫") || $0.contains("支付宝") })
     }

     private func extractAlipayDetailTitle(from lines: [String]) -> String? {
       guard let start = lines.firstIndex(where: { $0.contains("交易详情") }) else { return nil }
       var titleParts: [String] = []
       for line in lines.dropFirst(start + 1) {
         if isAlipayDetailTitleStopLine(line) { break }
         let cleaned = cleanAlipayDetailTitleLine(line)
         guard !cleaned.isEmpty else { continue }
         titleParts.append(cleaned)
         if titleParts.count >= 2 { break }
       }
       guard !titleParts.isEmpty else { return nil }
       return titleParts.joined(separator: "")
     }

     private func buildAlipayDetailItems(lines: [String], happenedAt: Date?, paymentMethod: String?) -> [OCRLineItem] {
       var items: [OCRLineItem] = []
       if let happenedAt {
         items.append(OCRLineItem(label: "支付时间", value: happenedAt.formatted(date: .numeric, time: .standard)))
       }
       if let paymentMethod {
         items.append(OCRLineItem(label: "付款方式", value: paymentMethod))
       }
       if let deduction = extractAlipayDeductionNote(from: lines) {
         items.append(OCRLineItem(label: "扣款说明", value: deduction))
       }
       return items
     }

     private func isAlipayListNoiseLine(_ line: String) -> Bool {
       let noiseKeywords = [
         "搜索交易记录", "全部", "支出", "转账", "退款", "收入", "搜索", "筛选", "订单", "可切换账号查询账单",
         "收支分析", "本月已省", "账单月报", "贴纸", "等待确认收货", "少", "•••"
       ]
       if noiseKeywords.contains(where: line.contains) { return true }
       if line.range(of: #"^\d{1,2}月$"#, options: .regularExpression) != nil { return false }
       return isNoiseLine(line)
     }

     private func extractSimpleMonthHeader(from line: String) -> Int? {
       let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
       let pattern = #"^(\d{1,2})月(?:[., … : ]*)$"#
       let ns = trimmed as NSString
       if let regex = try? NSRegularExpression(pattern: pattern),
         let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
         match.numberOfRanges > 1 {
           return Int(ns.substring(with: match.range(at: 1)))
       }
       return nil
     }

     private func extractMonthExpenseTotal(around index: Int, in lines: [String]) -> Double? {
       let slice = lines.dropFirst(index).prefix(6)
       for line in slice {
         if line.range(of: #"^¥[\d,]+(?:\.\d{1,2})?$"#, options: .regularExpression) != nil {
           return extractCurrency(from: line)
         }
       }
       return nil
     }

     private func isAlipayDateLine(_ line: String) -> Bool {
       line.range(of: #"^\d{2}-\d{2}\s+\d{2}:\d{2}$"#, options: .regularExpression) != nil
     }

     private func nearestAlipayTitle(before index: Int, in lines: [String]) -> String? {
       guard index > 0 else { return nil }
       var cursor = index - 1
       while cursor >= 0 {
         let candidate = lines[cursor]
         if isAlipayDateLine(candidate) || extractSimpleMonthHeader(from: candidate) != nil { break }
         if candidate.range(of: #"[\u4e00‑\u9fffA‑Za‑z]"#, options: .regularExpression) != nil,
           !candidate.contains("天猫"),
           !candidate.contains("淘"),
           !candidate.contains("阖豆"),
           !candidate.contains("保险"),
           !candidate.contains("日用百货") {
             return candidate
         }
         cursor -= 1
       }
       return nil
     }

     private func nearestAlipayCategory(before index: Int, in lines: [String]) -> String? {
       guard index > 0 else { return nil }
       var cursor = index - 1
       while cursor >= 0 {
         let candidate = lines[cursor]
         if isAlipayDateLine(candidate) || extractSimpleMonthHeader(from: candidate) != nil { break }
         if ["日用百货", "其他", "保险"].contains(candidate) {
           return candidate
         }
         cursor -= 1
       }
       return nil
     }

     private func nearestAlipayAmount(after index: Int, in lines: [String]) -> String? {
       let window = lines.dropFirst(index + 1).prefix(4)
       return window.first(where: { extractSignedAmount(from: $0) != nil })
     }

     private func extractWeChatTransferFieldValue(label: String, lines: [String]) -> String? {
       let candidates = weChatTransferValueBlock(from: lines)
       switch label {
       case "零钱余额":
         return candidates.first(where: { $0.range(of: #"^\d+(?:\.\d{1,2})$"#, options: .regularExpression) != nil })
       case "转账单号":
         return candidates.first(where: { $0.range(of: #"^\d{10,}$"#, options: .regularExpression) != nil })
       case "转账时间":
         return candidates.first(where: { $0.contains("年") && $0.contains(":") })
       case "支付方式":
         return candidates.first(where: { $0.contains("零钱") || $0.contains("银行卡") || $0.contains("信用卡") ||
 $0.contains("微信") })
       case "收款方备注":
         return candidates.first(where: {
           !$0.contains("成功") &&
           !$0.contains("零钱") &&
           !$0.contains("微信") &&
           !$0.contains("银行卡") &&
           !$0.contains("年") &&
           !$0.contains(":") &&
           $0.range(of: #"[\u4e00‑\u9fffA‑Za‑z]"#, options: .regularExpression) != nil
         })
       case "当前状态":
         return candidates.first(where: { $0.contains("成功") || $0.contains("完成") })
       default:
         return candidates.first(where: { !detailFieldLabels.contains($0) && !isNoiseLine($0) })
       }
     }

     private func weChatTransferValueBlock(from lines: [String]) -> [String] {
       let labels = ["当前状态", "收款方备注", "支付方式", "转账时间", "转账单号", "零钱余额"]
       guard let start = lines.firstIndex(of: labels[0]) else { return lines }
       var cursor = start
       while cursor < lines.count, labels.contains(lines[cursor]) {
         cursor += 1
       }
       guard cursor < lines.count else { return [] }
       var values: [String] = []
       while cursor < lines.count {
         let line = lines[cursor]
         if line == "账单服务" || line == "收款方服务" || line == "对订单有疑惑" || line == "申请电子凭证" || line ==
      "发起群收款" {
           break
         }
         if isNoiseLine(line) && !line.contains("成功") { break }
         values.append(line)
         cursor += 1
       }
       return values
     }

     private func extractAlipayDetailPaymentMethod(from lines: [String]) -> String? {
       lines
         .first(where: { $0.contains("花呗") || $0.contains("银行卡") || $0.contains("信用卡") || $0.contains("支付宝余额")
   || $0.contains("储蓄卡") })
         .map(normalizePaymentMethod)
     }

     private func extractAlipayDeductionNote(from lines: [String]) -> String? {
       guard let idx = lines.firstIndex(where: { $0.contains("先用后付") || $0.contains("芝麻分") }) else { return nil }
       var parts: [String] = []
       for line in lines[idx...].prefix(3) {
         if isAlipayDetailTitleStopLine(line) || line.contains("支付奖励") || line.contains("交易详情") { break }
         if line.contains("先用后付") || line.contains("芝麻分") || (!parts.isEmpty && parts.count <= 6) {
           parts.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
         } else if !parts.isEmpty {
           break
        }
    }
    let merged = parts.joined()
    return merged.isEmpty ? nil : merged
}

private func isAlipayDetailTitleStopLine(_ line: String) -> Bool {
    let stopKeywords = [
        "更多", "共", "账单管理", "账单分类", "标签", "自动生成账单统计报告",
        "我的消费图鉴", "其他>", "请选择", "计入收支", "支付奖励"
    ]
    if stopKeywords.contains(where: line.contains) { return true }
    return line == ">" || line == "•"
}

private func cleanAlipayDetailTitleLine(_ line: String) -> String {
    guard !line.contains("立即领取") && !line.contains("积分") else { return "" }
    guard !line.contains("查看关联记录") else { return "" }
    guard !line.contains("支付成功") else { return "" }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func buildAlipayListSections(from lines: [String]) -> [(month: Int, expenseTotal: Double?, items: [(title: String, category: String?, provider: String?, dateLine: String, amountText: String?)], lines: [String])] {
    var sections: [(month: Int, expenseTotal: Double?, items: [(title: String, category: String?, provider: String?, dateLine: String, amountText: String?)], lines: [String])] = []
    var currentMonth: Int?
    var currentExpenseTotal: Double?
    var currentLines: [String] = []

    for (idx, line) in lines.enumerated() {
        if let month = extractSimpleMonthHeader(from: line) {
            if let currentMonth = currentMonth {
                sections.append((month: currentMonth, expenseTotal: currentExpenseTotal, items: [], lines: currentLines))
            }
            currentMonth = month
            currentExpenseTotal = extractMonthExpenseTotal(around: idx, in: lines)
            currentLines = []
        } else if currentMonth != nil {
            currentLines.append(line)
        }
    }

    if let currentMonth = currentMonth {
        sections.append((month: currentMonth, expenseTotal: currentExpenseTotal, items: [], lines: currentLines))
    }

    return sections.map { section in
        (month: section.month, expenseTotal: section.expenseTotal, items: parseAlipayListItems(in: section.lines,
 expenseTotal: section.expenseTotal), lines: section.lines)
    }
}

private func parseAlipayListItems(in lines: [String], expenseTotal: Double?) -> [(title: String, category: String?, provider: String?, dateLine: String, amountText: String?)] {
    let dateIndices = lines.indices.filter { isAlipayDateLine(lines[$0]) }
    var items: [(title: String, category: String?, provider: String?, dateLine: String, amountText: String?)] = []

    for (position, dateIndex) in dateIndices.enumerated() {
        let previousDateIndex = position > 0 ? dateIndices[position - 1] : nil
        let nextDateIndex = position + 1 < dateIndices.count ? dateIndices[position + 1] : nil

        let beforeStart = max((previousDateIndex ?? -1) + 1, dateIndex - 4)
        let beforeLines = Array(lines[beforeStart..<dateIndex])
        let afterEnd = min((nextDateIndex ?? lines.count), dateIndex + 3)
        let afterLines = Array(lines[dateIndex + 1..<afterEnd])

        let category = nearestAlipayCategory(in: beforeLines)
        let provider = nearestAlipayProvider(in: beforeLines)
        let titleLine = nearestAlipayTitle(in: beforeLines)
        let cleanedTitle = titleLine.map { extractInlineAmountAndCleanTitle(from: $0).title }.flatMap { $0.isEmpty ? nil : $0 } ?? "未命名流水"
        let inlineAmount = titleLine.flatMap { extractInlineAmountAndCleanTitle(from: $0).amountText }
        let amountText = inlineAmount
            ?? nearestStandaloneAmount(in: beforeLines.reversed())
            ?? nearestStandaloneAmount(in: afterLines)
            ?? (dateIndices.count == 1 ? expenseTotal.map { String(format: "%-.2f", abs($0)) } : nil)

        items.append((title: cleanedTitle, category: category, provider: provider, dateLine: lines[dateIndex], amountText: amountText))
    }

    return items
}

private func nearestAlipayTitle(in lines: [String]) -> String? {
    lines.reversed().first { candidate in
        let cleaned = extractInlineAmountAndCleanTitle(from: candidate).title
        return isLikelyAlipayTitleLine(cleaned)
    }
}

private func nearestAlipayCategory(in lines: [String]) -> String? {
    lines.reversed().first(where: isLikelyAlipayCategoryLine)
}

private func nearestAlipayProvider(in lines: [String]) -> String? {
    lines.reversed().first(where: isLikelyAlipayProviderLine)
}

private func nearestStandaloneAmount<S: Sequence>(in lines: S) -> String? where S.Element == String {
    lines.first { extractSignedAmount(from: $0) != nil }
}

private func isLikelyAlipayCategoryLine(_ line: String) -> Bool {
    ["其他", "日用百货", "保险"].contains(line)
}

private func isLikelyAlipayProviderLine(_ line: String) -> Bool {
    ["天猫", "淘宝", "淘", "支付宝", "闲鱼"].contains(line)
}

private func isLikelyAlipayTitleLine(_ line: String) -> Bool {
    guard line.range(of: #"[\u4e00-\u9fffA-Za-z]"#, options: .regularExpression) != nil else { return false }
    if isAlipayDateLine(line) || extractSimpleMonthHeader(from: line) != nil { return false }
    if isLikelyAlipayCategoryLine(line) || isLikelyAlipayProviderLine(line) { return false }
    if extractSignedAmount(from: line) != nil { return false }
    if line.contains("收支分析") || line.contains("等待确认收货") { return false }
    return true
}

private func meaningfulAlipayListMerchant(provider: String?, title: String) -> String {
    if let provider, provider.count > 1, provider != "淘", provider != "闲鱼" {
        return provider
    }
    return normalizeListMerchant(title) ?? title
}

private func extractInlineAmountAndCleanTitle(from line: String) -> (title: String, amountText: String?) {
    if let range = line.range(of: #"#[+-]?\d+(?:\.\d{1,2})?#"#, options: .regularExpression) {
        let amountText = String(line[range])
        let title = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, amountText)
    }
    return (line, nil)
}

private func parseAlipayListDate(_ line: String, fallbackYear: Int) -> Date? {
    let regex = try? NSRegularExpression(pattern: #"#(\d{2})-(\d{2})\s+(\d{2}):(\d{2})#"#)
    let ns = line as NSString
    guard let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
          match.numberOfRanges == 5 else {
        return nil
    }
    let month = Int(ns.substring(with: match.range(at: 1))) ?? 1
    let day = Int(ns.substring(with: match.range(at: 2))) ?? 1
    let hour = Int(ns.substring(with: match.range(at: 3))) ?? 0
    let minute = Int(ns.substring(with: match.range(at: 4))) ?? 0
    var comps = DateComponents()
    comps.year = fallbackYear
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    return Calendar.current.date(from: comps)
}

private func isBalanceLine(_ line: String) -> Bool {
    line.contains("余额")
}

private func isNoiseLine(_ line: String) -> Bool {
    if ["×", "账单", "零钱明细", "账单服务", "对订单有疑惑", "申请电子凭证", "在此商户的交易"].contains(line) {
        return true
    }
    if detailFieldLabels.contains(line) { return false }
    if line.range(of: #"^\d{1,3}\.\d{1,3}\%?$"#, options: .regularExpression) != nil { return true }
    if line.range(of: #"^\d{1,2}:\d{2},\d{2}$"#, options: .regularExpression) != nil { return true }
    if line.count <= 1 { return true }
    return false
}

private func extractFallbackMerchant(from lines: [String]) -> String? {
    let blacklist = ["支付宝", "微信支付", "账单详情", "账单详情", "已支付", "付款成功", "收款成功", "交易单号", "订单号", "支付方式", "银行卡", "账单", "零钱明细"]
    return lines.first { line in
        !blacklist.contains(where: line.contains) && line.range(of: #"[\u4e00-\u9fffA-Za-z]"#, options: .regularExpression) != nil && !line.isEmpty && line.count >= 2 && !isNoiseLine(line)
    }
}

private func extractFallbackDetails(from lines: [String]) -> [OCRLineItem] {
    var result: [OCRLineItem] = []
    for line in lines {
        let parts = line.components(separatedBy: CharacterSet(charactersIn: ":"))
        if parts.count >= 2 {
            let label = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty && !value.isEmpty {
                result.append(OCRLineItem(label: label, value: value))
            }
        }
    }
    return Array(result.prefix(8))
}

private func classify(text: String) -> (String?, [String], Double) {
    let lowered = text.lowercased()
    var bestRule: Rule?
    var bestScore = 0

    for rule in rules {
        let score = rule.tokens.reduce(0) { partial, token in
            partial + (lowered.contains(token.lowercased()) ? 1 : 0)
        }
        if score > bestScore {
            bestScore = score
            bestRule = rule
        }
    }
    guard let bestRule else { return (nil, [], 0.25) }
    return (bestRule.keyword, bestRule.path, min(0.55 + Double(bestScore) * 0.12, 0.95))
}

private func normalizeClassifiedResult(kind: FlowType, _ raw: (keyword: String?, path: [String], confidence: Double))
-> (keyword: String?, path: [String], confidence: Double) {
    var keyword = raw.keyword
    var path = raw.path
    var confidence = raw.confidence

    if kind == .expense && path.first == "收入" {
        keyword = nil
        path = []
        confidence = min(confidence, 0.3)
    }
    return (keyword, path, confidence)
}

}
