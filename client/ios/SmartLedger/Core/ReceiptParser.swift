import Foundation

// MARK: - 规则

struct ReceiptRule {
    let category: String
    let keywords: [String]
    let tokens: [String]
    let path: [String]
}

// MARK: - 单行标签

enum OCRLineLabel {
    case merchant
    case amount
    case date
    case time
    case paymentMethod
    case category
    case note
    case other
}

// MARK: - 单条识别结果

struct OCRImportResult {
    var amount: Double?
    var merchant: String?
    var paymentMethod: String?
    var date: Date?
    var categoryKeyword: String?
    var confidence: Double
    var source: String
    var kind: FlowKind
    var fieldMap: [String: String]
}

// MARK: - 解析入口

final class ReceiptParserService {

    // MARK: 规则库
    // 图102: rules 字典，分类 -> 关键词/路径
    // 可见分类：餐饮 / 交通 / 购物 / 娱乐 / 日常 / 医疗 / 教育 / 居住 / 其他
    // 可见关键词："奶茶咖啡" / "日常吃饭" / "打车" / "水电网" / "工资" / "奖金" 等
    private let rules: [String: ReceiptRule] = [
        // 以原图为准
    ]

    // detailsKeywords：详情页判定关键词数组（图103）
    private let detailsKeywords: [String] = [
        // 以原图为准（含 "转账时间" / "账单详情" / "零钱明细" 等）
    ]

    init() {}

    // MARK: 主入口
    // 图103-104
    func parse(rawText: String) -> [OCRImportResult] {
        // 以原图为准：lines -> isDetailsPage / isWeChatTransferReceipt / isAlipayListPage 分流
    }

    func lines(rawText: String) -> [String] {
        // 以原图为准
    }

    // MARK: 行归一化 / 判断
    // 图105-106
    func normalizeLines(from text: String) -> [String] {
        // 以原图为准
    }

    func replaceNewlines(from text: String) -> String {
        // 以原图为准
    }

    func isDetailsPage(lines: [String]) -> Bool {
        // 以原图为准
    }

    func isWeChatTransferReceipt(lines: [String]) -> Bool {
        // 以原图为准
    }

    func isAlipayListPage(lines: [String]) -> Bool {
        // 以原图为准
    }

    // MARK: 微信转账详情
    // 图107-108
    func parseWeChatTransferDetails(lines: [String]) -> [OCRImportResult] {
        // 以原图为准
    }

    func classifyPaymentMethod(/* 以原图为准 */) -> String {
        // 以原图为准（"微信支付" / "零钱" / "银行卡" 等）
    }

    func extractWeChatTransfer(/* 以原图为准 */) -> OCRImportResult {
        // 以原图为准
    }

    // MARK: 支付宝详情
    func parseAlipayDetails(lines: [String]) -> [OCRImportResult] {
        // 以原图为准
    }

    // MARK: 支付宝列表页
    // 图109 / 图123-124
    func parseAlipayList(lines: [String]) -> [OCRImportResult] {
        // 以原图为准
    }

    func parseAlipayListItems(/* 以原图为准 */) -> [OCRImportResult] {
        // 以原图为准
    }

    func buildAlipayListSections(/* 以原图为准 */) -> [[OCRImportResult]] {
        // 以原图为准（图122: buildAlipayListSections）
    }

    // MARK: 兜底解析
    // 图110-111 / 图126-127
    func parseFallback(lines: [String]) -> [OCRImportResult] {
        // 以原图为准
    }

    func extractMonth(from line: String) -> Int? {
        // 以原图为准
    }

    func buildSections(from lines: [String]) -> [[String]] {
        // 以原图为准
    }

    func parseListItems(lines: [String]) -> [OCRImportResult] {
        // 以原图为准
    }

    // MARK: 金额提取
    // 图112
    func extractOriginalAmount(from line: String, lines: [String]) -> Double? {
        // 以原图为准（"原价" 判定）
    }

    func extractDiscountAmount(from line: String, fieldMap: [String: String]) -> Double? {
        // 以原图为准（"优惠" 判定）
    }

    func shouldDiscountLine(line: String) -> Bool {
        // 以原图为准
    }

    func assignWeight(for line: String, index: Int) -> Int {
        // 以原图为准（权重：200 / 120 / 50 等，按行位置）
    }

    // 图113
    func isShouldIgnoreLine(line: String) -> Bool {
        // 以原图为准（"单号" / "尾号" / "卡号" / "账单" 等噪声行）
    }

    func extractCurrency(from text: String) -> String? {
        // 以原图为准
    }

    func extractRmbAmount(from text: String) -> Double? {
        // 以原图为准
    }

    func detectKind(in text: String) -> FlowKind {
        // 以原图为准（"收入" / "支出" / "退款" 判定）
    }

    // MARK: 商户 / 标题 / 支付方式
    // 图114
    func preferMerchant(fieldMap: [String: String], lines: [String]) -> String? {
        // 以原图为准（fieldMap["商户全称"] 优先）
    }

    func preferTitle(fieldMap: [String: String], lines: [String], merchant: String?) -> String? {
        // 以原图为准
    }

    func extractPaymentMethod(from text: String, lines: [String]) -> String? {
        // 以原图为准（"支付成功" / "信用卡" / "账单" 判定）
    }

    // 图115
    func normalizePaymentMethod(raw: String?) -> String? {
        // 以原图为准（"银行卡" / "微信支付" / "支付宝" 归一）
    }

    // MARK: 日期
    // 图116-117
    func extractDate(from lines: [String]) -> Date? {
        // 以原图为准（DateFormatter 数组 + NSRegularExpression）
    }

    func extractMonthHeader(from line: String) -> (year: Int, month: Int)? {
        // 以原图为准（extractSimpleMonthHeader / extractMonthExpenseTotal 相关）
    }

    func parseListDate(/* 以原图为准 */) -> Date? {
        // 以原图为准
    }

    func isAlipayDateLine(line: String) -> Bool {
        // 以原图为准（图119）
    }

    // MARK: 列表项解析
    // 图117-118 / 图120-121
    func isItemLine(title: String, line: String) -> Bool {
        // 以原图为准（isTransactionTitleLine）
    }

    func cleanTitle(raw: String) -> String {
        // 以原图为准
    }

    func inferPaymentMethod(from text: String, title: String) -> String? {
        // 以原图为准（"支付宝" / "微信" / "零钱" / "付款" / "转给"）
    }

    func inferKind(text: String, lines: [String], amount: Double, fallback: FlowKind) -> FlowKind {
        // 以原图为准（图118: inferKind）
    }

    func extractAlipayDetailTitle(from lines: [String]) -> String? {
        // 以原图为准（图118 / 图123: extractAlipayDetailTitle）
    }

    func buildOCRItems(lines: [String], paymentMethod: String?, date: Date?, time: String?) -> [OCRImportResult] {
        // 以原图为准
    }

    func isAlipayListItem(line: String) -> Bool {
        // 以原图为准
    }

    // MARK: 支付宝详情辅助
    // 图118 / 图120-121 / 图124
    func buildAlipayDetailItems(/* 以原图为准 */) -> [OCRImportResult] {
        // 以原图为准
    }

    func nearestAlipayCategory(before line: String, lines: [String]) -> String? {
        // 以原图为准
    }

    func nearestAlipayAmount(before line: String, lines: [String]) -> Double? {
        // 以原图为准
    }

    func extractWeChatTransferFieldValue(/* 以原图为准 */) -> String? {
        // 以原图为准
    }

    func extractLabels(from lines: [String], paymentMethod: String?) -> [OCRLineLabel] {
        // 以原图为准
    }

    func extractAlipayPaymentMethod(from lines: [String]) -> String? {
        // 以原图为准
    }

    // 图122
    func isAlipayDetailTitleStopLine(line: String) -> Bool {
        // 以原图为准（"支付奖励" / "交易详情" / "账单管理" / "标签" / "支付成功" 等终止关键词）
    }

    func cleanAlipayDetailTitleLine(line: String) -> String {
        // 以原图为准
    }

    // 图125
    func extractFirstAmount(from line: String, lines: [String]) -> Double? {
        // 以原图为准
    }

    func isBalanceOrNoiseLine(line: String) -> Bool {
        // 以原图为准（余额 / 噪声行判定）
    }

    func extractMerchantName(from line: String) -> String? {
        // 以原图为准
    }

    // MARK: 兜底 / 分类
    // 图126-127
    func extractFallbackDetails(/* 以原图为准 */) -> [OCRImportResult] {
        // 以原图为准（字符串分割、规则匹配、置信度计算）
    }

    func classify(text: String) -> (category: String, path: [String], confidence: Double) {
        // 以原图为准
        // 图127: if score > bestScore / guard let bestRule
        // 若 kind == .expense && path.first == "收入"：重置 keyword / path 并限制 confidence
    }

    func normalizeClassifiedResult(/* 以原图为准 */) -> OCRImportResult {
        // 以原图为准
    }
}

// MARK: - 字段取值辅助（图111 / 图121）

private extension ReceiptParserService {

    func valueAfterColon(line: String) -> String? {
        // 以原图为准
    }

    func extractDetailTokens(from line: String) -> [String] {
        // 以原图为准
    }

    func extractCurrencySymbol(from text: String) -> String? {
        // 以原图为准
    }

    func extractSignedAmount(from text: String) -> Double? {
        // 以原图为准（含正负号金额）
    }

    func extractDetailAmount(/* 以原图为准 */) -> Double? {
        // 以原图为准
    }

    func makeFieldMap(/* 以原图为准 */) -> [String: String] {
        // 以原图为准（图110: makeFieldMap）
    }
}
