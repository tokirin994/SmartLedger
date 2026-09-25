import XCTest
@testable import SmartLedger

final class SmartLedgerCoreTests: XCTestCase {
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
        XCTAssertNotNil(result.happenedAt)
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
        XCTAssertNotNil(items.first?.happenedAt)
    }
}
