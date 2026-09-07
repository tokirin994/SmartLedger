import Foundation
import SwiftUI

// MARK: - 枚举与默认账本分类数据
// 图67：分类枚举（支出类别 + 图标 + 颜色 + parentId + level）
enum CategoryKind: String, Codable {
    case expense
    case income
}

// 图67：默认分类（层级结构，含 parentId / level）
// 可见类别：餐饮、交通、居住、娱乐、购物、服饰、学习、人情往来、收入
// 字段：name / kind / icon / colorHex / parentId / level
struct DemoCategorySpec {
    let name: String
    let kind: CategoryKind
    let icon: String
    let colorHex: String
    let parentId: Int?
    let level: Int
}

// 图67：默认分类数据（以原图为准）
let defaultCategories: [DemoCategorySpec] = [
    // .init(name: "餐饮", kind: .expense, icon: "fork.knife", colorHex: "#F96B6B", parentId: nil, level: 0),
    // .init(name: "咖啡", kind: .expense, icon: "cup.and.saucer.fill", colorHex: "#A87B64", parentId: <餐饮>, level: 1),
    // .init(name: "交通", ...),
    // .init(name: "居住", ...),
    // .init(name: "娱乐", ...),
    // .init(name: "购物", ...),
    // .init(name: "服饰", ...),
    // .init(name: "学习", ...),
    // .init(name: "人情往来", ...),
    // .init(name: "收入", kind: .income, ...),
    // 以原图为准
]

// 图68：defaultBooks / defaultBudgets 函数（创建账本、预算）
func defaultBooks() -> [LedgerBook] {
    // 以原图为准
}

func defaultBudgets() -> [BudgetItem] {
    // 以原图为准
}

// 图68：分类查询（按 name / kind 查找 id）
func findCategoryId(name: String, kind: CategoryKind) -> Int? {
    // 以原图为准
}

// 图69：BudgetItem 默认数据 + defaultTransactions + LedgerTransaction 初始化
// 字段：amount / happenedAt / merchant / categoryId / bookIds / kind 等
func defaultTransactions(books: [LedgerBook], categories: [LedgerCategory]) -> [LedgerTransaction] {
    // 以原图为准
}

// 图70：演示交易数据（标题 + 金额 + 日期 + 颜色）
// 可见标题：
//   "MacBook 分期"
//   "Notion 订阅"
//   "杭州周末游"
//   "体检与看牙"
//   "春节回家"
// 字段：title / amount / kind / happenedAt / note / merchant / categoryId / bookIds / installmentMonths 等
// 以原图为准

// 图71：预算项 + 演示交易
// 可见标题：
//   "通勤交通"
//   "购物克制计划"
//   "工资到账"
//   "房租"
//   "滴滴出行"
//   "高铁票"
// 字段：limitAmount / period / startDate / spentAmount / usageRatio / kind / amount / day偏移 / 分类 / 来源
// 以原图为准

// 图72：.init(...) 交易数据
// 可见标题：
//   "京东买显示器支架"
//   "淘宝日用品"
//   "顺丰快递"
// kind: expense / income
// 字段：amount / day偏移 / category / source
// 下方：var results: [LedgerTransaction] = [] + for 循环 + results.append(LedgerTransaction(...))
func buildDemoTransactions(
    books: [LedgerBook],
    categories: [LedgerCategory]
) -> [LedgerTransaction] {
    var results: [LedgerTransaction] = []
    // for ... {
    //     results.append(.init(
    //         id: ..., title: "...", amount: ..., kind: .expense,
    //         happenedAt: Date().addingTimeInterval(-day * 86400),
    //         note: nil, merchant: "...", paymentMethod: "...",
    //         currency: "CNY", categoryId: <category>, bookIds: [<book>],
    //         installmentGroupId: nil, installmentIndex: nil, installmentMonths: nil,
    //         originalAmount: nil, discountAmount: nil, premiumAmount: nil,
    //         paidByParticipantId: nil, paidByParticipantName: nil,
    //         splitParticipantIds: nil, splitParticipantNames: nil
    //     ))
    // }
    // 以原图为准
    return results
}

// 图73：installmentMonths / phoneCategory / results.append(LedgerTransaction...)
// 可见标题："iPhone 分期" / "Apple Store" / currency: "CNY"
// 分期逻辑：installmentMonths / installmentGroupId / installmentIndex
// 以原图为准

// 图74：DemoTransactionSpec 结构体 + DemoDateOffset 枚举 + 日期计算
struct DemoTransactionSpec {
    // 以原图为准（title / amount / kind / day偏移 / category / source / installmentMonths 等）
}

enum DemoDateOffset {
    case daysAgo(Int)
    case monthsAgo(Int)
    // 以原图为准

    func resolve(relativeTo base: Date = Date()) -> Date {
        // 以原图为准（基于 base 计算日期）
    }
}

// 图75：resolve / category / leaf / tx 函数
// 涉及日期计算、LedgerCategory 与 LedgerTransaction 构造及参数赋值
func resolve(_ spec: DemoTransactionSpec,
             categories: [LedgerCategory],
             books: [LedgerBook]) -> LedgerTransaction {
    // 以原图为准
}

func category(_ name: String, in categories: [LedgerCategory]) -> Int? {
    // 以原图为准
}

func leaf(_ name: String, in categories: [LedgerCategory]) -> Int? {
    // 以原图为准
}

func tx(_ spec: DemoTransactionSpec,
        categoryId: Int?,
        bookIds: [Int]) -> LedgerTransaction {
    // 以原图为准
}
