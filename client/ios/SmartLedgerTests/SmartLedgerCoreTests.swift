import XCTest
import UIKit
@testable import SmartLedger

final class SmartLedgerCoreTests: XCTestCase {
    func testDateWindowsTouchingAtBoundaryDoNotOverlap() {
        let boundary = Date(timeIntervalSince1970: 1_800_000_000)
        let previousMonth = DateWindow(start: boundary.addingTimeInterval(-30 * 86_400), end: boundary)
        let currentMonth = DateWindow(start: boundary, end: boundary.addingTimeInterval(31 * 86_400))

        XCTAssertFalse(LocalAnalytics.dateWindowsOverlap(previousMonth, currentMonth))
        XCTAssertTrue(LocalAnalytics.dateWindowsOverlap(
            DateWindow(start: boundary.addingTimeInterval(-1), end: boundary.addingTimeInterval(1)),
            currentMonth
        ))
    }

    func testMonthlyBudgetTemplateExpandsIntoYearMonthInstances() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
        let template = BudgetItem(
            id: 7, name: "月预算", limitAmount: 8000, periodType: "monthly", year: 2026,
            month: nil, startDate: start, endDate: nil, categoryId: nil, categoryName: nil,
            spentAmount: 0, usageRatio: 0
        )

        let periods = LocalAnalytics.monthlyBudgetPeriods(
            budgets: [template], transactions: [], categories: [], year: 2026, now: now
        )

        XCTAssertEqual(periods.map(\.month), [9, 10])
        XCTAssertEqual(periods.map(\.limitAmount), [8000, 8000])
        XCTAssertTrue(periods.allSatisfy { $0.id < 0 })
        XCTAssertEqual(periods.map(\.parentBudgetId), [nil, nil])
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
        XCTAssertEqual(result.categoryPath, ["餐饮", "奶茶咖啡"])
        XCTAssertGreaterThan(result.confidence ?? 0, 0.6)
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

    func testReceiptParserParsesGenericReceiptWithoutCurrencyPrefix() {
        let parser = ReceiptParser()
        let text = """
        账单
        北京都市味蕾餐饮管理有限公司
        −20.20
        原价    ¥21.00
        优惠    摇优惠·银行卡多笔立减优惠¥0.80
        当前状态    支付成功
        支付时间    2026年9月24日 18:00:32
        商品    精品快餐
        商户全称    北京都市味蕾餐饮管理有限公司
        支付方式    中国银行信用卡(5189)
        交易单号    4200003157202609243253765752
        """
        let result = parser.parse(rawText: text)
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.amount ?? 0, 20.20, accuracy: 0.01)
        XCTAssertEqual(result.title, "精品快餐")
        XCTAssertEqual(result.merchant, "北京都市味蕾餐饮管理有限公司")
        XCTAssertEqual(result.originalAmount ?? 0, 21.00, accuracy: 0.01)
        XCTAssertEqual(result.discountAmount ?? 0, 0.80, accuracy: 0.01)
        XCTAssertEqual(result.categoryPath, ["餐饮", "日常吃饭", "晚餐"])
        XCTAssertNotNil(result.happenedAt)
    }

    func testReceiptParserMergesAndSumsMultipleDiscountLines() {
        let parser = ReceiptParser()
        let text = """
        交易详情
        -34.06
        美团
        原价
        ¥35.50
        优惠    信用卡至高减10元优惠¥0.24
        摇优惠·银行卡多笔立减优惠¥1.20
        当前状态
        支付成功
        支付时间
        2026年09月25日 19:04:14
        商品
        村上一屋·鳗鱼饭·寿司·刺身·烧鸟(望京麒麟社店)-美团App-26092511200700001307650101860073
        收单机构
        北京钱包宝支付技术有限公司
        支付方式
        中国银行信用卡(5189)
        """

        let result = parser.parse(rawText: text)
        XCTAssertEqual(result.amount ?? 0, 34.06, accuracy: 0.01)
        XCTAssertEqual(result.originalAmount ?? 0, 35.50, accuracy: 0.01)
        XCTAssertEqual(result.discountAmount ?? 0, 1.44, accuracy: 0.01)
        XCTAssertEqual(result.title, "村上一屋·鳗鱼饭·寿司·刺身·烧鸟(望京麒麟社店)")
        XCTAssertTrue(result.details?.contains { $0.label == "优惠" && $0.value.contains("信用卡至高") && $0.value.contains("摇优惠") } == true)
    }

    func testReceiptParserParsesWeChatTransferDetailSnapshot() {
        let parser = ReceiptParser()
        let text = """
        转账
        零钱明细
        扫二维码付款-给刘南海
        -4.50
        当前状态
        收款方备注
        支付方式
        转账时间
        支付成功
        二维码收款
        零钱
        2026年09月04日 09:38:17
        58.00
        账单服务
        """
        let result = parser.parse(rawText: text)
        let details = result.details ?? []
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.amount ?? 0, 4.50, accuracy: 0.01)
        XCTAssertEqual(result.paymentMethod, "零钱")
        XCTAssertEqual(result.merchant, "刘南海")
        XCTAssertTrue(result.title?.contains("二维码付款") == true)
        XCTAssertTrue(details.contains { $0.label == "收款方备注" && $0.value == "二维码收款" })
        XCTAssertTrue(details.contains { $0.label == "零钱余额" && $0.value == "58.00" })
    }

    func testReceiptParserKeepsWeChatOutgoingQRCodeTransferAsExpense() {
        let text = """
        微信支付账单详情
        扫二维码付款-给刘海龙
        -6.00
        当前状态
        支付成功
        收款方全称
        刘海龙
        付款方式
        中国银行储蓄卡(2602)
        转账时间
        2026年10月8日 09:46:47
        转账单号
        10001073012026100801089946833620
        收款方服务
        收款方名片
        发起群收款
        """

        let result = ReceiptParser().parse(rawText: text)
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.amount ?? 0, 6, accuracy: 0.01)
    }

    func testReceiptParserUsesSignedAmountForWeChatQRCodePaymentScreenshot() {
        // OCR text captured from the user's screenshot. “收款方备注 / 二维码收款”
        // is recipient metadata; the -4.50 amount and QR-payment title mean expense.
        let text = """
        11:53    5G    67
        账单
        扫二维码付款-给刘海龙
        -4.50
        当前状态    支付成功
        收款方备注    二维码收款
        支付方式    中国银行储蓄卡（2602）
        转账时间    2026年10月9日    09:47:03
        转账单号    100010730120261009011452546665
        52
        账单服务
        收款方服务
        收款方名片
        本服务由财付通提供
        """

        let result = ReceiptParser().parse(rawText: text)
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.amount ?? 0, 4.50, accuracy: 0.01)
        // The title heuristic is orthogonal; this regression specifically guards direction.
    }

    func testReceiptParserKeepsWeChatTransferInAsIncome() {
        let incoming = ReceiptParser().parse(rawText: """
        微信支付
        零钱明细
        转入
        8.00
        转账时间
        2026年10月8日 10:10:00
        付款方
        张三
        """)
        XCTAssertEqual(incoming.kind, .income)
    }

    func testReceiptParserTreatsWeChatTransferOutAsExpenseEvenWhenOCRLosesMinusSign() {
        let text = """
        微信支付
        零钱明细
        转出
        6.00
        当前状态
        转账成功
        收款方
        刘海龙
        转账时间
        2026年10月8日 09:46:47
        转账单号
        10001073012026100801089946833620
        """

        let result = ReceiptParser().parse(rawText: text)
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.amount ?? 0, 6, accuracy: 0.01)
    }

    func testReceiptParserDoesNotTreatWeChatTransferOutListRowAsIncomeBecauseOfCounterpartyLabel() {
        let items = ReceiptParser().parseMultiple(rawText: """
        微信流水
        2026年10月
        转出给刘海龙
        6.00
        10-08 09:46
        收款方
        刘海龙
        """)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.kind, .expense)
    }

    func testReceiptParserRecognizesMeituanEnterpriseMealOrderAndTimePreset() {
        let text = """
        消费记录详情
        已支付
        ¥20.00
        【开票信息】该订单为企业订单，发票由美团统一收取
        订单时间
        2026-10-08 17:57:55
        订单编号
        2108134790212505662
        消费商家
        云南味道
        业务场景
        工作餐
        """

        let result = ReceiptParser().parse(rawText: text)
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.amount ?? 0, 20, accuracy: 0.01)
        XCTAssertEqual(result.title, "云南味道")
        XCTAssertEqual(result.merchant, "云南味道")
        XCTAssertEqual(result.paymentMethod, "公司补贴")
        XCTAssertEqual(result.presetKey, "meituan_enterprise_meal")
        XCTAssertEqual(result.categoryPath, ["餐饮", "日常吃饭", "晚餐"])
        XCTAssertNotNil(result.happenedAt)
        let draft = TransactionDraft(parsed: result)
        XCTAssertEqual(draft.paymentMethod, "公司补贴")
        XCTAssertTrue(draft.offsetEnabled)
        XCTAssertEqual(draft.offsetRatio, 100)
    }

    func testMeituanEnterpriseMealPrefersSubsidyOffsetCategory() {
        let reimbursement = LedgerCategory(id: 101, name: "报销", flowType: .income, icon: nil, color: nil, parentId: nil, level: 0, children: [])
        let subsidy = LedgerCategory(id: 102, name: "公司补贴", flowType: .income, icon: nil, color: nil, parentId: nil, level: 0, children: [])
        let refund = LedgerCategory(id: 103, name: "退款", flowType: .income, icon: nil, color: nil, parentId: nil, level: 0, children: [])
        let categories = [reimbursement, subsidy, refund]

        XCTAssertEqual(ocrOffsetIncomeCategoryID(in: categories, presetKey: "meituan_enterprise_meal"), subsidy.id)
        XCTAssertEqual(ocrOffsetIncomeCategoryID(in: categories), reimbursement.id)
    }

    func testReceiptParserMapsMeituanEnterpriseMealToLunchFromOrderTime() {
        let text = """
        消费记录详情
        已支付
        ¥21.00
        订单时间 2026-09-28 11:51:48
        订单编号 2104418774732197976
        消费商家 手工虾滑（望京科创大厦店）
        业务场景 工作餐
        """

        let result = ReceiptParser().parse(rawText: text)
        XCTAssertEqual(result.title, "手工虾滑（望京科创大厦店）")
        XCTAssertEqual(result.categoryPath, ["餐饮", "日常吃饭", "午餐"])
    }

    func testReceiptParserParsesAlipayListSnapshot() {
        let parser = ReceiptParser()
        let text = """
        账单
        2026年9月
        LEGO乐高 18653 1x3x2 反向弧形砖...
        其他
        09-01 13:21
        -24.15
        天猫
        力士植萃沐浴露白檀木持久留香...
        日用百货
        08-31 21:35
        -105.80
        必胜客-烤肉自助餐厅1人工作...-329.00
        餐饮美食
        08-30 19:57
        2026.6月保费缴费-银行卡安全险...
        -2.00
        保险
        08-30 11:59
        """
        let results = parser.parseMultiple(rawText: text)
        XCTAssertGreaterThanOrEqual(results.count, 3)
        XCTAssertTrue(results.contains { ($0.title ?? "").contains("LEGO乐高") && abs($0.amount ?? 0) - 24.15 < 0.01 })
        XCTAssertTrue(results.contains { ($0.title ?? "").contains("力士植萃") })
        XCTAssertTrue(results.allSatisfy { $0.happenedAt != nil })
    }

    func testReceiptParserParsesAlipayCompactBillDetailTitleAndSignedAmount() {
        let parser = ReceiptParser()
        let text = """
        11:55 1    :. 5G €35
        账单详情
        早阳包子
        -6.00
        交易成功
        支付时间
        2026-09-29 09:50:17
        付款方式
        花呗＞
        商品说明
        收钱码收款
        支付奖励
        立即领取2积分
        收款方全称
        **龙（个人）
        更多、
        """

        let result = parser.parse(rawText: text)
        XCTAssertEqual(result.amount ?? 0, 6.00, accuracy: 0.01)
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.title, "早阳包子")
        XCTAssertEqual(result.merchant, "**龙（个人）")
        XCTAssertEqual(result.paymentMethod, "花呗")
        XCTAssertEqual(Calendar.current.component(.hour, from: result.happenedAt ?? .distantPast), 9)
        XCTAssertEqual(Calendar.current.component(.minute, from: result.happenedAt ?? .distantPast), 50)
    }

    func testReceiptParserExtractsAlipayPaymentBenefitDiscountAndMapsMealCategory() {
        let parser = ReceiptParser()
        let text = """
        23:42 90%
        账单详情
        早阳包子
        -5.88
        交易成功
        订单金额
        6.00
        支付遇财神
        -0.12
        支付时间
        2026-09-24 09:41:04
        付款方式
        花呗
        商品说明
        收钱码收款
        账单分类
        餐饮美食
        """

        let result = parser.parse(rawText: text)
        XCTAssertEqual(result.amount ?? 0, 5.88, accuracy: 0.01)
        XCTAssertEqual(result.originalAmount ?? 0, 6.00, accuracy: 0.01)
        XCTAssertEqual(result.discountAmount ?? 0, 0.12, accuracy: 0.01)
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.title, "早阳包子")
        XCTAssertEqual(result.paymentMethod, "花呗")
        XCTAssertEqual(result.categoryPath, ["餐饮", "日常吃饭", "早餐"])
        XCTAssertEqual(Calendar.current.component(.hour, from: result.happenedAt ?? .distantPast), 9)
        XCTAssertEqual(Calendar.current.component(.minute, from: result.happenedAt ?? .distantPast), 41)
    }

    func testReceiptParserKeepsAlipayNegativePaymentRowsAsExpenses() {
        let parser = ReceiptParser()
        // Vision OCR text from the supplied Alipay bill-list screenshot. In
        // Alipay, “收钱码收款” can still be an outgoing payment; the signed
        // amount, not that ambiguous word, determines its direction.
        let text = """
        搜索交易记录 搜索 •••
        全部 支出 转账 退款 订单 筛选
        9月
        支出 ¥6,563.33 收入 ¥0.00
        收钱码收款-给早阳包子 -5.88
        餐饮美食
        今天 09:41
        收钱码收款-给早阳包子 -4.34
        餐饮美食
        昨天 09:42
        收钱码收款-给早阳包子 -5.84
        餐饮美食
        09-22 09:48
        扫收钱码付款-给瑞豹自行车地⋯•-2,998.92
        爱车养车
        09-19 14:24
        扫收钱码付款-给瑞豹自行车地⋯•-2,000.00
        爱车养车
        09-18 22:36
        """

        let results = parser.parseMultiple(rawText: text)
        XCTAssertEqual(results.count, 5)
        XCTAssertTrue(results.allSatisfy { $0.kind == .expense })
        XCTAssertEqual(results.map { $0.amount ?? 0 }, [5.88, 4.34, 5.84, 2998.92, 2000.00])
        XCTAssertTrue(results.allSatisfy { $0.happenedAt != nil })
        XCTAssertTrue(results[0].title?.contains("早阳包子") == true)
    }

    func testCategoryTreeBuilderMovesRootsAndNestedSiblings() {
        let siblingA = LedgerCategory(id: 1, name: "A", flowType: .expense, icon: nil, color: nil, parentId: nil, level: 0, children: [], sortOrder: 0)
        let income = LedgerCategory(id: 9, name: "收入", flowType: .income, icon: nil, color: nil, parentId: nil, level: 0, children: [], sortOrder: 1)
        let siblingB = LedgerCategory(id: 2, name: "B", flowType: .expense, icon: nil, color: nil, parentId: nil, level: 0, children: [], sortOrder: 2)
        let childA = LedgerCategory(id: 11, name: "早餐", flowType: .expense, icon: nil, color: nil, parentId: 10, level: 2, children: [], sortOrder: 0)
        let childB = LedgerCategory(id: 12, name: "午餐", flowType: .expense, icon: nil, color: nil, parentId: 10, level: 2, children: [], sortOrder: 1)
        let parent = LedgerCategory(id: 10, name: "日常吃饭", flowType: .expense, icon: nil, color: nil, parentId: nil, level: 1, children: [childA, childB], sortOrder: 3)
        let tree = [siblingA, income, siblingB, parent]

        let movedRoot = CategoryTreeBuilder.moving(categoryId: 1, relativeTo: 2, after: true, in: tree)
        XCTAssertEqual(movedRoot.filter { $0.flowType == .expense }.map(\.id), [2, 1, 10])
        XCTAssertEqual(movedRoot.first(where: { $0.id == 9 })?.id, 9)

        // A drop between existing rows must remain a real insertion, not snap to the top.
        let movedIntoMiddle = CategoryTreeBuilder.moving(categoryId: 10, relativeTo: 1, after: true, in: tree)
        XCTAssertEqual(movedIntoMiddle.filter { $0.flowType == .expense }.map(\.id), [1, 10, 2])

        let movedChild = CategoryTreeBuilder.moving(categoryId: 11, relativeTo: 12, after: true, in: tree)
        XCTAssertEqual(movedChild.first(where: { $0.id == 10 })?.children.map(\.id), [12, 11])
    }

    func testReceiptParserIgnoresStatusBarTimeAndMergesMultilineTitle() {
        let parser = ReceiptParser()
        let text = """
        21:14 5G
        账单
        商品名称
        超长 商品 名称 第一行
        第二行标题
        支付时间
        2026年9月24日 18:00:32
        支付金额
        -20.20
        商户全称
        示例商户
        支付方式
        银行卡
        当前状态
        支付成功
        """
        let result = parser.parse(rawText: text)
        XCTAssertEqual(result.title, "超长 商品 名称 第一行 第二行标题")
        XCTAssertNotNil(result.happenedAt)
        if let happenedAt = result.happenedAt {
            XCTAssertEqual(Calendar.current.component(.hour, from: happenedAt), 18)
            XCTAssertEqual(Calendar.current.component(.minute, from: happenedAt), 0)
        }
    }

    func testBillFileImportParsesCSVAfterPickerSelection() throws {
        let csv = "交易时间,商品说明,交易对方,收/支,金额\n2026-09-24 18:00:00,工作餐,公司食堂,支出,-20.20\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("smartledger-import-test.csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let items = try BillFileImportService().parse(url: url)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "工作餐")
        XCTAssertEqual(items.first?.amount ?? 0, 20.20, accuracy: 0.01)
        XCTAssertEqual(items.first?.categoryPath, ["餐饮", "日常吃饭", "晚餐"])
        XCTAssertNotNil(items.first?.happenedAt)
    }

    func testMealTransactionsUseTimeSpecificSubcategoriesForFileImport() throws {
        let csv = "交易时间,商品说明,交易对方,收/支,金额\n" +
            "2026-09-24 08:30:00,早餐,公司食堂,支出,-10.00\n" +
            "2026-09-24 12:30:00,午餐,公司食堂,支出,-20.00\n" +
            "2026-09-24 18:30:00,晚餐,公司食堂,支出,-30.00\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("smartledger-meal-time-test.csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let items = try BillFileImportService().parse(url: url)
        XCTAssertEqual(items.map(\.categoryPath), [
            ["餐饮", "日常吃饭", "早餐"],
            ["餐饮", "日常吃饭", "午餐"],
            ["餐饮", "日常吃饭", "晚餐"]
        ])
    }

    @MainActor
    func testBankPDFImportReadsTableColumnsAndSignedAmounts() throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 842, height: 595))
        let pdf = renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9)]
            let columns: [CGFloat] = [18, 87, 145, 204, 254, 312, 405, 478, 532, 598, 690, 778]
            let lines: [[String]] = [
                ["记账日期", "记账时间", "币别", "金额", "余额", "交易名称", "渠道", "网点名称", "附言", "对方账户名", "对方卡号/账号", "对方开户地址"],
                ["2026-07-01", "08:30:00", "人民币", "-20.20", "1000.00", "POS消费", "手机银行", "北京支行", "瑞幸咖啡工作餐", "瑞幸咖啡", "123456", "北京"],
                ["2026-07-02", "18:40:00", "人民币", "3000.00", "4000.00", "工资入账", "银企对接", "北京支行", "七月工资", "某公司", "654321", "北京"]
            ]
            for (rowIndex, row) in lines.enumerated() {
                let y = CGFloat(30 + rowIndex * 24)
                for (columnIndex, value) in row.enumerated() {
                    value.draw(at: CGPoint(x: columns[columnIndex], y: y), withAttributes: attributes)
                }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("smartledger-bank-statement-test.pdf")
        try pdf.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let items = try BillFileImportService().parse(url: url)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "POS消费")
        XCTAssertEqual(items[0].merchant, "瑞幸咖啡")
        XCTAssertEqual(items[0].paymentMethod, "手机银行")
        XCTAssertEqual(items[0].kind, .expense)
        XCTAssertEqual(items[0].amount ?? 0, 20.20, accuracy: 0.01)
        XCTAssertEqual(items[0].categoryPath, ["餐饮", "日常吃饭", "早餐"])
        XCTAssertEqual(items[1].kind, .income)
        XCTAssertEqual(items[1].amount ?? 0, 3000, accuracy: 0.01)
    }
}

/*
/*
/*
/*
/*
/*
/*
/*
/*
/*
}*/
XCTSkip("Local bank statement fixture is not installed")
        }
        let items = try BillFileImportService().parse(url: url)
        XCTAssertGreaterThan(items.count, 100)
        XCTAssertEqual(items.first?.amount ?? 0, 3.80, accuracy: 0.01)
        XCTAssertEqual(items.first?.kind, .expense)
        XCTAssertEqual(items.first?.title, "网上快捷支付")
    }
}*/
   }
}*/
       XCTAssertEqual(items.first?.kind, .expense)
        XCTAssertEqual(items.first?.title, "网上快捷支付")
    }
}*/
   }
}*/
   }
}*/
       XCTAssertEqual(items.first?.kind, .expense)
        XCTAssertEqual(items.first?.title, "网上快捷支付")
    }
}*/
   }
}*/
   }
}*/
   }
}*/
