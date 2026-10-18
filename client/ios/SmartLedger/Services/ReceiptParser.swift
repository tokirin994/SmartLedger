import Foundation

struct ReceiptParser {
    struct Rule {
        let keyword: String
        let tokens: [String]
        let path: [String]
    }

    private let rules: [Rule] = [
        .init(keyword: "奶茶咖啡", tokens: ["瑞幸", "库迪", "星巴克", "咖啡", "奶茶", "喜茶", "茶百道", "霸王茶姬", "蜜雪冰城"], path: ["餐饮", "奶茶咖啡"]),
        .init(keyword: "日常吃饭", tokens: ["餐饮", "餐饮美食", "午饭", "晚饭", "早餐", "早点", "包子", "豆浆", "油条", "早餐店", "外卖", "快餐", "饭店", "美团", "工作餐", "企业订单", "猪脚饭", "烧腊", "米线", "面馆", "快餐店", "小吃", "烧烤", "盖饭", "粉面", "烤肉", "自助餐"], path: ["餐饮", "日常吃饭"]),
        .init(keyword: "吃好的", tokens: ["火锅", "烤肉", "自助", "海鲜", "西餐"], path: ["餐饮", "吃好的"]),
        .init(keyword: "水果零食", tokens: ["水果", "零食", "盒马", "山姆", "超市", "便利店"], path: ["水果零食"]),
        .init(keyword: "买菜做饭", tokens: ["买菜", "菜市场", "朴朴", "叮咚买菜", "生鲜"], path: ["餐饮", "买菜做饭"]),
        .init(keyword: "打车", tokens: ["滴滴", "打车", "专车", "出租车", "代驾"], path: ["交通", "打车"]),
        .init(keyword: "地铁公交", tokens: ["地铁", "公交", "乘车码"], path: ["交通", "地铁公交"]),
        .init(keyword: "火车机票", tokens: ["火车票", "机票", "12306", "航旅", "南航", "东航", "国航"], path: ["交通", "火车机票"]),
        .init(keyword: "房租", tokens: ["房租", "租金"], path: ["居住", "房租"]),
        .init(keyword: "水电网", tokens: ["电费", "水费", "燃气", "宽带", "话费"], path: ["居住", "水电网"]),
        .init(keyword: "日用品", tokens: ["日用品", "纸巾", "洗发水", "沐浴露", "洁柔", "立白", "洗衣液", "卫生纸", "淘宝", "天猫", "乐高"], path: ["购物", "日用品"]),
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

    private let detailFieldLabels = ["当前状态", "支付时间", "商品名称", "商品说明", "商品", "商户全称", "收款方全称", "收款方全名", "收单机构", "支付方式", "付款方式", "支付渠道", "交易单号", "商户单号", "订单号", "优惠", "原价", "订单金额", "收款方", "收款方备注", "交易对方", "商家", "转账时间", "转账单号", "零钱余额", "扣款说明", "订单时间", "订单编号", "消费商家", "业务场景"]

    func parse(rawText: String) -> OCRImportResult {
        let lines = normalizedLines(from: rawText)
        if isMeituanEnterpriseMealOrder(lines) {
            return parseMeituanEnterpriseMealOrder(lines: lines)
        }
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
        if isMeituanEnterpriseMealOrder(lines) {
            return [parseMeituanEnterpriseMealOrder(lines: lines)]
        }
        if isWeChatTransferDetailPage(lines) {
            return [parseWeChatTransferDetail(lines: lines)]
        }
        if isAlipayDetailPage(lines) {
            return [parseAlipayDetail(lines: lines)]
        }
        if isLikelyDetailPage(lines) {
            return [parseDetail(lines: lines)]
        }
        if isEcommerceOrderPage(lines) {
            return parseEcommerceOrders(lines: lines)
        }
        let statementPage = lines.contains(where: { $0.contains("我的账单") || $0.contains("个人消费卡账户") })
        if isAlipayListPage(lines) || statementPage {
            let alipayResults = parseAlipayList(lines: lines)
            let genericResults = parseList(lines: lines)
            // Alipay layouts differ by app version. Compare rows with both an
            // amount and a transaction date; preferring the first non-empty
            // parser result used to silently discard rows found by the other.
            let completeAlipay = alipayResults.filter { $0.amount != nil && $0.happenedAt != nil }
            let completeGeneric = genericResults.filter { $0.amount != nil && $0.happenedAt != nil }
            if completeAlipay.count > completeGeneric.count { return alipayResults }
            if completeGeneric.count > completeAlipay.count { return genericResults }
            if !completeAlipay.isEmpty { return alipayResults }
            return genericResults.count > alipayResults.count ? genericResults : alipayResults
        }
        return parseList(lines: lines)
    }

    private func normalizedLines(from rawText: String) -> [String] {
        // OCR 服务会把同一视觉行的多个文本块用空格连接。将明显的列分隔
        // 拆开后，标题、日期、金额即使来自不同列也能进入同一套通用规则；
        // 普通标题中的单个空格不会被拆分，因此不依赖某个平台的固定模板。
        rawText
            .split(whereSeparator: \.isNewline)
            .flatMap { rawLine -> [String] in
                let normalized = normalizeLine(String(rawLine))
                guard !normalized.isEmpty else { return [] }
                let columns = normalized
                    .split(whereSeparator: { $0 == "\t" })
                    .flatMap { part -> [Substring] in
                        part.split(whereSeparator: { $0 == " " })
                    }
                if columns.count > 1 && normalized.range(of: #"\s{2,}"#, options: .regularExpression) != nil {
                    // 详情页的“商品/商品说明”经常包含空格或被 OCR 拼在同一视觉行。
                    // 保留完整视觉行，避免把商品名拆成多个字段；列表页仍按列拆分。
                    if detailFieldLabels.contains(where: { normalized.contains($0) }) {
                        return [normalized]
                    }
                    return columns.map(String.init)
                }
                return [normalized]
            }
            .filter { !$0.isEmpty }
    }

    private func normalizeLine(_ input: String) -> String {
        input
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "‑", with: "-")
            .replacingOccurrences(of: "‑", with: "-")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "﹣", with: "-")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "¥70‑00", with: "¥70.00")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLikelyDetailPage(_ lines: [String]) -> Bool {
        let score = detailFieldLabels.reduce(0) { partial, field in
            partial + (lines.contains(where: { $0.contains(field) }) ? 1 : 0)
        }
        // 银行/信用卡明细页的字段较少，通常只有“交易明细、交易时间、
        // 交易金额/已入账”。不要因为字段不足而退化成通用列表解析。
        let compactDetail = lines.contains(where: { $0.contains("交易明细") }) &&
            lines.contains(where: { $0.contains("交易时间") || $0.contains("交易金额") || $0.contains("已入账") })
        return score >= 4 || compactDetail
    }

    private func isWeChatTransferDetailPage(_ lines: [String]) -> Bool {
        lines.contains(where: { $0.contains("零钱明细") }) &&
        lines.contains(where: { $0.contains("转账时间") || $0.contains("收款方备注") })
    }

    private func isAlipayDetailPage(_ lines: [String]) -> Bool {
        lines.contains(where: { $0.contains("账单详情") }) &&
        lines.contains(where: { line in
            ["付款方式", "支付方式", "支付时间", "商品说明", "扣款说明", "收款方全称", "收款方全名", "收单机构", "当前状态"]
                .contains(where: { line.contains($0) })
        })
    }

    private func isAlipayListPage(_ lines: [String]) -> Bool {
        let classic = lines.contains(where: { $0.contains("搜索交易记录") }) &&
            lines.contains(where: { $0.contains("收支分析") })
        let statement = lines.contains(where: { $0.contains("我的账单") || $0.contains("个人消费卡账户") }) &&
            lines.contains(where: { $0.contains("可用额度") || $0.contains("预估未出账单") })
        return classic || statement
    }

    private func parseWeChatTransferDetail(lines: [String]) -> OCRImportResult {
        let text = lines.joined(separator: "\n")
        let fieldMap = makeFieldMap(lines: lines)
        let transferHeadline = lines.first(where: { $0.contains("付款") || $0.contains("转给") })

        let amountLine = lines.first(where: { $0.range(of: #"^[-‑]?\d+(?:\.\d{1,2})$"#, options: .regularExpression) != nil })
        let amount = extractCurrency(from: amountLine)
        // 只接受截图正文中的日历日期。状态栏通常只有“21:14”这样的时间，
        // 不能作为流水时间，否则会把手机状态栏误识别成交易时间。
        let happenedAt = extractTransactionDate(
            preferredValues: [
                extractWeChatTransferFieldValue(label: "转账时间", lines: lines),
                fieldMap["转账时间"]
            ],
            lines: lines
        )
        let paymentMethod = normalizePaymentMethod(extractWeChatTransferFieldValue(label: "支付方式", lines: lines) ?? fieldMap["支付方式"] ?? fieldMap["付款方式"] ?? "零钱")
        let merchant = normalizeListMerchant(transferHeadline ?? "") ?? transferHeadline
        // 商品名称优先；转账截图通常没有商品字段，此时自然回退到对方账户名称。
        let title = transferHeadline ?? preferredDetailTitle(fieldMap: fieldMap, lines: lines, merchant: merchant) ?? merchant ?? "转账详情"
        let kind = inferKind(in: text, lines: lines, amountLine: amountLine, fallback: .expense)
        let detailKeys = ["当前状态", "收款方备注", "支付方式", "转账时间", "转账单号", "零钱余额"]
        let details = detailKeys
            .compactMap { (key: String) -> OCRLineItem? in
                let value = extractWeChatTransferFieldValue(label: key, lines: lines) ?? fieldMap[key]
                guard let value, !value.isEmpty else { return nil }
                return OCRLineItem(label: key, value: value)
            }
        let classified = normalizeClassifiedResult(kind: kind, classify(text: [title, merchant, paymentMethod, extractWeChatTransferFieldValue(label: "收款方备注", lines: lines), text].compactMap { $0 }.joined(separator: "\n")), happenedAt: happenedAt)

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

    private func isMeituanEnterpriseMealOrder(_ lines: [String]) -> Bool {
        let text = lines.joined(separator: "\n")
        let hasOrderTime = lines.contains { $0.contains("订单时间") }
        let hasMerchant = lines.contains { $0.contains("消费商家") }
        let hasMealScenario = lines.contains { $0.contains("工作餐") || $0.contains("企业订单") }
        return (text.contains("消费记录详情") || text.contains("企业订单")) &&
            hasOrderTime && hasMerchant && hasMealScenario
    }

    private func parseMeituanEnterpriseMealOrder(lines: [String]) -> OCRImportResult {
        let fieldMap = makeFieldMap(lines: lines)
        let amount = extractDetailAmount(from: lines)
        let happenedAt = extractTransactionDate(
            preferredValues: [fieldMap["订单时间"]],
            lines: lines
        )
        let merchant = fieldMap["消费商家"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = merchant?.isEmpty == false ? merchant : nil
        var classified = normalizeClassifiedResult(
            kind: .expense,
            classify(text: "餐饮 工作餐"),
            happenedAt: happenedAt
        )
        // Enterprise meal orders always map into the meal hierarchy; select the
        // time-specific leaf only when the OCR supplied an actual order time.
        if let happenedAt {
            classified.path = mealTimeAdjustedPath(["餐饮", "日常吃饭"], date: happenedAt)
        }
        return OCRImportResult(
            amount: amount,
            kind: .expense,
            merchant: merchant,
            paymentMethod: "公司补贴",
            title: title,
            happenedAt: happenedAt,
            categoryKeyword: "日常吃饭",
            categoryPath: classified.path,
            details: [
                OCRLineItem(label: "识别场景", value: "美团企业工作餐"),
                OCRLineItem(label: "业务场景", value: fieldMap["业务场景"] ?? "工作餐"),
                OCRLineItem(label: "订单编号", value: fieldMap["订单编号"] ?? "")
            ].filter { !$0.value.isEmpty },
            confidence: amount != nil && title != nil && happenedAt != nil ? 0.97 : 0.72,
            rawLines: Array(lines.prefix(30)),
            originalAmount: nil,
            discountAmount: nil,
            presetKey: "meituan_enterprise_meal"
        )
    }

    private func parseAlipayDetail(lines: [String]) -> OCRImportResult {
        let text = lines.joined(separator: "\n")
        let amountLine = alipayDetailAmountLine(in: lines)
        let amount = amountLine.flatMap { extractCurrency(from: $0) }
        let fieldMap = makeFieldMap(lines: lines)
        let happenedAt = extractTransactionDate(
            preferredValues: [fieldMap["支付时间"], fieldMap["交易时间"]],
            lines: lines
        )
        let paymentMethod = extractAlipayDetailPaymentMethod(from: lines)
        let merchant = extractAlipayDetailMerchant(from: lines, fieldMap: fieldMap)
        // In Alipay's compact bill detail, the main title (e.g. “早阳包子”)
        // appears above the amount, while “商品说明” may only say “收钱码收款”.
        // Prefer that header title over the generic payment-channel description.
        let title = extractAlipayDetailTitle(from: lines, amountLine: amountLine)
            ?? preferredDetailTitle(fieldMap: fieldMap, lines: lines, merchant: merchant)
            ?? merchant
        let kind = inferKind(in: text, lines: lines, amountLine: amountLine, fallback: .expense)
        let originalAmount = extractOriginalAmount(from: lines, fieldMap: fieldMap)
            ?? extractCurrency(from: fieldMap["订单金额"])
            ?? extractLabeledAmount("订单金额", from: lines)
        let explicitDiscount = extractDiscountAmount(from: lines, fieldMap: fieldMap)
        let differenceDiscount: Double? = {
            guard let originalAmount, let amount, originalAmount > amount else { return nil }
            return ((originalAmount - amount) * 100).rounded() / 100
        }()
        let discountAmount = explicitDiscount ?? differenceDiscount
        let details = buildAlipayDetailItems(lines: lines, happenedAt: happenedAt, paymentMethod: paymentMethod)
        let classified = normalizeClassifiedResult(kind: kind, classify(text: [title, merchant, paymentMethod, text].compactMap { $0 }.joined(separator: "\n")), happenedAt: happenedAt)

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
            originalAmount: originalAmount,
            discountAmount: discountAmount
        )
    }

    private func parseAlipayList(lines: [String]) -> [OCRImportResult] {
        let isStatementPage = lines.contains { $0.contains("我的账单") || $0.contains("个人消费卡账户") }
        let filtered = isStatementPage ? lines : lines.filter { !isAlipayListNoiseLine($0) }
        let currentYear = Calendar.current.component(.year, from: Date())
        var results: [OCRImportResult] = []

        for section in buildAlipayListSections(from: filtered) {
            let items = section.items
            for (itemIndex, item) in items.enumerated() {
            let rawAmount = item.amountText.flatMap { extractListAmount(from: $0) } ?? {
                    if items.count == 1, let total = section.expenseTotal { return -abs(total) }
                    return nil
                }()
                let happenedAt = parseAlipayListDate(item.dateLine, fallbackYear: currentYear)

                // Alipay's expense list commonly labels a payment as
                // “收钱码收款-给某商户” while showing a negative amount. The
                // word “收款” alone describes the payment channel, not direction.
                let explicitIncome = item.title.contains("转入") || item.title.contains("退款") || item.title.contains("收入") || item.category == "收入" || item.category?.contains("退款") == true
                // 部分信用卡/账单列表把支出金额显示成无符号的 ¥22.00；
                // 无明确收入语义时按支出处理，避免整页被误判成收入。
                let kind: FlowType = explicitIncome ? .income : .expense
                let merchant = meaningfulAlipayListMerchant(provider: item.provider, title: item.title)
                let paymentMethod: String? = "支付宝"
                let classified = normalizeClassifiedResult(kind: kind, classify(text: [item.title, merchant, item.category, item.provider].compactMap { $0 }.joined(separator: "\n")), happenedAt: happenedAt)

                results.append(
                    OCRImportResult(
                        amount: rawAmount.map(abs),
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
                        confidence: rawAmount == nil ? 0.58 : (itemIndex == 0 && items.count == 1 ? 0.9 : 0.87),
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
        let happenedAt = extractTransactionDate(
            preferredValues: [fieldMap["支付时间"], fieldMap["转账时间"], fieldMap["交易时间"]],
            lines: lines
        )
        let merchant = preferredDetailMerchant(fieldMap: fieldMap, lines: lines)
        let title = preferredDetailTitle(fieldMap: fieldMap, lines: lines, merchant: merchant)
        let paymentMethod = extractPaymentMethod(fieldMap: fieldMap, lines: lines)
        let kind = detectKind(in: text, lines: lines)
        let details = detailItems(from: fieldMap)
        let classified = normalizeClassifiedResult(
            kind: kind,
            classify(text: [title, merchant, paymentMethod, fieldMap["商品"], fieldMap["商品说明"], text].compactMap { $0 }.joined(separator: "\n")),
            happenedAt: happenedAt
        )
        let categoryKeyword = classified.keyword
        let categoryPath = classified.path
        let categoryConfidence = classified.confidence
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

private func isEcommerceOrderPage(_ lines: [String]) -> Bool {
    lines.contains(where: { $0.contains("我的订单") || $0.contains("全部订单") }) &&
    (lines.contains(where: { $0.contains("实付款") || $0.contains("实付") }) ||
     lines.contains(where: { $0.range(of: #"下单[：:]?\s*\d{4}[-年]\d{1,2}[-月]\d{1,2}"#, options: .regularExpression) != nil }))
}

private func parseEcommerceOrders(lines: [String]) -> [OCRImportResult] {
    let year = Calendar.current.component(.year, from: Date())
    var results: [OCRImportResult] = []

    for (index, line) in lines.enumerated() {
        guard let detectedAmount = extractEcommercePaidAmount(from: line) else { continue }
        let previousLines = Array(lines[max(0, index - 9)..<index])
        guard let title = previousLines.reversed().max(by: { ecommerceTitleScore($0) < ecommerceTitleScore($1) }),
              ecommerceTitleScore(title) > 0 else { continue }
        // 订单页右侧金额偶尔被图片边缘裁掉（例如 ¥58.9 被识别成 ¥5）。
        // 对明显过小的实付金额，优先使用同一订单区域内更完整的商品金额。
        let nearbyPrice = previousLines.reversed().compactMap(extractCurrencyAnywhere).first
        let amount = detectedAmount < 10 && (nearbyPrice ?? 0) > detectedAmount ? nearbyPrice! : detectedAmount
        let dateLine = previousLines.reversed().first(where: { $0.range(of: #"\d{2}[.-]\d{2}"#, options: .regularExpression) != nil })
        let happenedAt = dateLine.flatMap { parseEcommerceDate($0, year: year) }
        let classified = normalizeClassifiedResult(kind: .expense, classify(text: title), happenedAt: happenedAt)
        results.append(OCRImportResult(
            amount: amount,
            kind: .expense,
            merchant: "电商订单",
            paymentMethod: nil,
            title: title,
            happenedAt: happenedAt,
            categoryKeyword: classified.keyword,
            categoryPath: classified.path,
            details: [
                OCRLineItem(label: "识别来源", value: "订单页批量识别"),
                OCRLineItem(label: "实付金额", value: String(format: "%.2f", amount))
            ],
            confidence: 0.86,
            rawLines: Array(previousLines.suffix(3)) + [line],
            originalAmount: nil,
            discountAmount: nil
        ))
    }
    if !results.isEmpty { return results }

    // 订单列表有时只显示“下单时间”和右侧实付金额，不出现“实付”标签。
    // 按订单时间切分卡片，再从同一局部区域选择金额和商品名，适配不同平台布局。
    let dateIndices = lines.indices.filter { lines[$0].range(of: #"下单[：:]?\s*\d{4}[-年]\d{1,2}[-月]\d{1,2}"#, options: .regularExpression) != nil }
    for dateIndex in dateIndices {
        let start = max(0, dateIndex - 6)
        let end = min(lines.count, dateIndex + 4)
        let window = Array(lines[start..<end])
        guard let title = window.reversed().first(where: { ecommerceTitleScore($0) > 0 }) else { continue }
        let amount = window.compactMap(extractCurrencyAnywhere).first
        let dateLine = lines[dateIndex]
        let happenedAt = parseEcommerceDateWithTime(dateLine, year: year)
        let classified = normalizeClassifiedResult(kind: .expense, classify(text: title), happenedAt: happenedAt)
        results.append(OCRImportResult(
            amount: amount,
            kind: .expense,
            merchant: "电商订单",
            paymentMethod: nil,
            title: title,
            happenedAt: happenedAt,
            categoryKeyword: classified.keyword,
            categoryPath: classified.path,
            details: [OCRLineItem(label: "识别来源", value: "订单列表")],
            confidence: amount == nil ? 0.52 : 0.78,
            rawLines: window,
            originalAmount: nil,
            discountAmount: nil
        ))
    }
    return results
}

private func parseEcommerceDateWithTime(_ line: String, year: Int) -> Date? {
    let pattern = #"下单[：:]?\s*(\d{4})[-年](\d{1,2})[-月](\d{1,2})[日\s]+(\d{1,2}):(\d{2})"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
    let ns = line as NSString
    var comps = DateComponents()
    comps.year = Int(ns.substring(with: match.range(at: 1))) ?? year
    comps.month = Int(ns.substring(with: match.range(at: 2))) ?? 1
    comps.day = Int(ns.substring(with: match.range(at: 3))) ?? 1
    comps.hour = Int(ns.substring(with: match.range(at: 4))) ?? 0
    comps.minute = Int(ns.substring(with: match.range(at: 5))) ?? 0
    return Calendar.current.date(from: comps)
}

private func extractEcommercePaidAmount(from line: String) -> Double? {
    let pattern = #"(?:实付款|实付)\s*[:：]?\s*[¥￥]?\s*(\d+(?:\.\d{1,2})?)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
          match.numberOfRanges > 1 else { return nil }
    return Double((line as NSString).substring(with: match.range(at: 1)))
}

private func ecommerceTitleScore(_ line: String) -> Int {
    guard line.range(of: #"[\u4e00-\u9fffA-Za-z]"#, options: .regularExpression) != nil,
          !line.contains("交易成功"), !line.contains("待评价"), !line.contains("更多"),
           !line.contains("申请"), !line.contains("实付款"), !line.contains("实付"),
           !line.contains("旗舰店"), !line.contains("官方店"), !line.contains("下单"),
           !line.contains("全部订单"), !line.contains("我的订单") else { return 0 }
    let stripped = cleanListTitle(line)
    guard stripped.count >= 5 else { return 0 }
    return min(stripped.count, 100)
}

private func parseEcommerceDate(_ line: String, year: Int) -> Date? {
    guard let regex = try? NSRegularExpression(pattern: #"(\d{2})[.-](\d{2})"#),
          let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
          match.numberOfRanges == 3 else { return nil }
    var components = DateComponents()
    components.year = year
    components.month = Int((line as NSString).substring(with: match.range(at: 1)))
    components.day = Int((line as NSString).substring(with: match.range(at: 2)))
    return Calendar.current.date(from: components)
}

private func parseList(lines: [String]) -> [OCRImportResult] {
    var results: [OCRImportResult] = []
    var currentMonth = Calendar.current.component(.month, from: Date())
    let currentYear = Calendar.current.component(.year, from: Date())
    let cleaned = lines.filter { !isNoiseLine($0) }
    let pagePaymentMethod = inferListPaymentMethod(fromPageLines: lines)

    var records: [(title: String, dateLine: String, month: Int, inlineAmount: Double?, incomeHint: Bool)] = []
    for index in cleaned.indices {
        let line = cleaned[index]
        if let month = extractMonthHeader(from: line) {
            currentMonth = month
            // A visual OCR row can contain the month header and the first
            // transaction together. Do not discard it if it includes an amount.
             if extractListAmountAnywhere(in: line) == nil { continue }
        }
        if let month = extractSimpleMonthHeader(from: line), !isListDateLine(line) {
            currentMonth = month
            continue
        }
        guard isListDateLine(line) else { continue }
        // Vision may put a title, amount and date in separate visual rows. Pick
        // the nearest human-readable row, then search the surrounding record for
        // its signed amount instead of requiring title and amount to share a row.
         let candidateStart = max(0, index - 4)
         let nearbyBefore = Array(cleaned[candidateStart..<index])
         let nearbyAfter = Array(cleaned[index..<min(cleaned.count, index + 5)])
         // 不同账单把日期放在标题之前或之后：两种顺序都支持，
         // 仍然只使用邻近文本块，不依赖固定屏幕坐标。
         let titleBefore = nearbyBefore.reversed().first(where: isTransactionTitleLine)
         let titleAfter = nearbyAfter.dropFirst().first(where: isTransactionTitleLine)
         let dateHasTime = line.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil
         guard let titleLine = (dateHasTime ? (titleBefore ?? titleAfter) : (titleAfter ?? titleBefore)) else { continue }
         let inlineAmount = ([titleLine] + Array(nearbyBefore.reversed()) + nearbyAfter)
            .compactMap(extractListAmountAnywhere(in:))
            .first
         let context = ([titleLine] + nearbyBefore.suffix(2) + nearbyAfter.prefix(3)).joined(separator: "\n")
         let compactContext = context.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
         let outgoingTransfer = ["转出", "转给", "转账支出", "转账付款"].contains(where: { compactContext.contains($0) })
         let incomeHint = !outgoingTransfer && (
             context.contains("退款") || context.contains("转入") || context.contains("收入") ||
             (context.contains("收款") && !titleLine.contains("收钱码") && (inlineAmount ?? -1) >= 0)
         )
         records.append((title: cleanListTitle(titleLine), dateLine: line, month: currentMonth, inlineAmount: inlineAmount, incomeHint: incomeHint))
    }

    let amountLines = cleaned.filter { line in
        extractListAmount(from: line) != nil && !isBalanceLine(line)
    }

    guard !records.isEmpty else {
        return parseLooseList(lines: lines, paymentMethod: pagePaymentMethod, fallbackYear: currentYear)
    }

    for idx in records.indices {
        let amount = records[idx].inlineAmount ?? (idx < amountLines.count ? extractListAmount(from: amountLines[idx]) : nil)
        guard let happenedAt = parseListDate(records[idx].dateLine, fallbackYear: currentYear, monthOverride: records[idx].month) else {
            continue
        }

        // 列表页常将支出显示为无符号 ¥22.00；没有明确收入语义时按支出，
        // 只有“退款/转入/收入”等上下文才判定为收入。
        let kind: FlowType = records[idx].incomeHint ? .income : .expense
        let displayAmount = amount.map(abs)
        let title = records[idx].title
        let merchant = normalizeListMerchant(title)
        let paymentMethod = inferListPaymentMethod(from: title, fallback: pagePaymentMethod)
        let classified = normalizeClassifiedResult(kind: kind, classify(text: [title, merchant, paymentMethod].compactMap { $0 }.joined(separator: "\n")), happenedAt: happenedAt)
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
                    OCRLineItem(label: "金额", value: displayAmount.map { String(format: "%.2f", $0) } ?? "待填写")
                ],
                confidence: amount == nil ? 0.52 : min(0.58 + categoryConfidence, 0.95),
                rawLines: [title, records[idx].dateLine, amount.map { String(format: "%.2f", $0) } ?? ""],
                originalAmount: nil,
                discountAmount: nil
            )
        )
    }

    return results
}

/// 最后一道与平台无关的兜底：当 OCR 将日期拆成多个文本块时，仍按“金额附近的
/// 标题 + 日期”建立流水。它只在常规列表规则完全没有命中时运行，避免把汇总金额
/// 当成流水，同时不依赖任何固定坐标或平台模板。
private func parseLooseList(lines: [String], paymentMethod: String?, fallbackYear: Int) -> [OCRImportResult] {
    var results: [OCRImportResult] = []
    var seen = Set<String>()
    for index in lines.indices {
        guard let amount = extractListAmountAnywhere(in: lines[index]), amount != 0,
              !isBalanceLine(lines[index]) else { continue }
        let windowStart = max(0, index - 5)
        let windowEnd = min(lines.count, index + 4)
        let window = Array(lines[windowStart..<windowEnd])
        guard let titleLine = window.first(where: { candidate in
            isTransactionTitleLine(candidate) &&
            !isListDateLine(candidate) &&
            !candidate.contains("总") &&
            !candidate.contains("预算") &&
            !candidate.contains("分类")
        }) else { continue }
        let title = cleanListTitle(titleLine)
        guard title.count >= 2 else { continue }
        let dateLine = window.first(where: isListDateLine)
        let happenedAt = dateLine.flatMap {
            parseListDate($0, fallbackYear: fallbackYear,
                          monthOverride: Calendar.current.component(.month, from: Date()))
        }
        let dateKey = dateLine ?? ""
        let key = "\(title)|\(abs(amount))|\(dateKey)"
        guard seen.insert(key).inserted else { continue }
        let context = window.joined(separator: "\n")
        let compactContext = context.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let outgoingTransfer = ["转出", "转给", "转账支出", "转账付款"].contains(where: { compactContext.contains($0) })
        let kind: FlowType = !outgoingTransfer && (context.contains("退款") || context.contains("转入") || context.contains("收入"))
            ? .income
            : .expense
        let merchant = normalizeListMerchant(title)
        let classified = normalizeClassifiedResult(kind: kind, classify(text: [title, merchant].compactMap { $0 }.joined(separator: "\n")), happenedAt: happenedAt)
        results.append(OCRImportResult(
            amount: abs(amount),
            kind: kind,
            merchant: merchant,
            paymentMethod: inferListPaymentMethod(from: title, fallback: paymentMethod),
            title: title,
            happenedAt: happenedAt,
            categoryKeyword: classified.keyword,
            categoryPath: classified.path,
            details: [OCRLineItem(label: "识别来源", value: "通用列表兜底")],
            confidence: happenedAt == nil ? 0.48 : 0.68,
            rawLines: window,
            originalAmount: nil,
            discountAmount: nil
        ))
    }
    return results
}

private func parseFallback(lines: [String]) -> OCRImportResult {
    let text = lines.joined(separator: "\n")
    let kind = detectKind(in: text, lines: lines)
    let amount = extractFallbackAmount(from: lines)
    let merchant = extractFallbackMerchant(from: lines)
    let paymentMethod = extractPaymentMethod(fieldMap: makeFieldMap(lines: lines), lines: lines)
    let details = extractFallbackDetails(from: lines)
    let happenedAt = extractTransactionDate(preferredValues: [], lines: lines)
    let classified = normalizeClassifiedResult(kind: kind, classify(text: [text, merchant, paymentMethod].compactMap { $0 }.joined(separator: "\n")), happenedAt: happenedAt)
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
    // 更具体的字段必须先匹配，例如“商品名称”不能先被短字段“商品”截断。
    let labelsBySpecificity = detailFieldLabels.sorted { $0.count > $1.count }
    // 识别服务会将同一视觉行的左右两列合并，例如“支付方式    零钱”。
    // 先取同一行标签后的内容，再兼容旧版逐行标签/值结构。
    for line in lines {
        for label in labelsBySpecificity where map[label] == nil {
            guard let range = line.range(of: label) else { continue }
            let inline = line[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":："))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !inline.isEmpty { map[label] = inline }
        }
    }
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
          for label in labelsBySpecificity where line == label || line.contains(label + ": ") || line.contains(label +
  ":") {
           if map[label]?.isEmpty == false { continue }
           if let inline = valueAfterColon(in: line), !inline.isEmpty {
             map[label] = inline
           } else if index + 1 < lines.count, !detailFieldLabels.contains(lines[index + 1]) {
             map[label] = lines[index + 1]
           }
          }
        }
        // 优惠说明经常会被 OCR 拆成多行（例如银行卡立减 + 摇优惠）。
        // 字段映射不能只保留第一行，否则既丢失说明，也无法累计优惠金额。
        let discountLines = collectDiscountLines(from: lines)
        if !discountLines.isEmpty {
          map["优惠"] = discountLines.joined(separator: "\n")
        }
        return map
      }

      private func collectDiscountLines(from lines: [String]) -> [String] {
        var values: [String] = []
        for (index, line) in lines.enumerated() {
          let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
          guard isDiscountLabelLine(trimmed) else {
            continue
          }

          let inline = trimmed
            .dropFirst("优惠".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":："))
            .trimmingCharacters(in: .whitespacesAndNewlines)
          if !inline.isEmpty { values.append(String(inline)) }

          var next = index + 1
          while next < lines.count {
            let candidate = lines[next].trimmingCharacters(in: .whitespacesAndNewlines)
            if isDetailFieldLine(candidate) {
              break
            }
            if !candidate.isEmpty && !isNoiseLine(candidate) {
              values.append(candidate)
            }
            next += 1
          }
        }

        var unique: [String] = []
        for value in values where !unique.contains(value) {
          unique.append(value)
        }
        return unique
      }

      private func isDetailFieldLine(_ line: String) -> Bool {
        detailFieldLabels.contains { label in
          line == label || line.hasPrefix(label + ":") || line.hasPrefix(label + "：") || line.hasPrefix(label + " ")
        }
      }

      private func isDiscountLabelLine(_ line: String) -> Bool {
        ["优惠", "支付遇财神", "遇财神", "支付优惠", "银行卡优惠", "红包优惠", "立减"]
          .contains(where: line.hasPrefix)
      }
      private func valueAfterColon(in line: String) -> String? {
       let parts = line.components(separatedBy: CharacterSet(charactersIn: ":: "))
       guard parts.count >= 2 else { return nil }
       return parts.dropFirst().joined(separator: ": ").trimmingCharacters(in: .whitespacesAndNewlines)
     }

      private func extractDetailAmount(from lines: [String]) -> Double? {
        let candidates: [(value: Double, index: Int, score: Int)] = lines.enumerated().flatMap { index, line in
          guard !line.contains("原价"), !line.contains("优惠"), !line.contains("余额"), !shouldIgnoreNumericLine(line) else {
            return [] as [(value: Double, index: Int, score: Int)]
          }
          return amountTokens(in: line).compactMap { token -> (Double, Int, Int)? in
            guard let value = parseAmountToken(token) else { return nil }
            var score = 100 - index
            if token.contains("-") { score += 45 }
            if token.contains("¥") || token.contains("￥") { score += 25 }
            if line.contains("支付") || line.contains("收款") || line.contains("实付") || line.contains("合计") || line.contains("总计") || line.contains("实际") { score += 30 }
            return (abs(value), index, score)
          }
        }
        return candidates.sorted { lhs, rhs in
          lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score > rhs.score
        }.first?.value ?? extractFallbackAmount(from: lines)
      }

     private func extractOriginalAmount(from lines: [String], fieldMap: [String: String]) -> Double? {
       if let value = extractCurrency(from: fieldMap["原价"]) { return value }
       for (idx, line) in lines.enumerated() where line == "原价" {
         if idx + 1 < lines.count, let value = extractCurrency(from: lines[idx + 1]) { return value }
       }
       return nil
     }

      private func extractDiscountAmount(from lines: [String], fieldMap: [String: String]) -> Double? {
        let fieldValues = currencyValues(in: fieldMap["优惠"])
        if !fieldValues.isEmpty {
          let total = fieldValues.reduce(0, +)
          if total < 10_000 { return total }
        }
        let lineValues = lines
          .filter { isDiscountLine($0) && !$0.contains("原价") && !$0.contains("订单金额") }
          .flatMap { currencyValues(in: $0) }
        if !lineValues.isEmpty { return lineValues.reduce(0, +) }
        for (idx, line) in lines.enumerated() where line == "优惠" {
          if idx + 1 < lines.count, let value = extractCurrency(from: lines[idx + 1]) { return value }
        }
        let benefitValues = lines.indices.compactMap { index -> Double? in
          guard isDiscountLine(lines[index]) else { return nil }
          if let inline = extractCurrency(from: lines[index]) { return inline }
          var next = index + 1
          while next < lines.count, !isDetailFieldLine(lines[next]) {
            if let value = extractCurrency(from: lines[next]) { return value }
            next += 1
          }
          return nil
        }
        if !benefitValues.isEmpty { return benefitValues.reduce(0, +) }
       if let line = lines.first(where: { isDiscountLine($0) }) {
         return extractCurrency(from: line)
       }
       return nil
     }

      private func extractLabeledAmount(_ label: String, from lines: [String]) -> Double? {
        for (index, line) in lines.enumerated() where line == label || line.hasPrefix(label + " ") || line.hasPrefix(label + "：") {
          if let inline = extractCurrency(from: line.replacingOccurrences(of: label, with: "")) { return inline }
          if index + 1 < lines.count, let next = extractCurrency(from: lines[index + 1]) { return next }
        }
        return nil
      }

      private func isDiscountLine(_ line: String) -> Bool {
        let normalized = line.replacingOccurrences(of: " ", with: "")
        return ["优惠", "立减", "遇财神", "红包优惠", "支付优惠", "银行卡优惠"]
          .contains(where: normalized.contains)
      }

      private func extractFallbackAmount(from lines: [String]) -> Double? {
        var candidates: [(Double, Int)] = []
        for (idx, line) in lines.enumerated() {
          if shouldIgnoreNumericLine(line) { continue }
          for token in amountTokens(in: line) {
            if let value = parseAmountToken(token) {
              let weight = amountWeight(for: line, index: idx)
              candidates.append((abs(value), weight))
            }
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
        if line.range(of: #"^\d{2}-\d{2}(?:\s+\d{1,2}:\d{2})?$"#, options: .regularExpression) != nil { return true }
        if line.range(of: #"^\d{4}[./-]\d{1,2}[./-]\d{1,2}(?:\s+\d{1,2}:\d{2})?$"#, options: .regularExpression) != nil { return true }
       if line.range(of: #"^\d{4}年\d{1,2}月(?:\s*\d{1,2})?(?:\.\d{2})?$"#, options:
 .regularExpression) != nil { return true }
       if line.range(of: #"^\d{1,2}月\d{1,2}日\s+\d{1,2}:\d{2}$"#, options: .regularExpression) != nil { return true }
       return false
     }

      private func extractCurrency(from text: String?) -> Double? {
        guard let text else { return nil }
        return amountTokens(in: text).compactMap(parseAmountToken).first.map(abs)
      }

      private func extractCurrencyAnywhere(_ text: String) -> Double? {
        amountTokens(in: text).compactMap(parseAmountToken).first.map(abs)
      }

      private func extractSignedAmount(from text: String) -> Double? {
        amountTokens(in: text).compactMap(parseAmountToken).first(where: { $0 < 0 || text.contains("+") })
      }

      private func extractSignedAmountAnywhere(in text: String) -> Double? {
        amountTokens(in: text).compactMap(parseAmountToken).first(where: { $0 < 0 || text.contains("+") })
      }

      private func extractListAmount(from text: String) -> Double? {
        if let signed = extractSignedAmountAnywhere(in: text) { return signed }
        if text.contains("¥") || text.contains("￥") {
          return extractCurrency(from: text)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^[+-]?\d+(?:\.\d{1,2})$"#, options: .regularExpression) != nil else { return nil }
        return Double(trimmed)
      }

      private func extractListAmountAnywhere(in text: String) -> Double? {
        if let signed = extractSignedAmountAnywhere(in: text) { return signed }
        if let amount = extractListAmount(from: text) { return amount }
        // Some bank/WeChat lists render an unsigned amount with a middle dot
        // instead of a currency symbol (for example “·22.00”). It is safe to
        // accept that token here because the caller already found a transaction
        // title/date neighbourhood; plain dates and IDs do not contain this
        // amount marker.
        if text.range(of: #"[·•∙﹒]\s*\d+(?:[\.:]\d{1,2})"#, options: .regularExpression) != nil {
          return extractCurrency(from: text)
        }
        return nil
      }

      private func currencyValues(in text: String?) -> [Double] {
        guard let text else { return [] }
        return amountTokens(in: text).compactMap(parseAmountToken).map(abs)
      }

      /// 提取行内所有可能的金额。没有货币符号时要求带小数点，避免把日期、
      /// 卡号和订单号当成金额；带 ¥/￥ 的整数金额仍然可以识别。
      private func amountTokens(in text: String) -> [String] {
        let normalized = normalizedAmountText(text)
        let pattern = #"[¥￥]?\s*[-+]?\s*(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?|[-+]?\s*[¥￥]\s*(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return regex.matches(in: normalized, range: range).map { match in
          (normalized as NSString).substring(with: match.range)
        }.filter { token in
          let compact = token.replacingOccurrences(of: " ", with: "")
          return compact.contains("¥") || compact.contains("￥") || compact.contains(".")
        }
      }

      private func parseAmountToken(_ token: String) -> Double? {
        let compact = token
          .replacingOccurrences(of: "¥", with: "")
          .replacingOccurrences(of: "￥", with: "")
          .replacingOccurrences(of: ",", with: "")
          .replacingOccurrences(of: " ", with: "")
        guard let value = Double(compact), value.isFinite else { return nil }
        return value
      }

     private func normalizedAmountText(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: ",", with: "")
         .replacingOccurrences(of: "−", with: "-")
         .replacingOccurrences(of: "‑", with: "-")
          .replacingOccurrences(of: "–", with: "-")
          .replacingOccurrences(of: "—", with: "-")
          .replacingOccurrences(of: "﹣", with: "-")
          .replacingOccurrences(of: "－", with: "-")
          .replacingOccurrences(of: "．", with: ".")
          .replacingOccurrences(of: "０", with: "0")
          .replacingOccurrences(of: "１", with: "1")
          .replacingOccurrences(of: "２", with: "2")
          .replacingOccurrences(of: "３", with: "3")
          .replacingOccurrences(of: "４", with: "4")
          .replacingOccurrences(of: "５", with: "5")
          .replacingOccurrences(of: "６", with: "6")
          .replacingOccurrences(of: "７", with: "7")
          .replacingOccurrences(of: "８", with: "8")
          .replacingOccurrences(of: "９", with: "9")
        normalized = normalized.replacingOccurrences(of: "：", with: ":")
        // Payment screenshots often render the decimal separator as a colon
        // (¥21:00) or a middle dot (·22.00 / -·6.00). Only normalize when the
        // punctuation is adjacent to digits, so labels such as “时间：” remain
        // unaffected.
        normalized = normalized.replacingOccurrences(
          of: #"(?<=\d):(?=\d{1,2}(?:\D|$))"#,
          with: ".",
          options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
          of: #"(?<!\d)[·•∙﹒](?=\d)"#,
          with: "",
          options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
          of: #"(?<=\d)[·•∙﹒](?=\d)"#,
          with: ".",
          options: .regularExpression
        )
        return normalized
      }

     private func cleanListTitle(_ text: String) -> String {
       text
          .replacingOccurrences(of: "·", with: " ")
          .replacingOccurrences(of: "•", with: " ")
          .replacingOccurrences(of: "∙", with: " ")
          .replacingOccurrences(of: #"\s*[¥￥]?[-+‑−]\s*\d+(?:\.\d{1,2})?\s*"#, with: " ", options: .regularExpression)
          .replacingOccurrences(of: #"\s*[¥￥]?\d+\.\d{1,2}\s*"#, with: " ", options: .regularExpression)
          .replacingOccurrences(of: #"零钱余额\s*\d+(?:\.\d{1,2})?"#, with: "", options: .regularExpression)
          .replacingOccurrences(of: #"^\d{4}年\d{1,2}月\s*"#, with: "", options: .regularExpression)
          .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
          .trimmingCharacters(in: .whitespacesAndNewlines)
     }

     private func detectKind(in text: String, lines: [String]) -> FlowType {
       // Signed transaction amounts are the strongest direction signal. Do not
       // let labels such as “收款方备注 / 二维码收款” turn an outgoing payment
       // into income; those fields describe the recipient, not the account flow.
       let nonTransactionAmountLabels = ["原价", "优惠", "余额", "订单编号", "订单号", "转账单号", "交易单号", "商户单号"]
       let hasNegativeTransactionAmount = lines.contains { line in
         guard !nonTransactionAmountLabels.contains(where: { line.contains($0) }) else { return false }
         let compact = line.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
         return compact.range(
           of: #"^(?:[¥￥])?[-−‑﹣－](?:[¥￥])?\d[\d,]*(?:[.:．]\d{1,2})?$"#,
           options: .regularExpression
         ) != nil
       }
       if hasNegativeTransactionAmount { return .expense }

       // Outgoing transfer/payment labels take precedence over incidental
       // “收款方/收款服务” text on WeChat bill screens. Those describe the
       // counterparty, not money received by the current user.
       let outgoingSignals = ["扫二维码付款", "扫码付款", "二维码付款", "扫二维码支付", "扫码支付", "付款成功", "转出", "转给", "转账支出", "转账付款", "支出", "扣款", "消费"]
       if outgoingSignals.contains(where: { text.contains($0) }) { return .expense }
       let incomingSignals = ["退款", "转入", "收入", "到账", "收款成功", "已收款", "入账"]
       if incomingSignals.contains(where: { text.contains($0) }) { return .income }
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
         !["账单", "零钱明细", "账单服务", "支付成功", "交易明细", "账单详情", "已入账"].contains(line)
       })
     }

      private func preferredDetailTitle(fieldMap: [String: String], lines: [String], merchant: String?) -> String? {
       // 标题统一遵循“商品名称优先、对方账户兜底”，避免把支付状态或页面标题误当流水标题。
       for key in ["商品名称", "商品", "商品说明", "商品详情", "商品信息"] {
         let continuation = detailValueLines(for: key, lines: lines)
         let rawProduct = continuation.isEmpty ? fieldMap[key] : continuation.joined(separator: " ")
          guard let product = rawProduct?
                  .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                  .trimmingCharacters(in: .whitespacesAndNewlines),
               !product.isEmpty,
               !detailFieldLabels.contains(product),
               !product.contains("商户全称"),
               !isNoiseLine(product) else { continue }
          return cleanDetailTitle(product)
        }
        return merchant.map(cleanDetailTitle)
      }

      private func cleanDetailTitle(_ raw: String) -> String {
        var title = raw
          .replacingOccurrences(of: #"\s*[-－—]\s*(?:美团\s*(?:App)?|美团外卖|Meituan)\s*[-－—].*$"#, with: "", options: .regularExpression)
          .replacingOccurrences(of: #"\s*[-－—]\s*\d{16,}\s*$"#, with: "", options: .regularExpression)
          .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "-－— "))
        return title.isEmpty ? raw : title
      }

     /// 详情页的商品名称可能被 OCR 拆成多行。合并字段后的连续文本，
     /// 保留商品名内部的单个空格，并在遇到下一个字段时停止。
     private func detailValueLines(for key: String, lines: [String]) -> [String] {
       guard let index = lines.firstIndex(where: { line in
         line == key || line.hasPrefix(key + ":") || line.hasPrefix(key + "：") || line.hasPrefix(key + " ")
       }) else { return [] }

       var values: [String] = []
       let labelLine = lines[index]
       if let range = labelLine.range(of: key) {
         let inline = labelLine[range.upperBound...]
           .trimmingCharacters(in: .whitespacesAndNewlines)
           .trimmingCharacters(in: CharacterSet(charactersIn: ":："))
           .trimmingCharacters(in: .whitespacesAndNewlines)
         if !inline.isEmpty { values.append(String(inline)) }
       }

       var next = index + 1
       while next < lines.count {
         let candidate = lines[next]
         let isNextField = detailFieldLabels.contains { label in
           candidate == label || candidate.hasPrefix(label + ":") || candidate.hasPrefix(label + "：") || candidate.hasPrefix(label + " ")
         }
         if isNextField { break }
         guard isTitleContinuation(candidate) else { break }
         values.append(candidate)
         next += 1
       }
       return values
     }

     private func isTitleContinuation(_ line: String) -> Bool {
       let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
       guard value.count > 1,
             !detailFieldLabels.contains(value),
             !isNoiseLine(value),
             !containsCalendarDate(value),
             amountTokens(in: value).isEmpty else { return false }
       return !value.contains("支付成功") && !value.contains("已入账") && !value.contains("账单服务")
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
       line.range(of: #"^(?:今天|昨天|前天)\s*\d{1,2}:\d{2}$|(?:\d{1,2}月\d{1,2}日(?:\s+\d{1,2}:\d{2})?|\d{2}-\d{2}(?:\s*\d{1,2}:\d{2})?)$"#, options: .regularExpression) != nil
       || line.range(of: #"^[A-Za-z]{3}\s+\d{1,2},\s+\d{4}(?:\s+at\s+\d{1,2}:\d{2})?$"#, options: .regularExpression) != nil
     }

     private func extractDate(from text: String?) -> Date? {
       guard let text else { return nil }
       // OCR 常把日期和时间拆成相邻的两个文本块；先跨空白合并解析。
       // 也可能把时间冒号识别成句点，且字段值嵌在整段 OCR 文本中。
       if let regex = try? NSRegularExpression(
         pattern: #"(\d{4})[-/.年](\d{1,2})[-/.月](\d{1,2})(?:日)?\s+(\d{1,2})[\.:](\d{2})(?:[\.:](\d{2}))?"#
       ),
       let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
         let ns = text as NSString
         var comps = DateComponents()
         comps.year = Int(ns.substring(with: match.range(at: 1)))
         comps.month = Int(ns.substring(with: match.range(at: 2)))
         comps.day = Int(ns.substring(with: match.range(at: 3)))
         comps.hour = Int(ns.substring(with: match.range(at: 4)))
         comps.minute = Int(ns.substring(with: match.range(at: 5)))
         comps.second = match.range(at: 6).location == NSNotFound ? 0 : Int(ns.substring(with: match.range(at: 6)))
         if let date = Calendar.current.date(from: comps) { return date }
       }
       if let regex = try? NSRegularExpression(
         pattern: #"(\d{4})年(\d{1,2})月(\d{1,2})日\s+(\d{1,2}):(\d{2})(?::(\d{2}))?"#
       ),
       let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
         let ns = text as NSString
         var comps = DateComponents()
         comps.year = Int(ns.substring(with: match.range(at: 1)))
         comps.month = Int(ns.substring(with: match.range(at: 2)))
         comps.day = Int(ns.substring(with: match.range(at: 3)))
         comps.hour = Int(ns.substring(with: match.range(at: 4)))
         comps.minute = Int(ns.substring(with: match.range(at: 5)))
         comps.second = match.range(at: 6).location == NSNotFound ? 0 : Int(ns.substring(with: match.range(at: 6)))
         if let date = Calendar.current.date(from: comps) { return date }
       }
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

     /// 从流水正文中提取交易时间。这里要求出现日历日期，绝不接受只有“21:14”
     /// 这种状态栏时间；优先使用带字段名的值，再扫描正文。
     private func extractTransactionDate(preferredValues: [String?], lines: [String]) -> Date? {
       let values = preferredValues.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
         .filter { !$0.isEmpty }

       for value in values where containsCalendarDate(value) {
         if let date = extractDate(from: value) { return date }
         if let date = parseDateOnly(value) { return date }
       }

       for index in lines.indices where containsCalendarDate(lines[index]) {
         let line = lines[index]
         // Vision 有时会把日期和时钟拆成相邻文本块；两者都来自正文时再合并。
         var dateText = line
         if index + 1 < lines.count, isStandaloneClockTime(lines[index + 1]) {
           dateText += " " + lines[index + 1]
         }
         if let date = extractDate(from: dateText) { return date }
         if let date = parseDateOnly(line) { return date }
         if let date = parseListDate(
           line,
           fallbackYear: Calendar.current.component(.year, from: Date()),
           monthOverride: Calendar.current.component(.month, from: Date())
         ) { return date }
       }
       return nil
     }

     private func isStandaloneClockTime(_ text: String) -> Bool {
       text.trimmingCharacters(in: .whitespacesAndNewlines)
         .range(of: #"^\d{1,2}[\.:]\d{2}(?::\d{2})?$"#, options: .regularExpression) != nil
     }

     private func containsCalendarDate(_ text: String) -> Bool {
       text.range(of: #"(?:\d{4}\s*[-/.年]\s*\d{1,2}\s*[-/.月]\s*\d{1,2}|\d{1,2}月\s*\d{1,2}日|\d{2}-\d{2}|[A-Za-z]{3}\s+\d{1,2},\s*\d{4})"#, options: .regularExpression) != nil
     }

     private func parseDateOnly(_ text: String) -> Date? {
       let formats = ["yyyy年M月d日", "yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd"]
       for format in formats {
         let formatter = DateFormatter()
         formatter.locale = Locale(identifier: "zh_CN")
          formatter.timeZone = .current
         formatter.dateFormat = format
         if let date = formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
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
       return Int(ns.substring(with: match.range(at: 2)))
     }

      private func parseListDate(_ line: String, fallbackYear: Int, monthOverride: Int) -> Date? {
        if let alipayDate = parseAlipayListDate(line, fallbackYear: fallbackYear) { return alipayDate }
        if let match = line.range(of: #"^(今天|昨天|前天)\s+(\d{1,2}):(\d{2})$"#, options: .regularExpression) {
          let parts = String(line[match]).components(separatedBy: CharacterSet(charactersIn: " :"))
          let offset = parts.first == "今天" ? 0 : (parts.first == "昨天" ? -1 : -2)
          var date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
          var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
          comps.hour = Int(parts.dropFirst().first ?? "12") ?? 12
          comps.minute = Int(parts.last ?? "0") ?? 0
          date = Calendar.current.date(from: comps) ?? date
          return date
        }
        if let regex = try? NSRegularExpression(pattern: #"^(\d{2})-(\d{2})(?:\s+(\d{1,2}):(\d{2}))?$"#),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
          let ns = line as NSString
          var comps = DateComponents()
          comps.year = fallbackYear
          comps.month = Int(ns.substring(with: match.range(at: 1))) ?? monthOverride
          comps.day = Int(ns.substring(with: match.range(at: 2))) ?? 1
          comps.hour = match.range(at: 3).location == NSNotFound ? 12 : (Int(ns.substring(with: match.range(at: 3))) ?? 12)
          comps.minute = match.range(at: 4).location == NSNotFound ? 0 : (Int(ns.substring(with: match.range(at: 4))) ?? 0)
          return Calendar.current.date(from: comps)
        }
        for format in ["MMM d, yyyy 'at' H:mm", "MMM d, yyyy"] {
          let formatter = DateFormatter()
          formatter.locale = Locale(identifier: "en_US_POSIX")
          formatter.timeZone = .current
          formatter.dateFormat = format
          if let date = formatter.date(from: line) { return date }
        }
        let regex = try? NSRegularExpression(pattern: #"^(\d{1,2})月(\d{1,2})日(?:\s+(\d{1,2}):(\d{2}))?$"#)
       let ns = line as NSString
       guard let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
       match.numberOfRanges == 5 else {
         return nil
       }
       let month = Int(ns.substring(with: match.range(at: 1))) ?? monthOverride
       let day = Int(ns.substring(with: match.range(at: 2))) ?? 1
       let hour = match.range(at: 3).location == NSNotFound ? 12 : (Int(ns.substring(with: match.range(at: 3))) ?? 12)
       let minute = match.range(at: 4).location == NSNotFound ? 0 : (Int(ns.substring(with: match.range(at: 4))) ?? 0)
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
        if extractMonthHeader(from: line) != nil && extractListAmountAnywhere(in: line) == nil { return false }
        let nonTitleLabels = ["其他", "餐饮美食", "日用百货", "保险", "交通出行", "爱车养车", "退款", "支出", "收入", "天猫", "淘宝", "支付宝", "微信", "微信支付", "银行卡"]
        if nonTitleLabels.contains(line) { return false }
        return !isNoiseLine(line) && !isBalanceLine(line) && (!line.contains("年") || extractListAmountAnywhere(in: line) != nil)
     }

     private func normalizeListMerchant(_ title: String) -> String? {
       func transferName(_ value: String?) -> String? {
         guard let value else { return nil }
         let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
         return trimmed.hasPrefix("给") ? String(trimmed.dropFirst()) : trimmed
       }
       if title.contains("付款-") {
         return transferName(title.components(separatedBy: "付款-").last)
       }
       if title.contains("-给") {
         return transferName(title.components(separatedBy: "-给").last)
       }
       if title.contains("付款‑") {
         return transferName(title.components(separatedBy: "付款‑").last)
       }
       if title.contains("转给") {
         return transferName(title.components(separatedBy: "转给").last)
       }
       if title.contains("‑给") {
         return transferName(title.components(separatedBy: "‑给").last)
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
       // Alipay labels “收钱码收款” as a payment description even when the
       // current user's transaction is an outgoing payment; the signed amount
       // is the authoritative direction signal when present.
       if let amountLine, amountLine.contains("-") || amountLine.contains("−") || amountLine.contains("‑") || amountLine.contains("﹣") || amountLine.contains("－") {
         return .expense
       }
       // “收款方”只是对方字段名，不能覆盖“转出/转给”的交易方向。
       let compactText = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
       if ["转出", "转给", "转账支出", "转账付款"].contains(where: { compactText.contains($0) }) {
         return .expense
       }
       if text.contains("付款成功") || text.contains("支付成功") || text.contains("扫码付款") ||
           text.contains("支出") || text.contains("扣款") || text.contains("消费") {
         return .expense
       }
       if ["退款", "转入", "收入", "到账", "收款成功", "已收款", "入账"].contains(where: { text.contains($0) }) {
         return .income
       }
       return fallback
     }

     private func extractAlipayDetailMerchant(from lines: [String]) -> String? {
       let fieldMap = makeFieldMap(lines: lines)
       return extractAlipayDetailMerchant(from: lines, fieldMap: fieldMap)
     }

     private func extractAlipayDetailMerchant(from lines: [String], fieldMap: [String: String]) -> String? {
       if let namedParty = fieldMap["收款方全称"] ?? fieldMap["收款方全名"] ?? fieldMap["商户全称"],
          !namedParty.isEmpty {
         return namedParty
       }
       if let nick = lines.first(where: { $0.range(of: #"^[A‑Za‑z0‑9*]{3,}$"#, options: .regularExpression) != nil }) {
         return nick
       }
       return lines.first(where: { $0.contains("淘宝") || $0.contains("天猫") || $0.contains("支付宝") })
     }

     private func extractAlipayDetailTitle(from lines: [String], amountLine: String? = nil) -> String? {
       if let amountLine, let amountIndex = lines.firstIndex(of: amountLine), amountIndex > 0 {
         let candidates = lines[..<amountIndex].reversed()
         if let title = candidates.first(where: { candidate in
           let line = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
           return !line.isEmpty &&
             !isAlipayDetailHeaderOrField(line) &&
             !isNoiseLine(line) &&
             amountTokens(in: line).isEmpty &&
             line.range(of: #"[\u4e00-\u9fffA-Za-z]"#, options: .regularExpression) != nil
         }) {
           return cleanDetailTitle(title)
         }
       }
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

     private func isAlipayDetailHeaderOrField(_ line: String) -> Bool {
       ["账单详情", "交易详情", "交易成功", "支付成功", "已完成", "支付时间", "交易时间", "商品", "商品说明",
        "商品名称", "收款方全称", "收款方全名", "收单机构", "支付方式", "付款方式", "支付渠道", "更多"]
         .contains(where: { line == $0 || line.hasPrefix($0 + ":") || line.hasPrefix($0 + "：") })
     }

     private func alipayDetailAmountLine(in lines: [String]) -> String? {
       // Prefer a standalone signed amount from the detail header; status-bar
       // clocks like 11:55 and IDs must never win over the actual payment.
       let signedAmount = lines.first { line in
         line.range(of: #"^\s*[-−‑﹣－]\s*[¥￥]?\s*\d+(?:,\d{3})*(?:\.\d{1,2})?\s*$|^\s*[-−‑﹣－]\s*[¥￥]\s*\d+(?:,\d{3})*(?:\.\d{1,2})?\s*$"#, options: .regularExpression) != nil
       }
       if let signedAmount { return signedAmount }
       return lines.first { line in
         line.range(of: #"^\s*[¥￥]\s*\d+(?:,\d{3})*(?:\.\d{1,2})?\s*$"#, options: .regularExpression) != nil
       }
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
       let pattern = #"^(\d{1,2})月(?:[.,，。、、 … :： ]*)$"#
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
    line.range(of: #"^(?:今天|昨天|前天)\s*\d{1,2}[:.]\d{2}$|^\d{2}-\d{2}(?:\s*\d{1,2}[:.]\d{2})?$"#, options: .regularExpression) != nil
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
         if let balanceIndex = lines.firstIndex(of: "零钱") {
           let following = lines.dropFirst(balanceIndex + 1)
           if let balance = following.first(where: { $0.range(of: #"^\d+(?:\.\d{1,2})$"#, options: .regularExpression) != nil }) {
             return balance
           }
         }
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

    // 信用卡“我的账单”页面可能没有单独的月份标题，但仍然包含完整的
    // 日期锚点；把整页作为一个交易区间解析，不能退化成只取月度总额。
    if sections.isEmpty && !lines.isEmpty {
        sections.append((month: Calendar.current.component(.month, from: Date()), expenseTotal: nil, items: [], lines: lines))
    }

    return sections.map { section in
        (month: section.month, expenseTotal: section.expenseTotal, items: parseAlipayListItemsRobust(in: section.lines,
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

/// 按“日期锚点 + 交易块”解析列表，不假设平台固定列位置。
private func parseAlipayListItemsRobust(in lines: [String], expenseTotal: Double?) -> [(title: String, category: String?, provider: String?, dateLine: String, amountText: String?)] {
    let dateIndices = lines.indices.filter { isAlipayDateLine(lines[$0]) }
    // 部分支付宝列表（尤其是“今天/昨天”样式）按“标题+金额、分类、日期”
    // 排列，而不是把日期放在交易块前面。先识别这种相对日期布局，避免把
    // 第一笔交易误挂到下一笔日期上。
    let usesTrailingDate = lines.contains { $0.contains("今天") || $0.contains("昨天") || $0.contains("前天") }
    var items: [(title: String, category: String?, provider: String?, dateLine: String, amountText: String?)] = []
    var currentDateLine: String?
    var currentCategory: String?
    var currentProvider: String?
    var pendingTitle: String?

    func appendItem(title rawTitle: String, amount: String?, date: String?, category categoryOverride: String? = nil, provider providerOverride: String? = nil) {
        let cleaned = extractInlineAmountAndCleanTitle(from: rawTitle).title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != "退", cleaned != "收支", cleaned != "支出", cleaned != "收入" else { return }
        items.append((title: cleaned, category: categoryOverride ?? currentCategory, provider: providerOverride ?? currentProvider, dateLine: date ?? "", amountText: amount))
    }

    var index = 0
    while index < lines.count {
        let line = lines[index]
        if usesTrailingDate {
            let inline = extractInlineAmountAndCleanTitle(from: line)
            let splitTitle = inline.title.isEmpty
                ? lines[max(0, index - 3)..<index].reversed().first(where: isLikelyAlipayTitleLine)
                : inline.title
            if let amount = inline.amountText, let title = splitTitle, !title.isEmpty {
                let end = min(lines.count, index + 4)
                if let dateIndex = lines[(index + 1)..<end].firstIndex(where: isAlipayDateLine) {
                    let block = Array(lines[(index + 1)..<dateIndex])
                    appendItem(title: title,
                               amount: amount,
                               date: lines[dateIndex],
                               category: block.first(where: isLikelyAlipayCategoryLine),
                               provider: block.first(where: isLikelyAlipayProviderLine))
                    index = dateIndex + 1
                    continue
                }
            }
        }
        if isAlipayDateLine(line) {
            currentDateLine = line
            currentCategory = nil
            currentProvider = nil
            pendingTitle = nil
            index += 1
            continue
        }
        guard currentDateLine != nil else { index += 1; continue }
        if isLikelyAlipayCategoryLine(line) { currentCategory = line; index += 1; continue }
        if isLikelyAlipayProviderLine(line) { currentProvider = line; index += 1; continue }

        let inline = extractInlineAmountAndCleanTitle(from: line)
        if let amount = inline.amountText {
            let title = inline.title == "退" || inline.title.isEmpty ? (pendingTitle ?? line) : inline.title
            appendItem(title: title, amount: amount, date: currentDateLine)
            pendingTitle = nil
            index += 1
            continue
        }

        if isLikelyAlipayTitleLine(line) {
            // 退款行常被 OCR 拆成“退 + 商户 + 金额”三列；“退”只是标记，
            // 不应覆盖已经捕获的商户标题，否则第二笔退款会被丢弃。
            if line == "退" {
                index += 1
                continue
            }
            pendingTitle = line
            var lookahead = index + 1
            var amount: String?
            while lookahead < lines.count && lookahead < index + 4 && !isAlipayDateLine(lines[lookahead]) {
                let candidate = lines[lookahead]
                if isLikelyAlipayCategoryLine(candidate) { currentCategory = candidate }
                else if isLikelyAlipayProviderLine(candidate) { currentProvider = candidate }
                else if let value = extractListAmount(from: candidate) { amount = String(value); break }
                lookahead += 1
            }
            if let amount {
                appendItem(title: line, amount: amount, date: currentDateLine)
                pendingTitle = nil
                index = lookahead + 1
                continue
            }
        }
        index += 1
    }

    if items.isEmpty, let firstDate = dateIndices.first {
        let after = Array(lines.dropFirst(firstDate + 1).prefix(5))
        let title = after.first(where: isLikelyAlipayTitleLine) ?? "未命名流水"
        let amount = after.first(where: { extractListAmount(from: $0) != nil })
            ?? (dateIndices.count == 1 ? expenseTotal.map { String(format: "%.2f", abs($0)) } : nil)
        items.append((title: title, category: after.first(where: isLikelyAlipayCategoryLine), provider: after.first(where: isLikelyAlipayProviderLine), dateLine: lines[firstDate], amountText: amount))
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
    lines.first { extractListAmount(from: $0) != nil }
}

private func isLikelyAlipayCategoryLine(_ line: String) -> Bool {
    let categories = ["其他", "日用百货", "保险", "退款", "餐饮美食", "交通出行", "爱车养车", "餐饮", "购物", "娱乐", "学习", "生活服务"]
    return categories.contains(where: { line == $0 || line.hasPrefix($0 + " ") || line.hasPrefix($0 + "·") })
}

private func isLikelyAlipayProviderLine(_ line: String) -> Bool {
    ["天猫", "淘宝", "淘", "支付宝", "闲鱼"].contains(line)
}

private func isLikelyAlipayTitleLine(_ line: String) -> Bool {
    guard line.range(of: #"[\u4e00-\u9fffA-Za-z]"#, options: .regularExpression) != nil else { return false }
    if isAlipayDateLine(line) || extractSimpleMonthHeader(from: line) != nil { return false }
    if isLikelyAlipayCategoryLine(line) || isLikelyAlipayProviderLine(line) { return false }
    if extractListAmount(from: line) != nil { return false }
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
    let normalized = line
        .replacingOccurrences(of: "·", with: "")
        .replacingOccurrences(of: "•", with: "")
        .replacingOccurrences(of: "∙", with: "")
    if let range = normalized.range(of: #"[+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:[\.:]\d{1,2})"#, options: .regularExpression) {
        let amountText = String(normalized[range]).replacingOccurrences(of: ":", with: ".")
        let title = String(normalized[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, amountText)
    }
    return (normalized, nil)
}

private func parseAlipayListDate(_ line: String, fallbackYear: Int) -> Date? {
    if let match = try? NSRegularExpression(pattern: #"^(今天|昨天|前天)\s*(\d{1,2})[:.](\d{2})$"#)
        .firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
        let ns = line as NSString
        let offset = ns.substring(with: match.range(at: 1)) == "今天" ? 0 : (ns.substring(with: match.range(at: 1)) == "昨天" ? -1 : -2)
        var date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = Int(ns.substring(with: match.range(at: 2))) ?? 12
        comps.minute = Int(ns.substring(with: match.range(at: 3))) ?? 0
        date = Calendar.current.date(from: comps) ?? date
        return date
    }
    let regex = try? NSRegularExpression(pattern: #"^(\d{2})-(\d{2})(?:\s*(\d{2})[:.](\d{2}))?$"#)
    let ns = line as NSString
    guard let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
          match.numberOfRanges == 5 else {
        return nil
    }
    let month = Int(ns.substring(with: match.range(at: 1))) ?? 1
    let day = Int(ns.substring(with: match.range(at: 2))) ?? 1
    let hour = match.range(at: 3).location == NSNotFound ? 12 : (Int(ns.substring(with: match.range(at: 3))) ?? 12)
    let minute = match.range(at: 4).location == NSNotFound ? 0 : (Int(ns.substring(with: match.range(at: 4))) ?? 0)
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

private func normalizeClassifiedResult(kind: FlowType, _ raw: (keyword: String?, path: [String], confidence: Double), happenedAt: Date? = nil)
-> (keyword: String?, path: [String], confidence: Double) {
    var keyword = raw.keyword
    var path = raw.path
    var confidence = raw.confidence

    if kind == .expense && path.first == "收入" {
        keyword = nil
        path = []
        confidence = min(confidence, 0.3)
    }
    if kind == .expense, let happenedAt {
        path = mealTimeAdjustedPath(path, date: happenedAt)
        if path.count > raw.path.count { keyword = path.last }
    }
    return (keyword, path, confidence)
}

private func mealTimeAdjustedPath(_ path: [String], date: Date) -> [String] {
    guard path.count >= 2, path[0] == "餐饮", path[1] == "日常吃饭" else { return path }
        let hour = Calendar.current.component(.hour, from: date)
    let meal = hour < 11 ? "早餐" : (hour < 16 ? "午餐" : "晚餐")
    if path.dropFirst(2).first == meal { return path }
    return Array(path.prefix(2)) + [meal]
}

} // ReceiptParser

// removed duplicate, malformed legacy tail
// ur < 16 ? "午餐" : "晚餐")
//     if path.dropFirst(2).first == meal { return path }
//     return Array(path.prefix(2)) + [meal]
// }
//
// } // ReceiptParser
// */
// Parser
// */
// Parser
// */
// malformed legacy tail removed
//     if path.dropFirst(2).first == meal { return path }
//     return Array(path.prefix(2)) + [meal]
// }
//
// } // ReceiptParser
// */
// Parser
// */
// Parser
// */
