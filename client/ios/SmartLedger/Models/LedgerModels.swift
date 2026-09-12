import Foundation
import SwiftUI

enum FlowType: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense, income
    var id: String { rawValue }
    var title: String {
        switch self {
        case .expense:
            return "支出"
        case .income:
            return "收入"
        }
    }
}

enum DisplayPalette {
    static let icons: [String] = [
        "folder", "tag.fill", "bookmark.fill", "star.fill",
        "fork.knife", "takeoutbag.and.cup.and.straw.fill", "cup.and.saucer.fill", "birthday.cake.fill",
        "popcorn.fill", "cart.fill", "basket.fill", "bag.fill",
        "car.fill", "tram.fill", "train.side.front.car", "airplane.circle.fill",
        "bicycle", "bus.fill", "ferry.fill", "fuelpump.fill",
        "house.fill", "house.and.flag.fill", "bed.double.fill", "lamp.floor.fill",
        "wrench.and.screwdriver.fill", "bolt.fill", "wifi", "fan.fill",
        "cross.case.fill", "stethoscope", "pills.fill", "bandage.fill",
        "heart.fill", "figure.run", "dumbbell.fill", "soccerball.inverse",
        "gift.fill", "party.popper.fill", "sparkles", "camera.fill",
        "leaf.fill", "fish.fill", "cat.fill", "dog.fill",
        "paintpalette.fill", "scissors", "hammer.fill", "globe.asia.australia.fill",
        "text.fill",
        "book.fill", "books.vertical.fill", "graduationcap.fill", "doc.text.fill",
        "desktopcomputer", "laptopcomputer", "iphone", "applewatch",
        "banknote.fill", "creditcard.fill", "wallet.pass.fill", "building.columns.fill",
        "briefcase.fill", "shippingbox.fill", "archivebox.fill", "paperplane.fill",
        "person.2.fill", "person.2.fill", "pawprint.fill", "leaf.fill",
        "paintpalette.fill", "scissors", "hammer.fill", "globe.asia.australia.fill"
    ]

    static let colors: [String] = [
        "#EA6388", "#EF4444", "#EC4899", "#8B5CF6",
        "#94A3B8", "#64748B", "#3B82F6", "#0EA5E9",
        "#14B8A6", "#22C55E", "#F59E0B", "#F97316",
        "#EAB308", "#EF4444", "#EC4899", "#8B5CF6"
    ]
}

enum Granularity: String, Codable, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        case .year: return "年"
        }
    }
}

struct DateWindow: Sendable {
    let start: Date
    let end: Date
}

enum DateRangePreset: String, CaseIterable, Identifiable, Sendable {
    case currentWeek
    case currentMonth
    case currentQuarter
    case currentYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentWeek: return "本周"
        case .currentMonth: return "本月"
        case .currentQuarter: return "本季度"
        case .currentYear: return "本年"
        }
    }

    func resolve(calendar: Calendar = .current) -> DateWindow {
        let now = Date()
        switch self {
        case .currentWeek:
            let interval = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 24 * 3600)
            return DateWindow(start: interval.start, end: interval.end)
        case .currentMonth:
            let interval = calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 30 * 24 * 3600)
            return DateWindow(start: interval.start, end: interval.end)
        case .currentQuarter:
            let month = calendar.component(.month, from: now)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var components = calendar.dateComponents([.year], from: now)
            components.month = quarterStartMonth
            components.day = 1
            let start = calendar.date(from: components) ?? now
            let end = calendar.date(byAdding: .month, value: 3, to: start) ?? now
            return DateWindow(start: start, end: end)
        case .currentYear:
            let interval = calendar.dateInterval(of: .year, for: now) ?? DateInterval(start: now, duration: 365 * 24 * 3600)
            return DateWindow(start: interval.start, end: interval.end)
        }
    }
}

struct CustomDateRange: Equatable, Sendable {
    var start: Date
    var end: Date

    static var recent30Days: CustomDateRange {
        let end = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        return CustomDateRange(start: start, end: end)
    }

    var resolvedWindow: DateWindow {
        DateWindow(
            start: Calendar.current.startOfDay(for: start),
            end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? end
        )
    }
}

struct LedgerCategory: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let flowType: FlowType
    let icon: String?
    let color: String?
    let parentId: Int?
    let level: Int
    let children: [LedgerCategory]

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color, level, children
        case flowType = "flow_type"
        case parentId = "parent_id"
    }

    var displayName: String { name }

    var pathComponents: [String] {
        name.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    var isLeaf: Bool { children.isEmpty }

    func flattened(prefix: [String] = []) -> [LedgerCategory] {
        let currentPrefix = prefix + [name]
        let current = LedgerCategory(
            id: id,
            name: currentPrefix.joined(separator: " / "),
            flowType: flowType,
            icon: icon,
            color: color,
            parentId: parentId,
            level: level,
            children: []
        )
        return [current] + children.flatMap { $0.flattened(prefix: currentPrefix) }
    }

    func leafFlattened(prefix: [String] = []) -> [LedgerCategory] {
        let currentPrefix = prefix + [name]
        if children.isEmpty {
            return [
                LedgerCategory(
                    id: id,
                    name: currentPrefix.joined(separator: " / "),
                    flowType: flowType,
                    icon: icon,
                    color: color,
                    parentId: parentId,
                    level: level,
                    children: []
                )
            ]
        }
        return children.flatMap { $0.leafFlattened(prefix: currentPrefix) }
    }

    func selectableFlattened(prefix: [String] = []) -> [LedgerCategory] {
        let currentPrefix = prefix + [name]
        let current = LedgerCategory(
            id: id,
            name: currentPrefix.joined(separator: " / "),
            flowType: flowType,
            icon: icon,
            color: color,
            parentId: parentId,
            level: level,
            children: []
        )
        guard !children.isEmpty else { return [current] }
        return [current] + children.flatMap { $0.selectableFlattened(prefix: currentPrefix) }
    }
}

struct LedgerTransaction: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let amount: Double
    let kind: FlowType
    let happenedAt: Date
    let note: String?
    let merchant: String?
    let paymentMethod: String?
    let source: String
    let currency: String
    let categoryId: Int?
    let categoryName: String?
    let bookId: Int?
    let bookName: String?
    let bookIds: [Int]
    let bookNames: [String]
    let installmentGroupId: String?
    let installmentIndex: Int?
    let installmentMonths: Int?
    let paidByParticipantId: String?
    let paidByParticipantName: String?
    let splitParticipantIds: [String]
    let splitParticipantNames: [String]
    var installmentOriginalTotal: Double? = nil
    var originalAmount: Double? = nil
    var discountAmount: Double? = nil
    var premiumAmount: Double? = nil
    var installmentStartMonth: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, amount, kind, note, merchant, source, currency
        case paymentMethod = "payment_method"
        case happenedAt = "happened_at"
        case categoryId = "category_id"
        case categoryName = "category_name"
        case bookId = "book_id"
        case bookIds = "book_ids"
        case bookName = "book_name"
        case bookNames = "book_names"
        case installmentGroupId = "installment_group_id"
        case installmentIndex = "installment_index"
        case installmentMonths = "installment_months"
        case paidByParticipantId = "paid_by_participant_id"
        case paidByParticipantName = "paid_by_participant_name"
        case splitParticipantIds = "split_participant_ids"
        case splitParticipantNames = "split_participant_names"
        case installmentOriginalTotal = "installment_original_total"
        case originalAmount = "original_amount"
        case discountAmount = "discount_amount"
        case premiumAmount = "premium_amount"
        case installmentStartMonth = "installment_start_month"
    }
}

struct TrendPoint: Codable, Identifiable, Sendable {
    let label: String
    let income: Double
    let expense: Double
    let balance: Double

    var id: String { label }
}

struct DistributionPoint: Codable, Identifiable, Sendable {
    let category: String
    let amount: Double
    let ratio: Double
    let color: String?
    var id: String { category }
}

enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case monthly
    var id: String { rawValue }
}

struct BudgetItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let limitAmount: Double
    let periodType: String
    let categoryId: Int?
    let categoryName: String?
    let year: Int
    let month: Int?
    let startDate: Date?
    let endDate: Date?
    let spentAmount: Double
    let usageRatio: Double

    enum CodingKeys: String, CodingKey {
        case id, name, limitAmount, categoryId, startDate, endDate, spentAmount, usageRatio
        case periodType = "period_type"
        case categoryName = "category_name"
        case year, month
    }
}

struct BudgetReport: Identifiable, Codable, Hashable {
    let id: UUID
}

struct OCRResult: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String?
    let merchant: String?
    let amount: Double?
    let kind: FlowType?
    let categoryKeyword: String?
    let paymentMethod: String?
    let happenedAt: Date?
    let currency: String?
    let categoryPath: [String]?
}

struct LedgerBook: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let icon: String?
    let color: String?
    let note: String?
    let startDate: Date?
    let endDate: Date?
    let budgetLimitAmount: Double?
    let budgetStartDate: Date?
    let budgetEndDate: Date?
    let autoCollectEnabled: Bool
    let expenseAmount: Double
    let incomeAmount: Double
    let balance: Double
    let transactionCount: Int
    let participantNames: [String]
    let isPinned: Bool
    let autoCollectCategoryIds: [Int]

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color, note, balance
        case startDate = "start_date"
        case endDate = "end_date"
        case autoCollectEnabled = "auto_collect_enabled"
        case budgetLimitAmount = "budget_limit_amount"
        case budgetStartDate = "budget_start_date"
        case budgetEndDate = "budget_end_date"
        case expenseAmount = "expense_amount"
        case incomeAmount = "income_amount"
        case transactionCount = "transaction_count"
        case participantNames = "participant_names"
        case isPinned = "is_pinned"
        case autoCollectCategoryIds = "auto_collect_category_ids"
    }

    var splitEnabled: Bool { participantNames.count > 1 }
    var budgetEnabled: Bool { (budgetLimitAmount ?? 0) > 0 }

    var participants: [BookParticipant] {
        guard splitEnabled else { return [] }
        return participantNames.map { BookParticipant(id: $0, name: $0) }
    }
}

// Compatibility initializers keep the existing store code source-compatible while
// persisted models use their newer field order.
extension LedgerTransaction {
    init(id: Int, title: String, amount: Double, kind: FlowType, happenedAt: Date, note: String?, merchant: String?, paymentMethod: String?, source: String, currency: String, categoryId: Int?, categoryName: String?, bookId: Int?, bookName: String?, bookIds: [Int], bookNames: [String], installmentGroupId: String?, installmentIndex: Int?, installmentMonths: Int?, installmentOriginalTotal: Double?, originalAmount: Double?, discountAmount: Double?, premiumAmount: Double?, paidByParticipantId: String?, paidByParticipantName: String?, splitParticipantIds: [String], splitParticipantNames: [String]) {
        self.init(id: id, title: title, amount: amount, kind: kind, happenedAt: happenedAt, note: note, merchant: merchant, paymentMethod: paymentMethod, source: source, currency: currency, categoryId: categoryId, categoryName: categoryName, bookId: bookId, bookName: bookName, bookIds: bookIds, bookNames: bookNames, installmentGroupId: installmentGroupId, installmentIndex: installmentIndex, installmentMonths: installmentMonths, paidByParticipantId: paidByParticipantId, paidByParticipantName: paidByParticipantName, splitParticipantIds: splitParticipantIds, splitParticipantNames: splitParticipantNames, installmentOriginalTotal: installmentOriginalTotal, originalAmount: originalAmount, discountAmount: discountAmount, premiumAmount: premiumAmount, installmentStartMonth: nil)
    }
}

extension LedgerBook {
    init(id: Int, name: String, icon: String?, color: String?, note: String?, startDate: Date?, endDate: Date?, autoCollectEnabled: Bool, budgetLimitAmount: Double?, budgetStartDate: Date?, budgetEndDate: Date?, expenseAmount: Double, incomeAmount: Double, balance: Double, transactionCount: Int, participantNames: [String], isPinned: Bool, autoCollectCategoryIds: [Int]) {
        self.init(id: id, name: name, icon: icon, color: color, note: note, startDate: startDate, endDate: endDate, budgetLimitAmount: budgetLimitAmount, budgetStartDate: budgetStartDate, budgetEndDate: budgetEndDate, autoCollectEnabled: autoCollectEnabled, expenseAmount: expenseAmount, incomeAmount: incomeAmount, balance: balance, transactionCount: transactionCount, participantNames: participantNames, isPinned: isPinned, autoCollectCategoryIds: autoCollectCategoryIds)
    }
}

extension BudgetItem {
    init(id: Int, name: String, limitAmount: Double, periodType: String, year: Int, month: Int?, startDate: Date?, endDate: Date?, categoryId: Int?, categoryName: String?, spentAmount: Double, usageRatio: Double) {
        self.init(id: id, name: name, limitAmount: limitAmount, periodType: periodType, categoryId: categoryId, categoryName: categoryName, year: year, month: month, startDate: startDate, endDate: endDate, spentAmount: spentAmount, usageRatio: usageRatio)
    }
}

struct BookParticipant: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

enum CloudSyncState: String { case disabled, idle, syncing, success, unavailable, conflict, failed
    var title: String { self == .disabled ? "未启用" : self == .idle ? "等待同步" : self == .syncing ? "同步中" : self == .success ? "已同步" : self == .unavailable ? "iCloud 不可用" : self == .conflict ? "需要选择版本" : "失败" }
}

struct BookSplitSummary: Identifiable, Sendable {
    let participant: BookParticipant
    let paid: Double
    let owed: Double
    let net: Double

    var id: String { participant.id }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { self == .system ? "跟随系统" : self == .light ? "白天模式" : "夜间模式" }
}

struct AnalyticsOverview: Codable, Sendable {
    let start: String
    let end: String
    let totalIncome: Double
    let totalExpense: Double
    let balance: Double
    let distribution: [DistributionPoint]
    let trend: [TrendPoint]
    let budgets: [BudgetItem]
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 24, 144, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension Color {
    init?(hexString: String) {
        let v = UInt64(hexString.dropFirst(), radix: 16) ?? 0
        guard v != 0 || hexString.lowercased() == "#000000" else { return nil }
        let r: CGFloat = CGFloat((v & 0xFF0000) >> 16) / 255
        let g: CGFloat = CGFloat((v & 0x00FF00) >> 8) / 255
        let b: CGFloat = CGFloat(v & 0x0000FF) / 255
        let a: CGFloat = hexString.count > 7 ? CGFloat((v & 0xFF000000) >> 24) / 255 : 1
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension Double {
    var currency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: NSNumber(value: self)) ?? "¥\(self)"
    }
}

struct CategoryTrendSeries: Codable, Identifiable, Sendable {
    let category: String
    let labels: [String]
    let values: [Double]

    var id: String { category }
}

struct CategoryTrendResponse: Codable, Sendable {
    let category: String
    let labels: [String]
    let series: [CategoryTrendSeries]
}

struct CategoryTrendChartPoint: Identifiable, Sendable {
    let category: String
    let label: String
    let value: Double

    var id: String { "\(category)-\(label)" }
}

struct OCRInputPayload: Encodable, Sendable {
    let rawText: String
}

enum OCRInputKeys: String, CodingKey {
    case rawText = "raw_text"
}

struct OCRLineItem: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let value: String
}

extension OCRLineItem {
    init(label: String, value: String) {
        self.init(id: UUID().uuidString, label: label, value: value)
    }
}

extension OCRImportResult {
    init(amount: Double?, kind: FlowType?, merchant: String?, paymentMethod: String?, title: String?, happenedAt: Date?, categoryKeyword: String?, categoryPath: [String]?, details: [OCRLineItem]?, confidence: Double?, rawLines: [String]?, originalAmount: Double?, discountAmount: Double?) {
        self.amount = amount
        self.kind = kind
        self.merchant = merchant
        self.title = title
        self.happenedAt = happenedAt
        self.paymentMethod = paymentMethod
        self.categoryKeyword = categoryKeyword
        self.categoryPath = categoryPath
        self.details = details
        self.rawLines = rawLines
        self.originalAmount = originalAmount
        self.discountAmount = discountAmount
        self.confidence = confidence
    }
}

struct OCRImportResult: Codable, Identifiable, Sendable {
    var id: String {
        title ?? merchant ?? "ocr"
    }
    var amount: Double?
    var kind: FlowType?
    var merchant: String?
    var title: String?
    var happenedAt: Date?
    var paymentMethod: String?
    var categoryKeyword: String?
    var categoryPath: [String]?
    var details: [OCRLineItem]?
    var rawLines: [String]?
    var originalAmount: Double?
    var discountAmount: Double?
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case amount, kind, merchant, title, details, confidence
        case paymentMethod = "payment_method"
        case happenedAt = "happened_at"
        case categoryKeyword = "category_keyword"
        case categoryPath = "category_path"
        case rawLines = "raw_lines"
        case originalAmount = "original_amount"
        case discountAmount = "discount_amount"
    }
}

struct TransactionDraft {
    var title: String = ""
    var amount: String = ""
    var kind: FlowType = .expense
    var happenedAt: Date = .now
    var note: String = ""
    var merchant: String = ""
    var paymentMethod: String = ""
    var categoryId: Int?
    var bookId: Int?
    var bookIds: [Int] = []
    var bookNames: [String] = []
    var originalAmount: String = ""
    var discountAmount: String = ""
    var premiumAmount: String = ""
    var installmentEnabled: Bool = false
    var installmentMonths: Int = 1
    var installmentStartMonth: Date = .now
    var ocrText: String?
    var source: String = "manual"
    var splitParticipantIds: [String] = []
    var paidByParticipantId: String?

    init() {}

    init(source: String) {
        self.source = source
    }

    init(transaction: LedgerTransaction) {
        self.title = transaction.title
        self.amount = String(format: "%.2f", transaction.amount)
        self.kind = transaction.kind
        self.happenedAt = transaction.happenedAt
        self.categoryId = transaction.categoryId
        self.bookId = transaction.bookId
        self.bookIds = transaction.bookIds
        self.note = transaction.note ?? ""
        self.merchant = transaction.merchant ?? ""
        self.paymentMethod = transaction.paymentMethod ?? ""
        self.source = transaction.source ?? "manual"
        self.originalAmount = transaction.originalAmount.map { String(format: "%.2f", $0) } ?? ""
        self.discountAmount = transaction.discountAmount.map { String(format: "%.2f", $0) } ?? ""
        self.premiumAmount = transaction.premiumAmount.map { String(format: "%.2f", $0) } ?? ""
        self.installmentEnabled = transaction.installmentMonths != nil
        self.installmentMonths = transaction.installmentMonths ?? 1
        self.installmentStartMonth = transaction.installmentStartMonth ?? .now
        self.ocrText = nil
        self.paidByParticipantId = transaction.paidByParticipantId
        self.splitParticipantIds = transaction.splitParticipantIds ?? []
    }

    init(parsed: OCRImportResult, source: String = "ocr") {
        self.source = source
        self.title = parsed.title ?? ""
        self.amount = parsed.amount.map { String(format: "%.2f", $0) } ?? ""
        self.kind = parsed.kind ?? .expense
        self.happenedAt = parsed.happenedAt ?? .now
        self.paymentMethod = parsed.paymentMethod ?? ""
        self.merchant = parsed.merchant ?? ""
        self.note = ""
        self.source = source
        self.originalAmount = parsed.originalAmount.map { String(format: "%.2f", $0) } ?? ""
        self.discountAmount = parsed.discountAmount.map { String(format: "%.2f", $0) } ?? ""
        self.premiumAmount = ""
        self.installmentEnabled = false
        self.installmentMonths = 1
        self.installmentStartMonth = .now
        self.ocrText = parsed.rawLines?.joined(separator: "\n")
        self.paidByParticipantId = nil
        self.splitParticipantIds = []
    }

    func toRequest() -> CreateTransactionRequest {
        return CreateTransactionRequest(
            title: title,
            amount: Double(amount) ?? 0,
            kind: kind,
            happenedAt: happenedAt,
            note: note.isEmpty ? nil : note,
            merchant: merchant.isEmpty ? nil : merchant,
            paymentMethod: paymentMethod.isEmpty ? nil : paymentMethod,
            source: source,
            currency: "CNY",
            categoryId: categoryId,
            bookId: bookId,
            bookIds: bookIds.isEmpty ? nil : bookIds,
            originalAmount: Double(originalAmount),
            discountAmount: Double(discountAmount),
            premiumAmount: Double(premiumAmount),
            installmentEnabled: installmentEnabled && installmentMonths > 1,
            installmentMonths: installmentEnabled && installmentMonths > 1 ? installmentMonths : nil,
            installmentStartMonth: installmentEnabled && installmentMonths > 1 ? Calendar.current.startOfDay(for: installmentStartMonth) : nil,
            paidByParticipantId: paidByParticipantId,
            splitParticipantIds: splitParticipantIds
        )
    }
}

struct CreateTransactionRequest: Encodable, Sendable {
    let title: String
    let amount: Double
    let kind: FlowType
    let happenedAt: Date
    let note: String?
    let merchant: String?
    let paymentMethod: String?
    let source: String
    let currency: String
    let categoryId: Int?
    let bookId: Int?
    let bookIds: [Int]?
    let originalAmount: Double?
    let discountAmount: Double?
    let premiumAmount: Double?
    let installmentEnabled: Bool
    let installmentMonths: Int?
    let installmentStartMonth: Date?
    let paidByParticipantId: String?
    let splitParticipantIds: [String]?

    enum CodingKeys: String, CodingKey {
        case title, amount, kind, note, merchant, source, currency
        case paymentMethod = "payment_method"
        case happenedAt = "happened_at"
        case categoryId = "category_id"
        case bookId = "book_id"
        case bookIds = "book_ids"
        case originalAmount = "original_amount"
        case discountAmount = "discount_amount"
        case premiumAmount = "premium_amount"
        case installmentEnabled = "installment_enabled"
        case installmentMonths = "installment_months"
        case installmentStartMonth = "installment_start_month"
        case paidByParticipantId = "paid_by_participant_id"
        case splitParticipantIds = "split_participant_ids"
    }
}

struct BudgetDraft: Encodable, Sendable {
    var name: String
    var limitAmount: Double
    var periodType: String = "monthly"
    var year: Int
    var month: Int?
    var startDate: Date?
    var endDate: Date?
    var categoryId: Int?

    enum CodingKeys: String, CodingKey {
        case name, year, month
        case limitAmount = "limit_amount"
        case periodType = "period_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case categoryId = "category_id"
    }
}

struct BookDraft: Encodable, Sendable {
    var name: String
    var icon: String?
    var note: String?
    var color: String?
    var startDate: Date?
    var endDate: Date?
    var budgetLimitAmount: Double?
    var budgetStartDate: Date?
    var budgetEndDate: Date?
    var autoCollectEnabled: Bool = false
    var participantNames: [String]
    var isPinned: Bool = false
    var autoCollectCategoryIds: [Int] = []

    enum CodingKeys: String, CodingKey {
        case name, icon, color, note
        case startDate = "start_date"
        case endDate = "end_date"
        case isPinned = "is_pinned"
        case autoCollectEnabled = "auto_collect_enabled"
        case budgetLimitAmount = "budget_limit_amount"
        case budgetStartDate = "budget_start_date"
        case budgetEndDate = "budget_end_date"
        case participantNames = "participant_names"
        case autoCollectCategoryIds = "auto_collect_category_ids"
    }
}

struct CategoryDraft: Encodable, Sendable {
    var name: String
    var flowType: FlowType = .expense
    var icon: String?
    var color: String?
    var parentId: Int?

    enum CodingKeys: String, CodingKey {
        case name, icon, color
        case flowType = "flow_type"
        case parentId = "parent_id"
    }
}

extension Date {
    var apiDateString: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}

extension Double {
    var cnYText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: NSNumber(value: self)) ?? "¥\(self)"
    }

    var cnyText: String { cnYText }
    var cnText: String { cnYText }
}
