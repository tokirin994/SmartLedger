import Foundation
import SwiftUI

enum FlowType: String, Codable, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var title: String { self == .expense ? "支出" : "收入" }
    var color: Color { self == .expense ? .red : .green }

    var icon: String {
        switch self {
        case .expense:
            return "$"
        case .income:
            return "收入"
        }
    }
}

enum DisplayPalette {
    static let icons: [String] = [
        "bag.fill", "tray.full", "bookmark.fill", "star.fill",
        "fork.knife", "takeoutbag.and.cup.and.straw.fill", "cup.and.saucer.fill",
        "birthdaycake.fill",
        "popcorn.fill", "basket.fill", "bag.fill",
        "car.fill", "tram.fill", "train.side.front.car", "airplane.circle.fill",
        "bicycle", "bus.fill", "ferry.fill", "fuelpump.fill",
        "house.fill", "house.and.flag.fill", "bed.double.fill", "lamp.floor.fill",
        "wrench.and.screwdriver.fill", "bolt.fill", "wifi", "fan.fill",
        "cross.case.fill", "stethoscope", "pills.fill", "bandage.fill",
        "heart.fill", "figure.run", "soccerball", "basketball.inverse",
        "gamecontroller.fill", "tv.fill", "music.note", "ticket.fill",
        "gift.fill", "party.popper.fill", "sparkles", "camera.fill",
        "leaf.fill", "fish.fill", "cat.fill", "dog.fill",
        "paintpalette.fill", "scissors", "hammer.fill", "globe.asia.australia.fill",
        "text.fill"
    ]

    static let colors: [String] = [
        "#5A4B8E", "#EA4080", "#28B576", "#3EA55E",
        "#148A8A", "#2C205E", "#F55609", "#FF9731",
        "#EA6388", "#EF4444", "#EC4899", "#8B5CF6"
    ]
}

enum Granularity: String, Codable, CaseIterable, Identifiable {
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
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)!
            return DateWindow(start: interval.start, end: interval.end)
        case .currentMonth:
            let interval = calendar.dateInterval(of: .month, for: now)!
            return DateWindow(start: interval.start, end: interval.end)
        case .currentQuarter:
            let month = calendar.component(.month, from: now)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var components = calendar.dateComponents([.year], from: now)
            components.month = quarterStartMonth
            components.day = 1
            let start = calendar.date(from: components) ?? now
            let end = calendar.date(byAdding: .month, value: 3, to: start)
            return DateWindow(start: start, end: end)
        case .currentYear:
            let interval = calendar.dateInterval(of: .year, for: now)!
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

    var resolved: DateWindow {
        DateWindow(
            start: Calendar.current.startOfDay(for: start),
            end: Calendar.current.date(byAdding: .day, value: 1, to:
                Calendar.current.startOfDay(for: end)) ?? end
        )
    }
}

struct DateWindow: Sendable {
    let start: Date
    let end: Date
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

    var displayName: String { name }

    var pathComponents: [String] {
        name.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    var isLeaf: Bool { children.isEmpty }

    func flattened(prefix: [String] = []) -> [LedgerCategory] {
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
        return children.flatMap { $0.flattened(prefix: currentPrefix) }
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

enum CodingKeys: String, CodingKey {
    case id, name, icon, color, note
    case flowType = "flow_type"
    case parentId = "parent_id"
}

struct LedgerTransaction: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let title: String
    let amount: Double
    let happenedAt: Date
    let note: String?
    let kind: FlowType
    let merchant: String?
    let paymentMethod: String?
    let source: String?
    let currency: String?
    let categoryId: Int?
    let categoryName: String?
    let bookId: Int?
    let bookName: String?
    let bookIds: [Int]?
    let bookNames: [String]?
    let installmentIndex: Int?
    let installmentGroupId: String?
    let installmentMonths: Int?
    let installmentStartMonth: Date?
    let installmentOriginalTotal: Double?
    let originalAmount: Double?
    let discountAmount: Double?
    let premiumAmount: Double?
    let paidByParticipantId: String?
    let paidByParticipantName: String?
    let splitParticipantIds: [String]?
    let splitParticipantNames: [String]?

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
        case installmentIndex = "installment_index"
        case installmentGroupId = "installment_group_id"
        case installmentMonths = "installment_months"
        case installmentStartMonth = "installment_start_month"
        case installmentOriginalTotal = "installment_original_total"
        case originalAmount = "original_amount"
        case discountAmount = "discount_amount"
        case premiumAmount = "premium_amount"
        case paidByParticipantId = "paid_by_participant_id"
        case paidByParticipantName = "paid_by_participant_name"
        case splitParticipantIds = "split_participant_ids"
        case splitParticipantNames = "split_participant_names"
    }
}

struct LedgerTransaction: Identifiable, Codable, Hashable {
    var id = UUID(); var title: String; var kind: FlowType; var amount: Double
    var happenedAt: Date; var note: String?; var merchant: String?; var paymentMethod: String?
    var source: String?; var currency: String?; var categoryId: Int?; var categoryName: String?
    var bookId: Int?; var bookName: String?; var bookIds: [Int]?; var bookNames: [String]?
    var installmentGroupId: UUID?; var installmentIndex: Int?; var installmentMonths: Int?
    var installmentStartMonth: Date?; var installmentOriginalTotal: Double?
    var originalAmount: Double?; var discountAmount: Double?; var premiumAmount: Double?
    var paidByParticipantId: String?; var paidByParticipantName: String?
    var splitParticipantIds: [String]?; var splitParticipantNames: [String]?
}

struct TrendPoint: Codable, Identifiable, Sendable {
    let label: String
    let income: Double
    let expense: Double
    let balance: Double
}

struct DistributionPoint: Codable, Identifiable, Sendable {
    let category: String
    let amount: Double
    let ratio: Double
    let color: String?
    let id: String { category }
}

enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case monthly
    var id: String { rawValue }
    var title: String { self == .monthly ? "月度" : "" }
}

struct BudgetItem: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let limitAmount: Double
    let period: BudgetPeriod
    let categoryId: UUID?
    let startDate: Date?
    let endDate: Date?
    let spentAmount: Double
    let usageRatio: Double
    enum CodingKeys: String, CodingKey {
        case id, name, limitAmount, period, categoryId, startDate, endDate, spentAmount, usageRatio
    }
}

struct BudgetReport: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let period: BudgetPeriod
    let limitAmount: Double
    let spentAmount: Double
    let usageRatio: Double
    let categoryName: String?
    let month: Int?
}

enum CodingKeys: String, CodingKey {
    case id, name, month, year
    case limitAmount = "limit_amount"
    case periodType = "period_type"
    case startDate = "start_date"
    case endDate = "end_date"
    case categoryId = "category_id"
    case categoryName = "category_name"
    case spentAmount = "spent_amount"
    case usageRatio = "usage_ratio"
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
    let details: [String]?
    let originalAmount: Double?
    let discountAmount: Double?
    let realLines: [String]?
}

struct LedgerBook: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let icon: String?
    let color: String?
    let startDate: Date?
    let endDate: Date?
    let budgetLimit: Double?
    let budgetStartDate: Date?
    let budgetEndDate: Date?
    let autoCollectEnabled: Bool
    let autoCollectCategoryIds: [Int]?
    let participants: [BookParticipant]?
    let isSplit: Bool
    var budgetEnabled: Bool { budgetLimit != nil }
    var splitEnabled: Bool { participants?.count ?? 0 > 1 }
    func participants() -> [BookParticipant] {
        guard splitEnabled else { return [] }
        return participantNames.map { BookParticipant(id: $0, name: $0) }
    }
}

enum CodingKeys: String, CodingKey {
    case id, name, icon, color, note, balance
    case startDate = "start_date"
    case endDate = "end_date"
    case autoCollectEnabled = "auto_collect_enabled"
    case budgetLimit = "budget_limit"
    case budgetStartDate = "budget_start_date"
    case budgetEndDate = "budget_end_date"
    case expenseAmount = "expense_amount"
    case incomeAmount = "income_amount"
    case transactionCount = "transaction_count"
    case participantNames = "participant_names"
    case isSplit = "is_split"
    case autoCollectCategoryIds = "auto_collect_category_ids"
}

var splitEnabled: Bool { participantNames.count > 1 }

var participants: [BookParticipant] {
    guard splitEnabled else { return [] }
    return participantNames.map { BookParticipant(id: $0, name: $0) }
}

struct BookParticipant: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
}

struct AppleAccountProfile: Codable {
    var userIdentifier: String
    var fullName: String?
    var email: String?
    var authorizedClientId: String?
    var authorizationCode: String?
    var identityToken: String?
    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

enum CloudSyncState: String { case disabled, idle, syncing, success, unavailable, conflict, failed
    var title: String { self == .disabled ? "未启用" : self == .idle ? "等待同步" : self == .syncing ? "同步中" : self == .success ? "已同步" : self == .unavailable ? "iCloud 不可用" : self == .conflict ? "需要选择版本" : "失败" }
}

struct BookSplitSummary: Sendable {
    let participant: BookParticipant
    let paid: Double
    let owed: Double
    let net: Double

    var id: String { participant.id }
    var net: Double { paid - owed }
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

struct PersistedLedgerSnapshot: Codable {
    var categories: [LedgerCategory]
    var books: [LedgerBook]
    var transactions: [LedgerTransaction]
    var budgets: [BudgetItem]
    enum CodingKeys: String, CodingKey {
        case categories, books, transactions, budgets
        case startDate = "start_date"
        case endDate = "end_date"
        case totalIncome = "total_income"
        case totalExpense = "total_expense"
    }
}

extension Color {
    init(hex: String) {
        let v = UInt64(hex.dropFirst(), radix: 16) ?? 0
        let r: CGFloat = CGFloat((v & 0xFF0000) >> 16) / 255
        let g: CGFloat = CGFloat((v & 0x00FF00) >> 8) / 255
        let b: CGFloat = CGFloat(v & 0x0000FF) / 255
        let a: CGFloat = hex.count > 7 ? CGFloat((v & 0xFF000000) >> 24) / 255 : 1
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension Color {
    init?(hexString: String) {
        let v = UInt64(hex.dropFirst(), radix: 16) ?? 0
        guard v != 0 || hex.lowercased() == "#000000" else { return nil }
        let r: CGFloat = CGFloat((v & 0xFF0000) >> 16) / 255
        let g: CGFloat = CGFloat((v & 0x00FF00) >> 8) / 255
        let b: CGFloat = CGFloat(v & 0x0000FF) / 255
        let a: CGFloat = hex.count > 7 ? CGFloat((v & 0xFF000000) >> 24) / 255 : 1
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

extension LedgerBook {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        budgetLimit = try container.decodeIfPresent(Double.self, forKey: .budgetLimit)
        budgetStartDate = try container.decodeIfPresent(Date.self, forKey: .budgetStartDate)
        budgetEndDate = try container.decodeIfPresent(Date.self, forKey: .budgetEndDate)
        expenseAmount = try container.decodeIfPresent(Double.self, forKey: .expenseAmount)
        incomeAmount = try container.decodeIfPresent(Double.self, forKey: .incomeAmount)
        balance = try container.decodeIfPresent(Double.self, forKey: .balance)
        transactionCount = try container.decodeIfPresent(Int.self, forKey: .transactionCount)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        participantNames = try container.decodeIfPresent([String].self, forKey: .participantNames) ?? []
        autoCollectCategoryIds = try container.decodeIfPresent([Int].self, forKey: .autoCollectCategoryIds) ?? []
        autoCollectEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoCollectEnabled) ?? false
    }
}

extension LedgerTransaction {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        amount = try container.decode(Double.self, forKey: .amount)
        happenedAt = try container.decode(Date.self, forKey: .happenedAt)
        kind = try container.decode(FlowType.self, forKey: .kind)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        merchant = try container.decodeIfPresent(String.self, forKey: .merchant)
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        categoryId = try container.decodeIfPresent(Int.self, forKey: .categoryId)
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        bookId = try container.decodeIfPresent(Int.self, forKey: .bookId)
        bookName = try container.decodeIfPresent(String.self, forKey: .bookName)
        bookIds = try container.decodeIfPresent([Int].self, forKey: .bookIds)
        bookNames = try container.decodeIfPresent([String].self, forKey: .bookNames)
        installmentGroupId = try container.decodeIfPresent(String.self, forKey: .installmentGroupId)
        installmentIndex = try container.decodeIfPresent(Int.self, forKey: .installmentIndex)
        installmentMonths = try container.decodeIfPresent(Int.self, forKey: .installmentMonths)
        installmentStartMonth = try container.decodeIfPresent(Date.self, forKey: .installmentStartMonth)
        installmentOriginalTotal = try container.decodeIfPresent(Double.self, forKey: .installmentOriginalTotal)
        originalAmount = try container.decodeIfPresent(Double.self, forKey: .originalAmount)
        discountAmount = try container.decodeIfPresent(Double.self, forKey: .discountAmount)
        premiumAmount = try container.decodeIfPresent(Double.self, forKey: .premiumAmount)
        paidByParticipantId = try container.decodeIfPresent(String.self, forKey: .paidByParticipantId)
        paidByParticipantName = try container.decodeIfPresent(String.self, forKey: .paidByParticipantName)
        splitParticipantIds = try container.decodeIfPresent([String].self, forKey: .splitParticipantIds)
        splitParticipantNames = try container.decodeIfPresent([String].self, forKey: .splitParticipantNames)
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

struct CategoryTrendDiverPoint: Identifiable, Sendable {
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
    var octText: String?
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
        self.bookIds = transaction.bookIds ?? (transaction.bookName.map { [$0] } ?? [])
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
        self.octText = nil
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
        self.note = parsed.note ?? ""
        self.source = source
        self.originalAmount = parsed.originalAmount.map { String(format: "%.2f", $0) } ?? ""
        self.discountAmount = parsed.discountAmount.map { String(format: "%.2f", $0) } ?? ""
        self.premiumAmount = ""
        self.installmentEnabled = false
        self.installmentMonths = 1
        self.installmentStartMonth = .now
        self.octText = parsed.rawLines?.joined(separator: "\n")
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

extension Date {
    var isoDateString: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}

extension Double {
    var cnYuanText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: NSNumber(value: self)) ?? "¥\(self)"
    }
}

extension LedgerBook: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        budgetLimitAmount = try container.decodeIfPresent(Double.self, forKey: .budgetLimitAmount)
        budgetStartDate = try container.decodeIfPresent(Date.self, forKey: .budgetStartDate)
        budgetEndDate = try container.decodeIfPresent(Date.self, forKey: .budgetEndDate)
        expenseAmount = try container.decodeIfPresent(Double.self, forKey: .expenseAmount)
        incomeAmount = try container.decodeIfPresent(Double.self, forKey: .incomeAmount)
        balance = try container.decodeIfPresent(Double.self, forKey: .balance)
        transactionCount = try container.decodeIfPresent(Int.self, forKey: .transactionCount)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        autoCollectEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoCollectEnabled) ?? false
        participantNames = try container.decodeIfPresent([String].self, forKey: .participantNames) ?? []
        autoCollectCategoryIds = try container.decodeIfPresent([Int].self, forKey: .autoCollectCategoryIds) ?? []
    }
}

extension LedgerTransaction {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        amount = try container.decode(Double.self, forKey: .amount)
        kind = try container.decode(FlowType.self, forKey: .kind)
        happenedAt = try container.decode(Date.self, forKey: .happenedAt)
        merchant = try container.decodeIfPresent(String.self, forKey: .merchant)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod)
        source = try container.decode(String.self, forKey: .source)
        currency = try container.decode(String.self, forKey: .currency)
        categoryId = try container.decodeIfPresent(Int.self, forKey: .categoryId)
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        bookId = try container.decodeIfPresent(Int.self, forKey: .bookId)
        bookName = try container.decodeIfPresent(String.self, forKey: .bookName)
        bookIds = try container.decodeIfPresent([String].self, forKey: .bookIds)?.compactMap { Int($0) } ?? []
        bookNames = try container.decodeIfPresent([String].self, forKey: .bookNames) ?? []
        installmentGroupId = try container.decodeIfPresent(String.self, forKey: .installmentGroupId)
        installmentIndex = try container.decodeIfPresent(Int.self, forKey: .installmentIndex)
        installmentMonths = try container.decodeIfPresent(Int.self, forKey: .installmentMonths)
        originalAmount = try container.decodeIfPresent(Double.self, forKey: .originalAmount)
        discountAmount = try container.decodeIfPresent(Double.self, forKey: .discountAmount)
        premiumAmount = try container.decodeIfPresent(Double.self, forKey: .premiumAmount)
        paidByParticipantId = try container.decodeIfPresent(String.self, forKey: .paidByParticipantId)
        paidByParticipantName = try container.decodeIfPresent(String.self, forKey: .paidByParticipantName)
        splitParticipantIds = try container.decodeIfPresent([String].self, forKey: .splitParticipantIds)
        splitParticipantNames = try container.decodeIfPresent([String].self, forKey: .splitParticipantNames) ?? []
    }
}
