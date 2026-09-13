import Foundation
import SwiftUI

enum CategoryKind: String, Codable { case expense, income }

enum DemoData {
    static func defaultCategories() -> [LedgerCategory] {
        var nextID = 1
        func node(_ name: String, _ icon: String, _ color: String, _ flow: FlowType, _ parent: Int? = nil, _ level: Int = 0, _ children: [(String, String)] = []) -> LedgerCategory {
            let id = nextID; nextID += 1
            let childNodes = children.map { child in
                node(child.0, child.1.isEmpty ? DemoData.categoryIcon(for: child.0, fallback: icon) : child.1, color, flow, id, level + 1)
            }
            return LedgerCategory(id: id, name: name, flowType: flow, icon: icon, color: color, parentId: parent, level: level, children: childNodes)
        }
        let expense: [(String, String, String, [(String, String)])] = [
            ("餐饮", "fork.knife", "#EF6C5B", [("早餐", ""), ("午餐", ""), ("晚餐", ""), ("夜宵", ""), ("外卖", ""), ("咖啡茶饮", ""), ("零食水果", ""), ("聚餐", ""), ("食堂", ""), ("买菜食材", ""), ("烘焙甜品", ""), ("酒水饮料", ""), ("自助餐", ""), ("工作餐", ""), ("奶茶果饮", ""), ("日常吃饭", ""), ("奶茶咖啡", ""), ("吃好的", ""), ("水果零食", ""), ("买菜做饭", ""), ("其他餐饮", "")]),
            ("交通出行", "car.fill", "#4F8EF7", [("公交地铁", ""), ("打车", ""), ("网约车", ""), ("共享单车", ""), ("加油", ""), ("充电", ""), ("停车费", ""), ("高速路桥", ""), ("车辆保养", ""), ("洗车", ""), ("违章罚款", ""), ("代驾", ""), ("租车", ""), ("机票", ""), ("火车票", ""), ("船票", ""), ("地铁公交", ""), ("加油停车", ""), ("火车机票", "")]),
            ("居住", "house.fill", "#68B984", [("房租", ""), ("水费", ""), ("电费", ""), ("燃气", ""), ("物业", ""), ("宽带", ""), ("手机话费", ""), ("家居维修", ""), ("清洁用品", ""), ("搬家", ""), ("取暖", ""), ("房屋保险", ""), ("家政服务", ""), ("装修", ""), ("绿植花卉", ""), ("水电网", ""), ("家居用品", ""), ("家电维修", "")]),
            ("购物", "bag.fill", "#F5A623", [("日用百货", ""), ("生鲜食品", ""), ("服饰鞋包", ""), ("数码电器", ""), ("美妆护肤", ""), ("母婴用品", ""), ("宠物用品", ""), ("家具家电", ""), ("办公用品", ""), ("首饰配饰", ""), ("图书杂志", ""), ("快递运费", ""), ("礼品", ""), ("日用品", ""), ("服饰", ""), ("数码", ""), ("家电家具", "")]),
            ("医疗健康", "cross.case.fill", "#E85D75", [("门诊", ""), ("住院", ""), ("药品", ""), ("体检", ""), ("牙科", ""), ("眼科", ""), ("疫苗", ""), ("心理咨询", ""), ("运动健身", ""), ("保健", ""), ("医疗器械", ""), ("保险", "")]),
            ("教育学习", "graduationcap.fill", "#8167D9", [("书籍", ""), ("文具", ""), ("课程", ""), ("培训", ""), ("学费", ""), ("考试报名", ""), ("语言学习", ""), ("学习工具", ""), ("云服务", ""), ("软件订阅", ""), ("会员订阅", "")]),
            ("休闲娱乐", "gamecontroller.fill", "#C16CE6", [("电影演出", ""), ("游戏", ""), ("KTV", ""), ("旅行", ""), ("酒店住宿", ""), ("摄影", ""), ("兴趣爱好", ""), ("线上娱乐", ""), ("运动场馆", ""), ("景点门票", ""), ("乐器玩具", ""), ("宠物娱乐", ""), ("休闲玩乐", ""), ("运动健身", "")]),
            ("人情往来", "gift.fill", "#E977A6", [("红包", ""), ("礼金", ""), ("婚礼随礼", ""), ("请客送礼", ""), ("孝敬父母", ""), ("朋友聚会", ""), ("探望慰问", ""), ("慈善捐赠", ""), ("礼物", ""), ("请客", "")]),
            ("金融支出", "creditcard.fill", "#607D8B", [("信用卡还款", ""), ("贷款还款", ""), ("利息", ""), ("手续费", ""), ("税费", ""), ("转账", ""), ("汇率损失", ""), ("投资亏损", "")]),
            ("其他支出", "ellipsis.circle.fill", "#8B95A1", [("罚款", ""), ("捐赠", ""), ("订阅服务", ""), ("未分类", "")])
        ]
        let income: [(String, String, String, [(String, String)])] = [
            ("工资收入", "banknote.fill", "#3AAE6D", [("基本工资", ""), ("奖金", ""), ("补贴", ""), ("报销", ""), ("加班费", ""), ("年终奖", ""), ("工资", ""), ("退款入账", ""), ("转账收入", "")]),
            ("经营收入", "storefront.fill", "#27A8A1", [("销售", ""), ("服务收入", ""), ("佣金", ""), ("稿费", ""), ("版权收入", "")]),
            ("投资收入", "chart.line.uptrend.xyaxis", "#4F8EF7", [("理财收益", ""), ("股息", ""), ("基金收益", ""), ("股票收益", ""), ("利息收入", "")]),
            ("其他收入", "plus.circle.fill", "#7E8B9A", [("退款", ""), ("礼金红包", ""), ("二手出售", ""), ("兼职", ""), ("租金收入", ""), ("意外所得", "")])
        ]
        return expense.map { node($0.0, $0.1, $0.2, .expense, nil, 0, $0.3) } + income.map { node($0.0, $0.1, $0.2, .income, nil, 0, $0.3) }
    }

    static let supplementalDefaultSubcategories: [String: [String]] = [
        "餐饮": ["买菜食材", "烘焙甜品", "酒水饮料", "自助餐", "工作餐", "奶茶果饮", "其他餐饮", "日常吃饭", "奶茶咖啡", "吃好的", "水果零食", "买菜做饭"],
        "交通出行": ["网约车", "充电", "车辆保养", "洗车", "违章罚款", "代驾", "租车", "船票", "地铁公交", "加油停车", "火车机票"],
        "居住": ["搬家", "取暖", "房屋保险", "家政服务", "装修", "绿植花卉", "水电网", "家居用品", "家电维修"],
        "购物": ["生鲜食品", "办公用品", "首饰配饰", "图书杂志", "快递运费", "日用品", "服饰", "数码", "家电家具"],
        "医疗健康": ["住院", "眼科", "疫苗", "心理咨询", "医疗器械"],
        "教育学习": ["文具", "学费", "语言学习", "云服务", "软件订阅"],
        "休闲娱乐": ["KTV", "酒店住宿", "乐器玩具", "宠物娱乐", "休闲玩乐", "运动健身"],
        "人情往来": ["婚礼随礼", "探望慰问", "慈善捐赠", "礼物", "请客"],
        "金融支出": ["贷款还款", "汇率损失", "投资亏损"],
        "其他支出": ["订阅服务"],
        "工资收入": ["加班费", "年终奖", "工资", "退款入账", "转账收入"],
        "经营收入": ["稿费", "版权收入"],
        "投资收入": ["股票收益", "利息收入"],
        "其他收入": ["租金收入", "意外所得"]
    ]

    struct SupplementalCategoryRoot {
        let name: String
        let flowType: FlowType
        let icon: String
        let color: String
        let children: [(String, String, String)]
    }

    /// Exact common roots that are absent from older catalog versions. They
    /// coexist with the legacy broader roots (such as “交通出行”) so existing
    /// user data is never renamed or reassigned.
    static let supplementalDefaultRoots: [SupplementalCategoryRoot] = [
        SupplementalCategoryRoot(name: "交通", flowType: .expense, icon: "car", color: "#3B82F6", children: [("打车", "car.side", "#60A5FA"), ("地铁公交", "tram", "#93C5FD"), ("加油停车", "fuelpump", "#BFDBFE"), ("火车机票", "airplane.departure", "#DBEAFE")]),
        SupplementalCategoryRoot(name: "娱乐", flowType: .expense, icon: "gamecontroller", color: "#EC4899", children: [("电影演出", "popcorn", "#F472B6"), ("游戏", "gamecontroller.fill", "#F9A8D4"), ("旅行", "airplane", "#FBCFE8"), ("休闲玩乐", "party.popper", "#F9A8D4"), ("运动健身", "figure.run", "#F9A8D4")]),
        SupplementalCategoryRoot(name: "学习", flowType: .expense, icon: "book", color: "#6366F1", children: [("书籍资料", "books.vertical", "#818CF8"), ("课程培训", "graduationcap", "#A5B4FC"), ("软件订阅", "rectangle.and.pencil.and.ellipsis", "#C7D2FE")]),
        SupplementalCategoryRoot(name: "收入", flowType: .income, icon: "banknote", color: "#22C55E", children: [("工资", "wallet.pass", "#4ADE80"), ("奖金", "star.square", "#86EFAC"), ("退款入账", "arrow.uturn.backward.circle", "#86EFAC"), ("转账收入", "arrow.down.left.circle", "#DCFCE7")])
    ]

    static func categoryIcon(for name: String, fallback: String) -> String {
        let icons: [String: String] = [
            "早餐": "sunrise.fill", "午餐": "fork.knife", "晚餐": "moon.fill", "夜宵": "moon.stars.fill", "外卖": "takeoutbag.and.cup.and.straw", "咖啡茶饮": "cup.and.saucer.fill", "奶茶果饮": "cup.and.saucer", "奶茶咖啡": "cup.and.saucer", "零食水果": "carrot.fill", "水果零食": "carrot", "买菜食材": "basket.fill", "买菜做饭": "basket", "吃好的": "birthday.cake.fill",
            "打车": "car.side.fill", "网约车": "car.side", "公交地铁": "tram.fill", "地铁公交": "tram", "加油": "fuelpump.fill", "加油停车": "fuelpump", "停车费": "parkingsign.circle.fill", "火车票": "train.side.front.car", "机票": "airplane", "火车机票": "airplane.departure", "共享单车": "bicycle", "代驾": "steeringwheel", "车辆保养": "wrench.and.screwdriver.fill",
            "房租": "building.2.fill", "水电网": "bolt.fill", "水费": "drop.fill", "电费": "bolt.fill", "宽带": "wifi", "家居用品": "bed.double.fill", "家电维修": "wrench.and.screwdriver", "家具家电": "sofa.fill", "装修": "hammer.fill",
            "日用品": "cart.fill", "日用百货": "cart.fill", "服饰": "tshirt.fill", "服饰鞋包": "tshirt", "数码": "iphone", "数码电器": "iphone", "快递运费": "shippingbox.fill", "美妆护肤": "face.smiling", "宠物用品": "pawprint.fill",
            "电影演出": "popcorn.fill", "游戏": "gamecontroller.fill", "旅行": "airplane", "休闲玩乐": "party.popper.fill", "运动健身": "figure.run", "KTV": "music.mic", "景点门票": "ticket.fill",
            "书籍": "books.vertical.fill", "书籍资料": "books.vertical", "课程": "graduationcap.fill", "课程培训": "graduationcap", "软件订阅": "rectangle.and.pencil.and.ellipsis", "红包": "envelope.open.fill", "礼物": "gift.fill", "请客": "person.2.fill",
            "基本工资": "wallet.pass.fill", "工资": "wallet.pass", "奖金": "star.square.fill", "退款入账": "arrow.uturn.backward.circle.fill", "转账收入": "arrow.down.left.circle.fill", "报销": "doc.text.fill"
        ]
        return icons[name] ?? fallback
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
