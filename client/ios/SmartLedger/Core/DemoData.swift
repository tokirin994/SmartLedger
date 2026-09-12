import Foundation
import SwiftUI

// MARK: - 分类枚与演示数据入口
enum CategoryKind: String, Codable {
    case expense
    case income
}

// 默认演示数据：分类树、默认账本；扩展演示数据为空
enum DemoData {
    static func defaultCategories() -> [LedgerCategory] {
        let expenseSpecs: [(String, String, String)] = [
            ("餐饮", "fork.knife", "#F96B6B"),
            ("交通", "car.fill", "#5B8DEF"),
            ("居住", "house.fill", "#7BC96F"),
            ("娱乐", "gamecontroller.fill", "#B983E5"),
            ("购物", "bag.fill", "#F5A623"),
            ("学习", "book.fill", "#4FB6BE"),
            ("人情往来", "gift.fill", "#E86FB1")
        ]
        var id = 1
        let expense = expenseSpecs.map { spec in
            let category = LedgerCategory(
                id: id,
                name: spec.0,
                flowType: .expense,
                icon: spec.1,
                color: spec.2,
                parentId: nil,
                level: 0,
                children: []
            )
            id += 1
            return category
        }
        let income = LedgerCategory(
            id: id,
            name: "收入",
            flowType: .income,
            icon: "yensign.circle.fill",
            color: "#67C23A",
            parentId: nil,
            level: 0,
            children: []
        )
        return expense + [income]
    }

    static func defaultBooks() -> [LedgerBook] {
        [
            LedgerBook(
                id: 1,
                name: "日常账本",
                icon: "book.fill",
                color: "#5B8DEF",
                note: nil,
                startDate: nil,
                endDate: nil,
                budgetLimitAmount: nil,
                budgetStartDate: nil,
                budgetEndDate: nil,
                autoCollectEnabled: false,
                expenseAmount: 0,
                incomeAmount: 0,
                balance: 0,
                transactionCount: 0,
                participantNames: [],
                isPinned: false,
                autoCollectCategoryIds: []
            )
        ]
    }

    static func defaultTransactions(categories: [LedgerCategory], books: [LedgerBook]) -> [LedgerTransaction] {
        []
    }

    static func defaultBudgets(categories: [LedgerCategory], books: [LedgerBook]) -> [BudgetItem] {
        []
    }

    static func extendedBooks(startingAt id: Int) -> [LedgerBook] {
        []
    }

    static func extendedBudgets(categories: [LedgerCategory], startingAt id: Int) -> [BudgetItem] {
        []
    }

    static func extendedTransactions(categories: [LedgerCategory], books: [LedgerBook], startingAt id: Int) -> [LedgerTransaction] {
        []
    }
}
