import Foundation
import SwiftUI

enum CategoryKind: String, Codable { case expense, income }

enum DemoData {
    static func defaultCategories() -> [LedgerCategory] {
        var nextID = 1
        func node(_ name: String, _ icon: String, _ color: String, _ flow: FlowType, _ parent: Int? = nil, _ level: Int = 0, _ children: [(String, String)] = []) -> LedgerCategory {
            let id = nextID; nextID += 1
            let childNodes = children.map { child in node(child.0, icon, color, flow, id, level + 1) }
            return LedgerCategory(id: id, name: name, flowType: flow, icon: icon, color: color, parentId: parent, level: level, children: childNodes)
        }
        let expense: [(String, String, String, [(String, String)])] = [
            ("餐饮", "fork.knife", "#EF6C5B", [("早餐", ""), ("午餐", ""), ("晚餐", ""), ("夜宵", ""), ("外卖", ""), ("咖啡茶饮", ""), ("零食水果", ""), ("聚餐", ""), ("食堂", "")]),
            ("交通出行", "car.fill", "#4F8EF7", [("公交地铁", ""), ("打车", ""), ("共享单车", ""), ("加油", ""), ("停车费", ""), ("高速路桥", ""), ("机票", ""), ("火车票", "")]),
            ("居住", "house.fill", "#68B984", [("房租", ""), ("水费", ""), ("电费", ""), ("燃气", ""), ("物业", ""), ("宽带", ""), ("手机话费", ""), ("家居维修", ""), ("清洁用品", "")]),
            ("购物", "bag.fill", "#F5A623", [("日用百货", ""), ("服饰鞋包", ""), ("数码电器", ""), ("美妆护肤", ""), ("母婴用品", ""), ("宠物用品", ""), ("家具家电", ""), ("礼品", "")]),
            ("医疗健康", "cross.case.fill", "#E85D75", [("门诊", ""), ("药品", ""), ("体检", ""), ("牙科", ""), ("运动健身", ""), ("保健", ""), ("保险", "")]),
            ("教育学习", "graduationcap.fill", "#8167D9", [("书籍", ""), ("课程", ""), ("培训", ""), ("考试报名", ""), ("学习工具", ""), ("会员订阅", "")]),
            ("休闲娱乐", "gamecontroller.fill", "#C16CE6", [("电影演出", ""), ("游戏", ""), ("旅行", ""), ("摄影", ""), ("兴趣爱好", ""), ("线上娱乐", ""), ("运动场馆", ""), ("景点门票", "")]),
            ("人情往来", "gift.fill", "#E977A6", [("红包", ""), ("礼金", ""), ("请客送礼", ""), ("孝敬父母", ""), ("朋友聚会", "")]),
            ("金融支出", "creditcard.fill", "#607D8B", [("信用卡还款", ""), ("利息", ""), ("手续费", ""), ("税费", ""), ("转账", "")]),
            ("其他支出", "ellipsis.circle.fill", "#8B95A1", [("罚款", ""), ("捐赠", ""), ("未分类", "")])
        ]
        let income: [(String, String, String, [(String, String)])] = [
            ("工资收入", "banknote.fill", "#3AAE6D", [("基本工资", ""), ("奖金", ""), ("补贴", ""), ("报销", "")]),
            ("经营收入", "storefront.fill", "#27A8A1", [("销售", ""), ("服务收入", ""), ("佣金", "")]),
            ("投资收入", "chart.line.uptrend.xyaxis", "#4F8EF7", [("理财收益", ""), ("股息", ""), ("基金收益", "")]),
            ("其他收入", "plus.circle.fill", "#7E8B9A", [("退款", ""), ("礼金红包", ""), ("二手出售", ""), ("兼职", "")])
        ]
        return expense.map { node($0.0, $0.1, $0.2, .expense, nil, 0, $0.3) } + income.map { node($0.0, $0.1, $0.2, .income, nil, 0, $0.3) }
    }

    static func defaultBooks() -> [LedgerBook] { [book(id: 1, name: "日常账本", icon: "book.fill", color: "#5B8DEF", pinned: true)] }
    static func defaultTransactions(categories: [LedgerCategory], books: [LedgerBook]) -> [LedgerTransaction] { [] }
    static func defaultBudgets(categories: [LedgerCategory], books: [LedgerBook]) -> [BudgetItem] { [] }

    static func extendedBooks(startingAt id: Int) -> [LedgerBook] {
        [book(id: id, name: "九月生活", icon: "calendar", color: "#8B5CF6"), book(id: id + 1, name: "旅行计划", icon: "airplane", color: "#F59E0B")]
    }
    static func extendedBudgets(categories: [LedgerCategory], startingAt id: Int) -> [BudgetItem] { [] }

    static func extendedTransactions(categories: [LedgerCategory], books: [LedgerBook], startingAt id: Int) -> [LedgerTransaction] {
        let leaves = categories.flatMap { $0.leafFlattened() }
        guard let defaultBook = books.first else { return [] }
        let titles = ["早餐", "午餐", "地铁出行", "超市采购", "咖啡", "电影票", "工资到账", "水电缴费", "打车", "水果"]
        let amounts: [Double] = [18, 32, 5, 86, 24, 58, 8500, 126, 22, 35]
        let calendar = Calendar.current
        return titles.enumerated().map { offset, title in
            let category = leaves[offset % leaves.count]
            let income = title == "工资到账"
            return LedgerTransaction(id: id + offset, title: title, amount: amounts[offset], kind: income ? .income : .expense, happenedAt: calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date(), note: "模拟数据", merchant: nil, paymentMethod: income ? "银行卡" : "微信", source: "manual", currency: "CNY", categoryId: category.id, categoryName: category.name, bookId: defaultBook.id, bookName: defaultBook.name, bookIds: [defaultBook.id], bookNames: [defaultBook.name], installmentGroupId: nil, installmentIndex: nil, installmentMonths: nil, installmentOriginalTotal: nil, originalAmount: nil, discountAmount: nil, premiumAmount: nil, paidByParticipantId: nil, paidByParticipantName: nil, splitParticipantIds: [], splitParticipantNames: [])
        }
    }

    private static func book(id: Int, name: String, icon: String, color: String, pinned: Bool = false) -> LedgerBook {
        LedgerBook(id: id, name: name, icon: icon, color: color, note: nil, startDate: nil, endDate: nil, budgetLimitAmount: nil, budgetStartDate: nil, budgetEndDate: nil, autoCollectEnabled: false, expenseAmount: 0, incomeAmount: 0, balance: 0, transactionCount: 0, participantNames: [], isPinned: pinned, autoCollectCategoryIds: [])
    }
}