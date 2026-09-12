import XCTest
@testable import SmartLedger

@MainActor
final class SmartLedgerCoreTests: XCTestCase {
    func testSelectableCategoriesOnlyContainLeafNodes() {
        let store = LedgerStore()
        store.categories = DemoData.defaultCategories()
        
        let expenseCategories = store.selectableCategories(for: .expense)
        XCTAssertFalse(expenseCategories.isEmpty)
        XCTAssertTrue(expenseCategories.allSatisfy { $0.isLeaf })
        XCTAssertFalse(expenseCategories.contains(where: { $0.name == "餐饮" }))
        XCTAssertTrue(expenseCategories.contains(where: { $0.name == "快餐 / 日常吃饭" }))
    }
    
    func testCreateInstallmentTransactionSplitsAcrossMonths() async {
        let store = LedgerStore()
        store.categories = DemoData.defaultCategories()
        store.books = DemoData.defaultBooks()
        store.transactions = []
        
        let leafCategory = store.selectableCategories(for: .expense).first(where: { $0.name == "租房 / 房租" })!
        
        var draft = TransactionDraft()
        draft.title = "MacBook Air"
        draft.amount = 3000
        draft.kind = .expense
        draft.categoryId = leafCategory.id
        draft.installmentMonths = 3
        draft.startMonth = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        
        await store.createTransaction(draft: draft)
        
        XCTAssertEqual(store.transactions.count, 3)
        
        let sorted = store.transactions.sorted { $0.installmentIndex ?? 0 < $1.installmentIndex ?? 0 }
        XCTAssertEqual(sorted.map { $0.installmentIndex }, [1, 2, 3])
        XCTAssertEqual(sorted.map { $0.installmentMonth }, [1, 3, 5])
        XCTAssertEqual(sorted.reduce(0) { $0 + $1.amount }, 3000, accuracy: 0.01)
        XCTAssertTrue(sorted.compactMap({ $0.installmentGroupId }).count == 3)
        
        let months = sorted.map { Calendar.current.component(.month, from: $0.happenedAt) }
        XCTAssertEqual(months, [1, 2, 3])
    }
    
    func testBudgetProgressCountMatchingRootCategoryTransactions() {
        let categories = DemoData.defaultCategories().flatMap { $0.flatten() }
        let budget = BudgetItem(
            id: 1,
            name: "餐饮预算",
            limitAmount: 1000,
            periodType: .monthly,
            year: 2026,
            month: 1,
            startDate: nil,
            endDate: nil,
            categoryId: categories.first(where: { $0.name == "餐饮" })!.id,
            categoryName: "餐饮",
            spentAmount: 0,
            usageRatio: 0
        )
        
        let janb = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 8))!
        let jank = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let jan8 = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        
        let transactions = [
            LedgerTransaction(id: 1, title: "午餐", amount: 30, kind: .expense, happenedAt: janb, note: nil, merchant: nil, paymentMethod: nil, source: "manual", currency: "CNY", categoryId: categories.first(where: { $0.name == "餐饮" })!.id, categoryName: "餐饮 / 日常吃饭", bookId: nil, bookmark: nil, installmentGroupId: nil, installmentIndex: nil, installmentMonths: nil, installmentOriginalTotal: nil, originalAmount: nil, discountAmount: nil, premiumAmount: nil, paidBy: nil, participantNames: nil, splitParticipantIds: nil, splitParticipantNames: nil),
            LedgerTransaction(id: 2, title: "奶茶", amount: 20, kind: .expense, happenedAt: jank, note: nil, merchant: nil, paymentMethod: nil, source: "manual", currency: "CNY", categoryId: categories.first(where: { $0.name == "餐饮 / 奶茶甜品" })!.id, categoryName: "餐饮 / 奶茶甜品", bookId: nil, bookmark: nil, installmentGroupId: nil, installmentIndex: nil, installmentMonths: nil, installmentOriginalTotal: nil, originalAmount: nil, discountAmount: nil, premiumAmount: nil, paidBy: nil, participantNames: nil, splitParticipantIds: nil, splitParticipantNames: nil),
            LedgerTransaction(id: 3, title: "打车", amount: 50, kind: .expense, happenedAt: jan8, note: nil, merchant: nil, paymentMethod: nil, source: "manual", currency: "CNY", categoryId: categories.first(where: { $0.name == "交通 / 打车" })!.id, categoryName: "交通 / 打车", bookId: nil, bookmark: nil, installmentGroupId: nil, installmentIndex: nil, installmentMonths: nil, installmentOriginalTotal: nil, originalAmount: nil, discountAmount: nil, premiumAmount: nil, paidBy: nil, participantNames: nil, splitParticipantIds: nil, splitParticipantNames: nil)
        ]
        
        let result = LocalAnalytics.computeBudgetProgress(transactions: transactions, categories: categories, budgets: [budget])
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].spentAmount, 50, accuracy: 0.01)
        XCTAssertEqual(result[0].usageRatio, 0.05, accuracy: 0.001)
    }
    
    func testReceiptParserParsesWeChatExpenseSnapshot() {
        let parser = ReceiptParser()
        let text = """
        微信支付
        付款成功
        收款方：瑞幸咖啡
        商品说明：生椰拿铁
        支付方式：零钱
        支付金额：¥24.00
        """
        
        let result = parser.parse(rawText: text)
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.amount ?? 0, 24.00, accuracy: 0.01)
        XCTAssertEqual(result.merchant, "瑞幸咖啡")
        XCTAssertEqual(result.categoryPath, ["餐饮", "奶茶甜品"])
        XCTAssertGreaterThan(result.confidence, 0.6)
    }
    
    func testReceiptParserParsesIncomeSnapshot() {
        let parser = ReceiptParser()
        let text = """
        转账成功
        收款方：张三
        收入金额：500.00
        备注：朋友转账
        """
        
        let result = parser.parse(rawText: text)
        XCTAssertEqual(result.kind, .income)
        XCTAssertEqual(result.amount ?? 0, 500.00, accuracy: 0.01)
        XCTAssertEqual(result.categoryPath, ["收入", "转账收入"])
    }
    
    func testReceiptParserParsesWeChatTransferDetailSnapshot() {
        let parser = ReceiptParser()
        let text = """
        转账
        20/3/1
        
        59
        x
        零钱明细
        扫二维码付款-给刘南海
        -4.50
        
        当前状态
        收款方备注
        支付方式
        转账时间
        转账单号
        支付成功
        零钱
        
        2026年09月04日 09:38:17
        1000107513012802401751990A1
        554
        58.00
        账单服务
        """
        
        let result = parser.parse(rawText: text)
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.amount ?? 0, 4.50, accuracy: 0.01)
        XCTAssertEqual(result.paymentMethod, "零钱")
        XCTAssertEqual(result.merchant, "刘南海")
        XCTAssertTrue(result.title?.contains("二维码付款") == true)
        XCTAssertTrue(result.details.contains(where: { $0.label == "收款方备注" && $0.value == "二维码收款" }))
        XCTAssertTrue(result.details.contains(where: { $0.label == "零钱" && $0.value == "58.00" }))
    }
    
    func testReceiptParserParsesAlipayDetailSnapshot() {
        let parser = ReceiptParser()
        let text = """
        花呗
        20/3/1
        
        关联记录
        支付时间
        付款方式
        账单详情
        
        mbaox
        -25.15
        支付成功
        2026-03-01 13:21:05
        花呗
        
        先用后付订单完成付款，已计入芝麻分
        明细
        交易详情
        支付提醒
        之前提醒3次
        """
        
        let result = parser.parse(rawText: text)
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.amount ?? 0, 25.15, accuracy: 0.01)
        XCTAssertEqual(result.paymentMethod, "花呗")
        XCTAssertEqual(result.merchant, "mbaox")
        XCTAssertTrue(result.title?.contains("花呗") == true)
        XCTAssertTrue(result.details.contains(where: { $0.label == "扣款说明" && $0.value.contains("芝麻分评估") }))
        XCTAssertEqual(result.categoryPath, ["购物", "日用百货"])
    }
    
    func testReceiptParserParsesAlipayListSnapshot() {
        let parser = ReceiptParser()
        let text = """
        2013x
        Q 搜索交易记录
        全部
        转账
        支出
        购物
        日用
        9月
        支出
        ¥24.15
        本月已省<0.00元>
        收入
        ¥0.00
        
        筛选
        少
        账单
        
        LEGO乐高 18653 1x3x2 反向弧形砖...
        其他
        09-01 13:21
        支出
        ¥15,616.62
        V6.52
        天猫
        力士植萃沐浴露白檀木持久留香...
        日用百货
        08-31 21:35
        -24.15
        收支分析
        必胜客-烤肉自助餐厅1人工作...-329.00
        日用百货
        08-30 19:57
        2026.6月保费缴费-银行卡安全险...
        -2.00
        保险
        08-30 11:59
        """
        
        let results = parser.parseMultiple(rawText: text)
        XCTAssertEqual(results.count, 4)
        XCTAssertTrue(results.contains(where: { ($0.title ?? "").contains("LEGO乐高") && abs($0.amount ?? 0) - 24.15 < 0.01 }))
        XCTAssertTrue(results.contains(where: { ($0.title ?? "").contains("力士植萃") && $0.merchant == "天猫" }))
        XCTAssertTrue(results.contains(where: { ($0.title ?? "").contains("烤肉") && $0.categoryPath == ["餐饮", "日用百货"] }))
        XCTAssertTrue(results.contains(where: { ($0.title ?? "").contains("保费缴费") && abs($0.amount ?? 0) - 2.00 < 0.01 }))
    }
}
