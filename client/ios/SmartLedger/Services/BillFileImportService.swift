import Compression
import Foundation
import PDFKit

/// Parses exported Alipay, WeChat, Meituan, JD and bank statement files into
/// the same editable review model used by screenshot OCR.
struct BillFileImportService: Sendable {
    enum Source: String, Equatable, Sendable {
        case alipay = "支付宝"
        case wechat = "微信"
        case meituan = "美团"
        case jd = "京东"
        case bank = "银行流水"
        case unknown = "账单文件"
    }

    enum ImportError: LocalizedError {
        case unreadable(String)
        case unsupported(String)
        case invalidHeader(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name):
                return "无法读取 \(name)，请确认文件没有损坏。"
            case .unsupported(let name):
                return "暂不支持 \(name) 格式，请选择银行流水 PDF 或 CSV、TXT、XLSX 账单文件。"
            case .invalidHeader(let name):
                if name.lowercased().hasSuffix(".pdf") {
                    return "未识别出银行流水 PDF 的表格内容。请确认 PDF 中的文字可选择或复制；扫描图片版暂不支持文件解析。"
                }
                return "未识别出 \(name) 的账单表头，请选择交易明细导出文件。"
            }
        }
    }

    func parse(url: URL) throws -> [OCRImportResult] {
        let fileName = url.lastPathComponent
        let source = source(for: fileName)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadable(fileName)
        }

        if ["xlsx", "xlsm"].contains(url.pathExtension.lowercased()) {
            guard let rows = XLSXRows(data: data).read() else {
                throw ImportError.unreadable(fileName)
            }
            return try parse(rows: rows, source: source == .unknown ? inferSource(rows: rows) : source, fileName: fileName)
        }

        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(data: data) else {
                throw ImportError.unreadable(fileName)
            }
            let rows = PDFTableRows(document: document).read()
            let pdfSource = source == .unknown ? inferSource(rows: rows) : source
            return try parse(rows: rows, source: pdfSource, fileName: fileName)
        }

        guard ["csv", "txt", "tsv", ""].contains(url.pathExtension.lowercased()) else {
            throw ImportError.unsupported(fileName)
        }
        guard let text = decode(data) else {
            throw ImportError.unreadable(fileName)
        }
        let rows = CSVRows(text: text).read()
        return try parse(rows: rows, source: source == .unknown ? inferSource(rows: rows) : source, fileName: fileName)
    }

    private func parse(rows: [[String]], source: Source, fileName: String) throws -> [OCRImportResult] {
        guard let headerRow = rows.firstIndex(where: { row in
            let line = row.joined(separator: " ").billNormalized
            return (line.contains("交易时间") || line.contains("交易创建时间") || line.contains("记账日期") || line.contains("日期"))
                && (line.contains("金额") || line.contains("收支") || line.contains("收/支"))
        }) else {
            throw ImportError.invalidHeader(fileName)
        }

        let headers = rows[headerRow].map(\.billNormalized)
        let dateIndex = index(headers, ["交易成功时间", "交易时间", "交易创建时间", "创建时间", "支付时间", "记账日期", "时间", "日期"])
        let timeIndex = index(headers, ["记账时间"])
        let titleIndex = index(headers, ["商品说明", "商品名称", "订单标题", "交易说明", "交易名称", "商品", "交易对方", "对方账户名", "收款方", "商户"])
        let merchantIndex = index(headers, ["交易对方", "对方账户名", "收款方", "商户", "商户名称", "商家名称", "店铺名称"])
        let memoIndex = index(headers, ["附言", "摘要", "备注"])
        let flowIndex = index(headers, ["收/支", "收支", "交易类型", "类型"])
        let paymentIndex = index(headers, ["收/付款方式", "付款方式", "支付方式", "支付渠道", "渠道"])
        let amountIndex = source == .meituan
            ? (index(headers, ["实付金额"]) ?? index(headers, ["金额", "订单金额"]))
            : index(headers, ["金额（元）", "金额(元)", "金额", "实付金额", "订单金额", "支付金额"])
        let statusIndex = index(headers, ["交易状态", "支付状态", "状态"])
        let categoryIndex = index(headers, ["交易分类", "账单分类", "类目"])

        guard dateIndex != nil, (titleIndex != nil || merchantIndex != nil), amountIndex != nil else {
            throw ImportError.invalidHeader(fileName)
        }

        var results: [OCRImportResult] = []
        var seen = Set<String>()
        for row in rows.dropFirst(headerRow + 1) {
            guard let date = parseDate(value(row, dateIndex), time: value(row, timeIndex)),
                  let amountValue = parseAmount(value(row, amountIndex)),
                  amountValue != 0 else { continue }

            let title = firstNonEmpty(value(row, titleIndex), value(row, merchantIndex), value(row, memoIndex)).billDecoded
            guard !title.isEmpty else { continue }
            guard let kind = parseKind(value(row, flowIndex), amountText: value(row, amountIndex), source: source) else { continue }

            let status = value(row, statusIndex)
            guard !status.contains("失败"), !status.contains("关闭") else { continue }

            let amount = abs(amountValue)
            let key = "\(Int(date.timeIntervalSince1970 / 60))|\(kind.rawValue)|\(String(format: "%.2f", amount))|\(title.billNormalized)"
            guard seen.insert(key).inserted else { continue }

            let merchant = value(row, merchantIndex).billDecoded
            let classificationMerchant = [merchant, value(row, memoIndex).billDecoded]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let category = classify(
                title: title,
                merchant: classificationMerchant,
                sourceCategory: value(row, categoryIndex),
                source: source,
                kind: kind,
                date: date
            )
            results.append(OCRImportResult(
                amount: amount,
                kind: kind,
                merchant: merchant.nilIfEmpty,
                paymentMethod: value(row, paymentIndex).nilIfEmpty,
                title: title,
                happenedAt: date,
                categoryKeyword: category.last,
                categoryPath: category,
                details: [
                    OCRLineItem(label: "导入来源", value: source.rawValue),
                    OCRLineItem(label: "文件", value: fileName)
                ],
                confidence: 0.94,
                rawLines: row,
                originalAmount: nil,
                discountAmount: nil
            ))
        }
        return results
    }

    private func source(for fileName: String) -> Source {
        let name = fileName.lowercased()
        if name.contains("支付宝") || name.contains("alipay") { return .alipay }
        if name.contains("微信") || name.contains("wechat") { return .wechat }
        if name.contains("美团") || name.contains("meituan") { return .meituan }
        if name.contains("京东") || name.contains("jd") { return .jd }
        if name.contains("银行") || name.contains("交易流水明细") { return .bank }
        return .unknown
    }

    private func inferSource(rows: [[String]]) -> Source {
        guard let header = rows.first(where: { row in
            let line = row.joined(separator: " ").billNormalized
            return (line.contains("交易时间") || line.contains("交易创建时间") || line.contains("记账日期") || line.contains("日期"))
                && (line.contains("金额") || line.contains("收支") || line.contains("收/支"))
        })?.joined(separator: " ").billNormalized else { return .unknown }
        if header.contains("订单标题") || header.contains("实付金额") { return .meituan }
        if header.contains("交易说明") || header.contains("交易分类") && header.contains("商户名称") { return .jd }
        if header.contains("商品说明") && header.contains("收/付款方式") { return .alipay }
        if header.contains("商品") && header.contains("交易对方") { return .wechat }
        if header.contains("记账日期") && header.contains("交易名称") && header.contains("对方账户名") { return .bank }
        return .unknown
    }

    private func index(_ headers: [String], _ candidates: [String]) -> Int? {
        for candidate in candidates {
            if let match = headers.firstIndex(where: { $0.contains(candidate.billNormalized) }) {
                return match
            }
        }
        return nil
    }

    private func value(_ row: [String], _ index: Int?) -> String {
        guard let index, row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstNonEmpty(_ values: String...) -> String {
        values.first(where: { !$0.isEmpty }) ?? ""
    }

    private func parseAmount(_ value: String) -> Double? {
        let text = value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
        guard let range = text.range(of: #"[-+]?\d+(?:\.\d+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(String(text[range]))
    }

    private func parseKind(_ text: String, amountText: String, source: Source) -> FlowType? {
        if text.contains("不计") || (text.contains("其他") && !text.contains("收入")) { return nil }
        if text.contains("收入") || text.contains("退款") || text.contains("收款") { return .income }
        if text.contains("支出") || text.contains("付款") || text.contains("消费") { return .expense }
        if amountText.trimmingCharacters(in: .whitespaces).hasPrefix("-") { return .expense }
        if source == .bank { return .income }
        return source == .unknown ? nil : .expense
    }

    private func classify(title: String, merchant: String, sourceCategory: String, source: Source, kind: FlowType, date: Date) -> [String] {
        let text = "\(title) \(merchant) \(sourceCategory)".lowercased()
        guard kind == .expense else {
            if text.contains("退款") || text.contains("退货") { return ["其他收入", "退款"] }
            if text.contains("工资") || text.contains("薪") || text.contains("奖金") { return ["工资收入", "工资"] }
            if text.contains("转账") || text.contains("收款") { return ["工资收入", "转账收入"] }
            return ["其他收入", "意外所得"]
        }

        let food = ["外卖", "餐", "饭", "面", "粉", "烧烤", "火锅", "汉堡", "肯德基", "麦当劳", "奶茶", "咖啡", "饮料", "食堂", "小吃", "寿司", "料理", "披萨", "炸鸡"]
        if sourceCategory.contains("餐饮") || food.contains(where: { text.contains($0) }) {
            // 流水时间按账单使用的中国时区计算，避免远程运行环境（通常为 UTC）
            // 把晚餐误判成早餐。
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
            let hour = calendar.component(.hour, from: date)
            return ["餐饮", "日常吃饭", hour < 11 ? "早餐" : (hour < 16 ? "午餐" : "晚餐")]
        }
        if source == .meituan { return ["餐饮", "外卖"] }
        if text.contains("火车") || text.contains("机票") || text.contains("飞机") || text.contains("12306") {
            return ["交通出行", "火车机票"]
        }
        if text.contains("地铁") || text.contains("公交") { return ["交通出行", "地铁公交"] }
        if text.contains("加油") || text.contains("停车") || text.contains("充电") { return ["交通出行", "加油停车"] }
        if sourceCategory.contains("交通") || ["打车", "网约车", "滴滴", "高德"].contains(where: { text.contains($0) }) {
            return ["交通出行", "网约车"]
        }
        if sourceCategory.contains("文化休闲") || ["酒店", "民宿", "旅行", "景区", "电影", "影院", "游戏", "演出"].contains(where: { text.contains($0) }) {
            return ["休闲娱乐", "休闲玩乐"]
        }
        if sourceCategory.contains("医疗") || ["医院", "药", "医疗", "诊所", "保险"].contains(where: { text.contains($0) }) {
            return ["医疗健康", "药品"]
        }
        if sourceCategory.contains("教育") || ["课程", "培训", "书", "学习", "会员", "订阅", "软件"].contains(where: { text.contains($0) }) {
            return ["教育学习", "软件订阅"]
        }
        if sourceCategory.contains("家居") || ["房租", "水费", "电费", "燃气", "物业", "宽带", "插座", "家具", "家电"].contains(where: { text.contains($0) }) {
            return ["居住", "家居用品"]
        }
        if sourceCategory.contains("服饰") || text.contains("衣") || text.contains("鞋") { return ["购物", "服饰"] }
        if sourceCategory.contains("运动") { return ["休闲娱乐", "运动健身"] }
        if sourceCategory.contains("日用") || sourceCategory.contains("其他") { return ["购物", "日用百货"] }
        if ["礼物", "红包", "请客", "婚礼"].contains(where: { text.contains($0) }) { return ["人情往来", "礼物"] }
        return ["购物", "日用百货"]
    }

    private func parseDate(_ text: String, time: String = "") -> Date? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let combinedText = time.isEmpty || text.contains(":") ? text : "\(text) \(time)"
        if let serial = Double(text), serial > 20_000, serial < 80_000 {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
            let epoch = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30)) ?? Date(timeIntervalSince1970: -2_208_988_800)
            return epoch.addingTimeInterval(serial * 86_400)
        }
        let formats = [
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
            "yyyy.MM.dd HH:mm:ss", "yyyy.MM.dd HH:mm",
            "yyyy年MM月dd日 HH:mm:ss", "yyyy年MM月dd日 HH:mm",
            "MM-dd HH:mm:ss", "MM-dd HH:mm",
            "yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "yyyy年MM月dd日"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: combinedText) { return date }
        }
        return nil
    }

    private func decode(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [
            .utf8,
            String.Encoding(rawValue: 0x80000632), // GB18030
            String.Encoding(rawValue: 0x80000631), // GBK
            .unicode,
            .shiftJIS
        ]
        return encodings.compactMap { String(data: data, encoding: $0) }.first
    }
}

private extension String {
    var billNormalized: String {
        replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .lowercased()
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var billDecoded: String {
        replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

private struct CSVRows {
    let text: String

    func read() -> [[String]] {
        let firstLine = text.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? ""
        let delimiter: Character = firstLine.contains("\t") ? "\t" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(text)
        chars.append("\n")
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\"" {
                if quoted, index + 1 < chars.count, chars[index + 1] == "\"" {
                    field.append("\"")
                    index += 2
                    continue
                }
                quoted.toggle()
            } else if char == delimiter && !quoted {
                row.append(field)
                field = ""
            } else if (char == "\n" || char == "\r") && !quoted {
                if char == "\r", index + 1 < chars.count, chars[index + 1] == "\n" { index += 1 }
                row.append(field)
                field = ""
                rows.append(row)
                row = []
            } else {
                field.append(char)
            }
            index += 1
        }
        return rows
    }
}

/// Reconstructs a simple text table from PDFKit glyph coordinates. This keeps
/// bank PDF parsing independent of page templates and supports multi-page
/// exports with repeated table headers.
private struct PDFTableRows {
    private struct TextRun {
        let text: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    let document: PDFDocument

    func read() -> [[String]] {
        var result: [[String]] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            result.append(contentsOf: rows(on: page))
        }
        return result
    }

    private func rows(on page: PDFPage) -> [[String]] {
        guard let text = page.string, !text.isEmpty else { return [] }
        // PDFKit's per-character bounds are unreliable for some generated and
        // bank PDFs (some glyphs get zero-width or tiny boxes). Text selections
        // preserve each positioned text run, which lets us recover table cells
        // without depending on a particular page size or bank template.
        let pageBounds = page.bounds(for: .mediaBox)
        let selections = page.selection(for: pageBounds)?.selectionsByLine() ?? []
        let runs = selections.compactMap { selection -> TextRun? in
            guard let value = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            let bounds = selection.bounds(for: page)
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            return TextRun(text: value, x: bounds.minX, y: bounds.midY, width: bounds.width, height: bounds.height)
        }

        if !runs.isEmpty {
            let lines = groupedLines(runs)
            if let header = lines.first(where: { line in
                let value = line.sorted { $0.x < $1.x }.map(\.text).joined().billNormalized
                return value.contains("记账日期") && value.contains("金额") && value.contains("交易名称")
            }) {
                let headerRuns = header.sorted { $0.x < $1.x }
                if headerRuns.count >= 6 {
                    return mappedRows(lines, columnStarts: headerRuns.map(\.x))
                }
                // Some PDF generators return a whole text object as one run,
                // even when it visually spans multiple columns. Fall through
                // to glyph geometry so gaps in the table header recover columns.
            }
        }

        let source = text as NSString
        var glyphs: [TextRun] = []
        glyphs.reserveCapacity(source.length)
        for index in 0..<source.length {
            let character = source.substring(with: NSRange(location: index, length: 1))
            guard !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let bounds = page.characterBounds(at: index)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            glyphs.append(TextRun(text: character, x: bounds.minX, y: bounds.midY, width: bounds.width, height: bounds.height))
        }
        if !glyphs.isEmpty {
            let lines = groupedLines(glyphs)
            if let header = lines.first(where: { line in
                line.sorted { $0.x < $1.x }.map(\.text).joined().billNormalized
                    .range(of: "记账日期.*金额.*交易名称", options: .regularExpression) != nil
            }) {
                let headerGlyphs = header.sorted { $0.x < $1.x }
                let widths = headerGlyphs.map(\.width).filter { $0 > 0 }.sorted()
                let typicalWidth = widths.isEmpty ? 8 : widths[widths.count / 2]
                let gapThreshold = max(2, typicalWidth * 0.55)
                var starts: [CGFloat] = []
                var previous: TextRun?
                for glyph in headerGlyphs {
                    if let previous,
                       glyph.x - previous.x - previous.width > gapThreshold {
                        starts.append(glyph.x)
                    } else if starts.isEmpty {
                        starts.append(glyph.x)
                    }
                    previous = glyph
                }
                if starts.count >= 6 {
                    return mappedRows(lines, columnStarts: starts)
                }
            }
        }

        // Logical text-only fallback for PDFs whose text layer has no usable
        // geometry. Bank exports commonly preserve transaction records in
        // reading order even when PDFKit coalesces the whole table row into one run.
        if let rows = logicalBankRows(text), !rows.isEmpty { return rows }
        return text.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .filter { !$0.isEmpty }
    }

    private func logicalBankRows(_ text: String) -> [[String]]? {
        let normalized = text.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let nsText = normalized as NSString
        let pattern = #"\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+\d{2}:\d{2}:\d{2}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let records = expression.matches(in: normalized, range: NSRange(location: 0, length: nsText.length))
        guard !records.isEmpty else { return nil }

        let knownChannels = ["手机银行", "银企对接", "POS机", "支付宝", "微信", "柜面", "网银"]
        var rows = [["记账日期", "记账时间", "币别", "金额", "余额", "交易名称", "渠道", "网点名称", "附言", "对方账户名", "对方卡号/账号", "对方开户地址"]]
        for (index, match) in records.enumerated() {
            let end = index + 1 < records.count ? records[index + 1].range.location : nsText.length
            let chunk = nsText.substring(with: NSRange(location: match.range.location, length: end - match.range.location))
            let tokens = chunk.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.count >= 7 else { continue }

            let moneyPattern = #"^[+-]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{2})$"#
            let moneyIndices = tokens.indices.dropFirst(2).filter {
                tokens[$0].range(of: moneyPattern, options: .regularExpression) != nil
            }
            guard moneyIndices.count >= 2 else { continue }
            let amountIndex = moneyIndices[0]
            let balanceIndex = moneyIndices[1]
            guard let channelIndex = tokens.indices.first(where: { position in
                position > balanceIndex && knownChannels.contains(where: { tokens[position].contains($0) })
            }) else { continue }

            let title = tokens[(balanceIndex + 1)..<channelIndex].joined().trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            let channel = knownChannels.first(where: { tokens[channelIndex].contains($0) }) ?? tokens[channelIndex]
            var tail = Array(tokens.dropFirst(channelIndex + 1))
            if tail.first?.allSatisfy({ $0 == "-" }) == true { tail.removeFirst() }
            let branch = tail.indices.contains(0) ? tail[0] : ""
            let memo = tail.indices.contains(1) ? tail[1] : ""
            let counterparty = tail.indices.contains(2) ? tail[2] : ""
            let account = tail.indices.contains(3) ? tail[3] : ""
            let address = tail.dropFirst(min(4, tail.count)).joined(separator: " ")
            rows.append([
                tokens[0], tokens[1], "人民币", tokens[amountIndex], tokens[balanceIndex],
                title, channel, branch, memo, counterparty, account, address
            ])
        }
        return rows.count > 1 ? rows : nil
    }

    private func mappedRows(_ lines: [[TextRun]], columnStarts: [CGFloat]) -> [[String]] {
        let boundaries = zip(columnStarts, columnStarts.dropFirst()).map { ($0 + $1) / 2 }
        return lines.map { line in
            var cells = Array(repeating: "", count: columnStarts.count)
            for run in line.sorted(by: { $0.x < $1.x }) {
                let column = boundaries.firstIndex(where: { run.x < $0 }) ?? (columnStarts.count - 1)
                if !cells[column].isEmpty { cells[column].append(" ") }
                cells[column].append(contentsOf: run.text)
            }
            return cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    private func groupedLines(_ runs: [TextRun]) -> [[TextRun]] {
        let sorted = runs.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y > $1.y }
        var lines: [[TextRun]] = []
        var centers: [CGFloat] = []
        for run in sorted {
            let tolerance = max(2.0, run.height * 0.35)
            if let index = centers.indices.min(by: { abs(centers[$0] - run.y) < abs(centers[$1] - run.y) }),
               abs(centers[index] - run.y) <= tolerance {
                lines[index].append(run)
                centers[index] = lines[index].reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(lines[index].count)
            } else {
                lines.append([run])
                centers.append(run.y)
            }
        }
        return lines
    }
}

/// Small XLSX reader for standard WeChat exports. WeChat exports use shared
/// strings and the first worksheet; no third-party dependency is required.
private struct XLSXRows {
    let data: Data

    func read() -> [[String]]? {
        guard let sharedData = zipEntry("xl/sharedStrings.xml"),
              let shared = xmlValues(sharedData),
              let sheet = zipEntry("xl/worksheets/sheet1.xml") else { return nil }
        return worksheetValues(sheet, shared: shared)
    }

    private func zipEntry(_ name: String) -> Data? {
        guard data.count >= 22 else { return nil }
        let start = max(0, data.count - 65_557)
        var end: Int?
        for offset in stride(from: data.count - 22, through: start, by: -1) where u32(offset) == 0x06054b50 {
            end = offset
            break
        }
        guard let end else { return nil }
        let directorySize = u32(end + 12)
        let directoryOffset = u32(end + 16)
        var cursor = directoryOffset
        while cursor + 46 <= directoryOffset + directorySize, u32(cursor) == 0x02014b50 {
            let method = u16(cursor + 10)
            let compressedSize = u32(cursor + 20)
            let uncompressedSize = u32(cursor + 24)
            let nameLength = u16(cursor + 28)
            let extraLength = u16(cursor + 30)
            let commentLength = u16(cursor + 32)
            let localOffset = u32(cursor + 42)
            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else { return nil }
            let entryName = String(data: data[nameStart..<(nameStart + nameLength)], encoding: .utf8) ?? ""
            if entryName == name {
                guard localOffset + 30 <= data.count else { return nil }
                let localNameLength = u16(localOffset + 26)
                let localExtraLength = u16(localOffset + 28)
                let payload = localOffset + 30 + localNameLength + localExtraLength
                guard payload + compressedSize <= data.count else { return nil }
                let bytes = Data(data[payload..<(payload + compressedSize)])
                return method == 0 ? bytes : inflate(bytes, size: uncompressedSize)
            }
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return nil
    }

    private func u16(_ index: Int) -> Int {
        Int(data[index]) | (Int(data[index + 1]) << 8)
    }

    private func u32(_ index: Int) -> Int {
        u16(index) | (u16(index + 2) << 16)
    }

    private func inflate(_ input: Data, size: Int) -> Data? {
        var output = Data(count: max(size, 1))
        let count = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    destination.count,
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard count > 0 else { return nil }
        output.count = count
        return output
    }

    private func xmlValues(_ data: Data) -> [String]? {
        let text = String(decoding: data, as: UTF8.self)
        let matches = text.matches(of: /(?s)<si(?:\s[^>]*)?>(.*?)<\/si>/)
        return matches.map { match in
            match.1.matches(of: /(?s)<t(?:\s[^>]*)?>(.*?)<\/t>/)
                .map { String($0.1).billDecoded }
                .joined()
        }
    }

    private func worksheetValues(_ data: Data, shared: [String]) -> [[String]] {
        let text = String(decoding: data, as: UTF8.self)
        return text.matches(of: /(?s)<row(?:\s[^>]*)?>(.*?)<\/row>/).map { rowMatch in
            var cells: [(Int, String)] = []
            for cell in String(rowMatch.1).matches(of: /(?s)<c\s+([^>]*)>(.*?)<\/c>/) {
                let attributes = String(cell.1)
                guard let reference = attributes.firstMatch(of: /r="([A-Z]+)\d+"/) else { continue }
                let column = reference.1.utf8.reduce(0) { $0 * 26 + Int($1) - 64 } - 1
                let type = attributes.firstMatch(of: /t="([^"]+)"/).map { String($0.1) } ?? ""
                let contents = String(cell.2)
                let raw = contents.firstMatch(of: /(?s)<v>(.*?)<\/v>/).map { String($0.1) }
                    ?? contents.firstMatch(of: /(?s)<t>(.*?)<\/t>/).map { String($0.1).billDecoded }
                    ?? ""
                var value = raw
                if type == "s", let index = Int(raw), shared.indices.contains(index) {
                    value = shared[index]
                }
                cells.append((column, value))
            }
            var row = Array(repeating: "", count: (cells.map(\.0).max() ?? -1) + 1)
            for (column, value) in cells where row.indices.contains(column) {
                row[column] = value
            }
            return row
        }
    }
}
/*
// The duplicate trailing worksheet parser fragment was removed.
// End of the file; no trailing parser fragment.
// }
// End of the file; no trailing parser fragment.
                row[column] = value
            }
            return row
        }
    }
}
// The duplicate trailing worksheet parser fragment was removed.
// End of the file; no trailing parser fragment.
// }
// End of the file; no trailing parser fragment.
trailing parser fragment.
*/
/*
ing parser fragment.
trailing parser fragment.
*/
