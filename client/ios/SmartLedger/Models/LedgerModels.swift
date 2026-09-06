import Foundation
import SwiftUI
import UIKit

enum FlowType: String, Codable, CaseIterable, Identifiable { case expense, income; var id: String { rawValue }
    var title: String { self == .expense ? "支出" : "收入" }
    var tint: Color { self == .expense ? .orange : .green }
}

struct LedgerCategory: Identifiable, Codable, Hashable {
    var id = UUID(); var name: String; var kind: FlowType; var icon: String; var colorHex: String; var parentID: UUID?
    var color: Color { Color(hex: colorHex) }
    var flowType: FlowType { kind }
    var parentId: UUID? { parentID }
    var level: Int { parentID == nil ? 0 : 1 }
    var children: [LedgerCategory] = []
}

struct LedgerTransaction: Identifiable, Codable, Hashable {
    var id = UUID(); var title: String; var amount: Double; var kind: FlowType; var happenedAt = Date()
    var note = ""; var merchant = ""; var paymentMethod = "微信支付"; var source = "manual"
    var currency = "CNY"; var categoryID: UUID?; var categoryName = ""; var bookID: UUID?; var bookIDs: [UUID] = []; var bookName = ""; var bookNames: [String] = []; var installmentGroupID: UUID?; var installmentIndex = 1; var installmentMonths = 1; var installmentOriginalTotal: Double?
    var originalAmount: Double?; var discountAmount: Double?; var premiumAmount: Double?
    var paidBy = ""; var paidByParticipantID: UUID?; var paidByParticipantName = ""; var splitParticipantIDs: [UUID] = []; var splitParticipants: [String] = []; var splitParticipantNames: [String] = []
}

struct LedgerBook: Identifiable, Codable, Hashable {
    var id = UUID(); var name: String; var icon = "book.closed.fill"; var colorHex = "3B82F6"
    var startDate = Date(); var endDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
    var autoCollectEnabled = false; var autoCollectCategoryIDs: [UUID] = []; var budgetLimit: Double = 0
    var participants: [String] = []; var isPinned = false
    var color: Color { Color(hex: colorHex) }
    var budgetLimitAmount: Double { budgetLimit }; var budgetStartDate: Date { startDate }; var budgetEndDate: Date { endDate }
    var participantNames: [String] { participants }; var splitEnabled: Bool { participants.count > 1 }; var budgetEnabled: Bool { budgetLimit > 0 }
}

enum BudgetPeriod: String, Codable, CaseIterable, Identifiable { case monthly, range; var id: String { rawValue }; var title: String { self == .monthly ? "每月" : "区间" } }
struct Budget: Identifiable, Codable, Hashable {
    var id = UUID(); var name: String; var limitAmount: Double; var period: BudgetPeriod = .monthly
    var year = Calendar.current.component(.year, from: Date()); var month = Calendar.current.component(.month, from: Date()); var startDate = Date(); var endDate = Date(); var categoryID: UUID?; var categoryName = ""; var spentAmount = 0.0; var usageRatio = 0.0
    var periodType: BudgetPeriod { period }
}

struct OCRImportResult: Identifiable, Codable, Hashable {
    var id = UUID(); var amount: Double; var kind: FlowType; var merchant: String; var title: String
    var paymentMethod: String; var happenedAt: Date; var categoryKeyword = ""; var categoryPath: [String] = []; var details: [OCRDetail] = []; var confidence: Double
    var rawLines: [String] = []; var originalAmount: Double?; var discountAmount: Double?
}

struct OCRDetail: Codable, Hashable, Identifiable { var id = UUID(); var label: String; var value: String }

struct AppleAccountProfile: Codable, Hashable {
    var userIdentifier: String; var fullName: String; var email: String; var authorizedAt: Date
}

enum CloudSyncState: String { case disabled, idle, syncing, success, unavailable, conflict, failed
    var title: String { ["disabled":"未启用", "idle":"等待同步", "syncing":"同步中", "success":"已同步", "unavailable":"iCloud 不可用", "conflict":"需要选择版本", "failed":"同步失败"][rawValue]! }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable { case system, light, dark; var id: String { rawValue }; var title: String { ["system":"跟随系统", "light":"白天模式", "dark":"夜间模式"][rawValue]! } }

struct PersistedLedgerSnapshot: Codable { var categories: [LedgerCategory]; var books: [LedgerBook]; var transactions: [LedgerTransaction]; var budgets: [Budget]; var nextIDs: [String:Int] = [:]; var updatedAt: Date }

extension Color { init(hex: String) { let v = UInt64(hex, radix: 16) ?? 0; self.init(red: Double((v >> 16) & 255)/255, green: Double((v >> 8) & 255)/255, blue: Double(v & 255)/255) } }
extension Color { var hexString: String { let value = UIColor(self); var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0; value.getRed(&r, green: &g, blue: &b, alpha: &a); return String(format: "%02lX%02lX%02lX", lroundf(Float(r * 255)), lroundf(Float(g * 255)), lroundf(Float(b * 255))) } }
extension Double { var currency: String { formatted(.currency(code: "CNY").precision(.fractionLength(2))) } }
