import SwiftUI
import UniformTypeIdentifiers

struct BooksView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var showingCreate = false
    @State private var searchText = ""
    @State private var bookToDelete: LedgerBook?

    private var filteredBooks: [LedgerBook] {
        store.books.filter { book in
            searchText.isEmpty || book.name.localizedCaseInsensitiveContains(searchText) || (book.note ?? "").localizedCaseInsensitiveContains(searchText)
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            if $0.startDate != $1.startDate { return ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            return $0.id > $1.id
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        bookMetric("账本数", "\(store.books.count)", .blue)
                        bookMetric("主题支出", store.books.reduce(0) { $0 + $1.expenseAmount }.cnyText, .orange)
                        bookMetric("主题收入", store.books.reduce(0) { $0 + $1.incomeAmount }.cnyText, .green)
                    }.listRowBackground(Color.clear)
                }
                Section {
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("搜索账本标题", text: $searchText); if !searchText.isEmpty { Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") } } }
                }
                if filteredBooks.isEmpty {
                    Section { ContentUnavailableView(searchText.isEmpty ? "暂无主题账本" : "没有匹配的账本", systemImage: "books.vertical") }
                } else {
                    Section {
                        ForEach(filteredBooks) { book in
                            NavigationLink { BookDetailView(book: book) } label: { BookRow(book: book) }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button { Task { await store.setBookPinned(book.id, pinned: !book.isPinned) } } label: { Label(book.isPinned ? "取消置顶" : "置顶", systemImage: book.isPinned ? "pin.slash" : "pin") }.tint(.orange)
                                    Button(role: .destructive) { bookToDelete = book } label: { Label("删除", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .dismissKeyboardWhenTappedOutside()
            .navigationTitle("账本")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { Task { await store.loadBooks() } } label: { Image(systemName: "arrow.clockwise") } }
                ToolbarItem(placement: .topBarTrailing) { Button { showingCreate = true } label: { Image(systemName: "plus") } }
            }
            .sheet(isPresented: $showingCreate) { BookEditorView(book: nil).environmentObject(store) }
            .alert("删除账本？", isPresented: Binding(get: { bookToDelete != nil }, set: { if !$0 { bookToDelete = nil } })) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { if let bookToDelete { Task { await store.deleteBook(bookToDelete.id) }; self.bookToDelete = nil } }
            } message: { Text("删除账本不会删除流水，只会移除流水与该账本的关联。") }
            .task { await store.loadBooks() }
        }
    }

    private func bookMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.bold)).foregroundStyle(color) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(10).glassCard(cornerRadius: 14, strokeOpacity: 0.16)
    }
}
private struct BookRow: View {
    let book: LedgerBook

    private var periodText: String {
        guard let start = book.startDate else { return "未限定期间" }
        let startText = start.formatted(date: .abbreviated, time: .omitted)
        return book.endDate.map { "\(startText) - \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "自 \(startText) 起"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: book.icon ?? "book.closed.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(hex: book.color ?? "#4F46E5"))
                    .frame(width: 46, height: 46)
                    .background(Color(hex: book.color ?? "#4F46E5").opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(book.name).font(.headline)
                        if book.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) }
                    }
                    Label(book.splitEnabled ? "多人分账" : "个人记账", systemImage: book.splitEnabled ? "person.2.fill" : "person.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(book.splitEnabled ? .purple : .secondary)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background((book.splitEnabled ? Color.purple : Color.secondary).opacity(0.11), in: Capsule())
                    Label("\(book.transactionCount) 笔流水", systemImage: "list.bullet")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 5) {
                    Text("净额").font(.caption2).foregroundStyle(.secondary)
                    Text(book.balance.cnyText)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(book.balance < 0 ? .red : .blue)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        Text("支 \(book.expenseAmount.cnyText)").foregroundStyle(.orange)
                        Text("收 \(book.incomeAmount.cnyText)").foregroundStyle(.green)
                    }
                    .font(.caption2.weight(.medium))
                    .lineLimit(1).minimumScaleFactor(0.65)
                }
            }

            Divider().opacity(0.45)
            HStack(spacing: 10) {
                Label(periodText, systemImage: "calendar")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color(hex: book.color ?? "#4F46E5"))
                    .lineLimit(1)
            }
            .font(.caption2.weight(.medium))
        }
        .padding(14)
        .background(Color(hex: book.color ?? "#4F46E5").opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .leading) { Capsule().fill(Color(hex: book.color ?? "#4F46E5")).frame(width: 4).padding(.vertical, 14) }
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color(hex: book.color ?? "#4F46E5").opacity(0.14), lineWidth: 1) }
        .padding(.vertical, 4)
    }
}

private struct BookDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let book: LedgerBook
    @State private var showingEditor = false
    @State private var deleteRequested = false
    @State private var editingTransaction: LedgerTransaction?
    @State private var exportFormat: BookExportFormat?
    @State private var showExportFormatPicker = false

    private var relatedTransactions: [LedgerTransaction] { store.transactions.filter { $0.bookIds.contains(book.id) || $0.bookId == book.id }.sorted { $0.happenedAt > $1.happenedAt } }
    private var current: LedgerBook { store.books.first(where: { $0.id == book.id }) ?? book }
    private func transactionAmountText(_ transaction: LedgerTransaction) -> String { (transaction.kind == .expense ? -transaction.amount : transaction.amount).cnyText }
    private func transactionAmountColor(_ transaction: LedgerTransaction) -> Color { transaction.kind == .expense ? .primary : .green }
    private var splitTransactions: [LedgerTransaction] { relatedTransactions.filter { $0.kind == .expense && !$0.splitParticipantIds.isEmpty } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(current.note?.isEmpty == false ? current.note! : "将相关流水归集在一起").foregroundStyle(.secondary)
                    HStack(spacing: 10) { metric("支出", current.expenseAmount.cnyText, .orange); metric("收入", current.incomeAmount.cnyText, .green); metric("净额", current.balance.cnyText, current.balance < 0 ? .red : .blue) }
                    HStack(spacing: 10) {
                        metric("优惠", relatedTransactions.compactMap(\.discountAmount).reduce(0, +).cnyText, .green)
                        metric("溢价", relatedTransactions.compactMap(\.premiumAmount).reduce(0, +).cnyText, .red)
                    }
                    if !current.participantNames.isEmpty { Text("分账成员").font(.caption).foregroundStyle(.secondary); ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(current.participantNames, id: \.self) { Text($0).padding(.horizontal, 11).padding(.vertical, 6).background(.blue.opacity(0.1), in: Capsule()) } } } }
                }.padding().glassCard(cornerRadius: 20, strokeOpacity: 0.15)
                if current.budgetEnabled { budgetCard }
                if !splitTransactions.isEmpty { splitCard }
                transactionsCard
            }.padding()
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .dismissKeyboardWhenTappedOutside()
        .navigationTitle(current.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Button("设置") { showingEditor = true }; Button("导出账本") { showExportFormatPicker = true }; Button(current.isPinned ? "取消置顶" : "置顶") { Task { await store.setBookPinned(current.id, pinned: !current.isPinned) } }; Button("删除账本", role: .destructive) { deleteRequested = true } } label: { Image(systemName: "gearshape") } } }
        .sheet(isPresented: $showingEditor) { BookEditorView(book: current).environmentObject(store) }
        .sheet(item: $editingTransaction) { transaction in
            CreateTransactionView(editingTransaction: transaction)
                .environmentObject(store)
        }
        .fileExporter(isPresented: Binding(get: { exportFormat != nil }, set: { if !$0 { exportFormat = nil } }), document: BookExportDocument(book: current, transactions: relatedTransactions, format: exportFormat ?? .markdown), contentType: exportFormat?.contentType ?? .plainText, defaultFilename: "\(current.name).\(exportFormat?.fileExtension ?? "md")") { _ in exportFormat = nil }
        .confirmationDialog("选择导出格式", isPresented: $showExportFormatPicker, titleVisibility: .visible) {
            Button("导出 HTML 报告") { exportFormat = .html }
            Button("导出 Markdown") { exportFormat = .markdown }
            Button("取消", role: .cancel) {}
        } message: {
            Text("HTML 适合直接打开或打印，Markdown 适合继续编辑。")
        }
        .alert("删除账本？", isPresented: $deleteRequested) { Button("取消", role: .cancel) {}; Button("删除", role: .destructive) { Task { await store.deleteBook(current.id) }; dismiss() } } message: { Text("删除账本不会删除流水，只会移除关联。") }
    }

    private var budgetCard: some View { let limit = current.budgetLimitAmount ?? 0; let remaining = limit - current.expenseAmount; return VStack(alignment: .leading, spacing: 12) { Text("账本预算").font(.title3.bold()); HStack(spacing: 10) { metric("预算", limit.cnyText, .blue); metric("已用", current.expenseAmount.cnyText, .orange); metric("剩余", remaining.cnyText, remaining < 0 ? .red : .green) }; ProgressView(value: min(max(current.expenseAmount / max(limit, 1), 0), 1)).tint(remaining < 0 ? .red : .blue); Text("预算周期：\(periodText)").font(.caption).foregroundStyle(.secondary) }.padding().glassCard(cornerRadius: 20, strokeOpacity: 0.15) }
    private var splitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("最终分账").font(.title3.bold())
            if current.autoCollectEnabled {
                Label("归集流水无分账信息时默认由我承担；已有分账信息按流水设置计算", systemImage: "person.3.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(current.participants) { member in
                    let paid = splitTransactions.filter { $0.paidByParticipantId == member.id }.reduce(0) { $0 + $1.amount }
                    let owed = splitTransactions.filter { $0.splitParticipantIds.contains(member.id) }.reduce(0) { $0 + $1.amount / Double(max($1.splitParticipantIds.count, 1)) }
                    let net = paid - owed
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(member.name).font(.headline)
                            Spacer()
                            Text(net >= 0 ? "应收 \(net.cnyText)" : "应付 \((-net).cnyText)")
                                .foregroundStyle(net >= 0 ? .green : .orange)
                        }
                        HStack(spacing: 10) {
                            metric("已支付", paid.cnyText, .blue)
                            metric("应承担", owed.cnyText, .purple)
                        }
                    }
            }
        }
        .padding()
        .glassCard(cornerRadius: 20, strokeOpacity: 0.15)
    }
    private var transactionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("归集流水").font(.title3.bold())
                Spacer()
                Text("左滑可取消关联").font(.caption2).foregroundStyle(.secondary)
                Text("\(relatedTransactions.count) 笔").font(.caption).foregroundStyle(.secondary)
            }
            if relatedTransactions.isEmpty {
                ContentUnavailableView("暂无归集流水", systemImage: "tray")
            }
            ForEach(relatedTransactions) { transaction in
                BookTransactionSwipeRow(transaction: transaction) {
                    Task { await store.removeTransaction(transaction.id, from: current.id) }
                } onEdit: {
                    editingTransaction = transaction
                }
            }
        }
    }
    private var periodText: String { guard let start = current.startDate else { return "未限定" }; let begin = start.formatted(date: .abbreviated, time: .omitted); return current.endDate.map { "\(begin) - \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "自 \(begin) 起" }
    private func metric(_ title: String, _ value: String, _ color: Color) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.bold()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65) }.frame(maxWidth: .infinity, minHeight: 62, alignment: .leading).padding(10).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12)) }
}

private struct BookTransactionSwipeRow: View {
    let transaction: LedgerTransaction
    let onRemove: () -> Void
    let onEdit: () -> Void
    @State private var isActionRevealed = false
    @GestureState private var dragOffset: CGFloat = 0

    private var amountText: String { (transaction.kind == .expense ? -transaction.amount : transaction.amount).cnyText }
    private var amountColor: Color { transaction.kind == .expense ? .primary : .green }
    private var contentOffset: CGFloat {
        let base: CGFloat = isActionRevealed ? -96 : 0
        return min(0, max(-96, base + dragOffset))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                withAnimation(.snappy) { isActionRevealed = false }
                onRemove()
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "link.badge.minus")
                    Text("取消关联").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 94)
                .frame(maxHeight: .infinity)
                .background(.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Image(systemName: transaction.kind == .expense ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                    .font(.title3).foregroundStyle(transaction.kind == .expense ? .orange : .green).frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(transaction.categoryName ?? "未分类")
                        Text("·")
                        Text(transaction.happenedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(amountText).font(.subheadline.weight(.bold)).foregroundStyle(amountColor)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1) }
            .offset(x: contentOffset)
            .onTapGesture {
                guard !isActionRevealed else { return }
                onEdit()
            }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .updating($dragOffset) { value, state, _ in state = value.translation.width }
                    .onEnded { value in
                        withAnimation(.snappy) {
                            let projected = (isActionRevealed ? -96 : 0) + value.predictedEndTranslation.width
                            isActionRevealed = projected < -48
                        }
                    }
            )
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private enum BookExportFormat: Equatable {
    case markdown, html
    var contentType: UTType { self == .markdown ? .plainText : .html }
    var fileExtension: String { self == .markdown ? "md" : "html" }
}

private struct BookExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .html] }
    let text: String

    init(book: LedgerBook, transactions: [LedgerTransaction], format: BookExportFormat) {
        let discount = transactions.compactMap(\.discountAmount).reduce(0, +)
        let premium = transactions.compactMap(\.premiumAmount).reduce(0, +)
        let period = Self.periodText(for: book)
        let rows = transactions.map { transaction in
            let sign = transaction.kind == .expense ? "-" : "+"
            let category = transaction.categoryName ?? "未分类"
            let date = transaction.happenedAt.formatted(date: .abbreviated, time: .shortened)
            return "| \(date) | \(transaction.title) | \(category) | \(sign)\(transaction.amount.cnyText) | \(transaction.note ?? "") |"
        }.joined(separator: "\n")
        let markdown = "# \(book.name)\n\n> 账本期间：\(period)\n\n## 汇总\n\n- 支出：\(book.expenseAmount.cnyText)\n- 收入：\(book.incomeAmount.cnyText)\n- 净额：\(book.balance.cnyText)\n- 优惠：\(discount.cnyText)\n- 溢价：\(premium.cnyText)\n\n## 流水\n\n| 时间 | 标题 | 分类 | 金额 | 备注 |\n|---|---|---|---:|---|\n\(rows)\n"
        if format == .markdown {
            self.text = markdown
        } else {
            self.text = Self.htmlReport(book: book, transactions: transactions, period: period, discount: discount, premium: premium)
        }
    }

    private static func periodText(for book: LedgerBook) -> String {
        guard let start = book.startDate else { return "未限定" }
        let begin = start.formatted(date: .abbreviated, time: .omitted)
        return book.endDate.map { "\(begin) - \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "自 \(begin) 起"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func htmlReport(book: LedgerBook, transactions: [LedgerTransaction], period: String, discount: Double, premium: Double) -> String {
        let expense = transactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
        let income = transactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
        let categories = Dictionary(grouping: transactions.filter { $0.kind == .expense }, by: { $0.categoryName ?? "未分类" })
            .map { (name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
        let maxCategory = max(categories.first?.amount ?? 1, 1)
        let categoryRows = categories.prefix(8).map { item in
            let percent = Int((item.amount / maxCategory * 100).rounded())
            return "<div class=\"category-row\"><div class=\"category-label\"><span>\(escape(item.name))</span><strong>\(item.amount.cnyText)</strong></div><div class=\"bar\"><i style=\"width:\(percent)%\"></i></div></div>"
        }.joined()
        let memberRows = book.participants.map { member in
            let paid = transactions.filter { $0.kind == .expense && $0.paidByParticipantId == member.id }.reduce(0) { $0 + $1.amount }
            let owed = transactions.filter { $0.kind == .expense && $0.splitParticipantIds.contains(member.id) }.reduce(0) { $0 + $1.amount / Double(max($1.splitParticipantIds.count, 1)) }
            return "<div class=\"member-row\"><span>\(escape(member.name))</span><span>已支付 <b>\(paid.cnyText)</b></span><span>应承担 <b>\(owed.cnyText)</b></span></div>"
        }.joined()
        let transactionRows = transactions.map { transaction in
            let isExpense = transaction.kind == .expense
            let amount = "\(isExpense ? "-" : "+")\(transaction.amount.cnyText)"
            let date = transaction.happenedAt.formatted(date: .abbreviated, time: .shortened)
            let discountText = transaction.discountAmount.map { "优惠 \($0.cnyText)" } ?? ""
            let premiumText = transaction.premiumAmount.map { "溢价 \($0.cnyText)" } ?? ""
            let adjustmentText = [discountText, premiumText].filter { !$0.isEmpty }.joined(separator: " · ")
            let adjustmentMarkup = adjustmentText.isEmpty ? "" : "<small>\(escape(adjustmentText))</small>"
            return "<tr><td>\(escape(date))</td><td><strong>\(escape(transaction.title))</strong><small>\(escape(transaction.note ?? ""))</small></td><td><span class=\"tag\">\(escape(transaction.categoryName ?? "未分类"))</span></td><td class=\"amount \(isExpense ? "expense" : "income")\">\(amount)\(adjustmentMarkup)</td></tr>"
        }.joined()
        return """
        <!doctype html>
        <html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(escape(book.name)) · 账本报告</title>
        <style>
        :root{color-scheme:light;--ink:#172033;--muted:#718096;--line:#e8edf5;--blue:#4f7cff;--green:#20b779;--orange:#f59a3d;--red:#e85d75}*{box-sizing:border-box}body{margin:0;background:#f4f7fb;color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","PingFang SC",sans-serif;line-height:1.5}.page{max-width:980px;margin:0 auto;padding:42px 22px 64px}.hero{padding:38px 40px;border-radius:28px;background:linear-gradient(135deg,#3867f4,#7c5ce8);color:#fff;box-shadow:0 18px 48px rgba(61,91,205,.25)}.eyebrow{opacity:.76;font-size:13px;letter-spacing:1.5px}.hero h1{margin:8px 0 5px;font-size:36px;letter-spacing:-.8px}.hero p{margin:0;opacity:.85}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:22px 0}.card,.section{background:#fff;border:1px solid var(--line);border-radius:20px;box-shadow:0 8px 25px rgba(32,55,90,.06)}.card{padding:18px}.card span{display:block;color:var(--muted);font-size:13px}.card strong{display:block;margin-top:6px;font-size:22px}.card.expense strong{color:var(--orange)}.card.income strong{color:var(--green)}.card.balance strong{color:var(--blue)}.section{padding:25px 26px;margin-top:18px}.section h2{font-size:19px;margin:0 0 18px}.category-row{margin:12px 0}.category-label{display:flex;justify-content:space-between;font-size:14px}.category-label strong{font-weight:600}.bar{height:9px;background:#edf1f7;border-radius:8px;margin-top:7px;overflow:hidden}.bar i{display:block;height:100%;border-radius:8px;background:linear-gradient(90deg,#5a83ff,#8d6df1)}.member-row{display:grid;grid-template-columns:1.3fr 1fr 1fr;padding:12px 0;border-bottom:1px solid var(--line);color:var(--muted)}.member-row:last-child{border-bottom:0}.member-row b{color:var(--ink)}.table-wrap{overflow-x:auto}table{width:100%;border-collapse:collapse;min-width:650px}th{color:var(--muted);font-size:12px;font-weight:600;text-align:left;padding:10px 12px;border-bottom:1px solid var(--line)}td{padding:14px 12px;border-bottom:1px solid var(--line);font-size:13px;vertical-align:top}td small{display:block;color:var(--muted);margin-top:3px}.tag{display:inline-block;background:#eef3ff;color:#456ee2;padding:4px 9px;border-radius:999px;font-size:12px}.amount{text-align:right;font-weight:700}.amount.expense{color:var(--orange)}.amount.income{color:var(--green)}.footer{text-align:center;color:var(--muted);font-size:12px;margin-top:26px}@media(max-width:700px){.page{padding:20px 14px 42px}.hero{padding:27px 24px;border-radius:22px}.hero h1{font-size:28px}.grid{grid-template-columns:repeat(2,1fr)}.section{padding:20px 16px}.member-row{grid-template-columns:1fr;gap:4px}}
        </style></head><body><main class="page"><header class="hero"><div class="eyebrow">SMART LEDGER · FINANCIAL REPORT</div><h1>\(escape(book.name))</h1><p>账本期间：\(escape(period)) · 共 \(transactions.count) 笔流水</p></header>
        <section class="grid"><div class="card expense"><span>总支出</span><strong>\(expense.cnyText)</strong></div><div class="card income"><span>总收入</span><strong>\(income.cnyText)</strong></div><div class="card balance"><span>净额</span><strong>\(book.balance.cnyText)</strong></div><div class="card"><span>优惠 / 溢价</span><strong>\(discount.cnyText) / \(premium.cnyText)</strong></div></section>
        <section class="section"><h2>分类支出</h2>\(categoryRows.isEmpty ? "<p style=\"color:var(--muted)\">暂无支出分类</p>" : categoryRows)</section>
        \(memberRows.isEmpty ? "" : "<section class=\"section\"><h2>分账概览</h2>\(memberRows)</section>")
        <section class="section"><h2>流水明细</h2><div class="table-wrap"><table><thead><tr><th>时间</th><th>标题 / 备注</th><th>分类</th><th style="text-align:right">金额</th></tr></thead><tbody>\(transactionRows.isEmpty ? "<tr><td colspan=\"4\">暂无流水</td></tr>" : transactionRows)</tbody></table></div></section><div class="footer">由 Smart Ledger 生成 · \(Date.now.formatted(date: .abbreviated, time: .shortened))</div></main></body></html>
        """
    }

    init(configuration: ReadConfiguration) throws { text = "" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct BookEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let book: LedgerBook?
    @State private var name: String
    @State private var note: String
    @State private var icon: String
    @State private var color: String
    @State private var isPinned: Bool
    @State private var autoCollectEnabled: Bool
    @State private var selectedCategoryIDs: Set<Int>
    @State private var budgetEnabled: Bool
    @State private var budgetText: String
    @State private var hasDateRange: Bool
    @State private var hasEndDate: Bool
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var members: [String]
    @State private var newMember = ""
    @State private var showAutoCollectSetup = false
    @State private var collectUnassignedNow = true
    @State private var keepExistingCollected = true
    @State private var showDateRangeRequiredAlert = false
    @State private var showDateRangeCollectionPrompt = false
    @State private var saveFailureMessage: String?
    @State private var autoCollectExecutionMessage: String?
    @State private var iconPickerExpanded = false

    init(book: LedgerBook?) {
        self.book = book
        _name = State(initialValue: book?.name ?? "")
        _note = State(initialValue: book?.note ?? "")
        _icon = State(initialValue: book?.icon ?? "book.closed.fill")
        _color = State(initialValue: book?.color ?? "#4F46E5")
        _isPinned = State(initialValue: book?.isPinned ?? false)
        _autoCollectEnabled = State(initialValue: book?.autoCollectEnabled ?? false)
        _selectedCategoryIDs = State(initialValue: Set(book?.autoCollectCategoryIds ?? []))
        _budgetEnabled = State(initialValue: book?.budgetEnabled ?? false)
        _budgetText = State(initialValue: book?.budgetLimitAmount.map { String($0) } ?? "")
        _hasDateRange = State(initialValue: book?.startDate != nil || book == nil)
        _hasEndDate = State(initialValue: book?.endDate != nil)
        _startDate = State(initialValue: book?.startDate ?? Date())
        _endDate = State(initialValue: book?.endDate ?? Date())
        _members = State(initialValue: book?.participantNames.isEmpty == false ? (book?.participantNames ?? []) : ["我"])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账本名称", text: $name)
                    TextField("备注", text: $note)
                    Button { iconPickerExpanded.toggle() } label: {
                        HStack { Image(systemName: icon).foregroundStyle(Color(hex: color)); VStack(alignment: .leading) { Text("图标"); Text(icon).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: iconPickerExpanded ? "chevron.up" : "chevron.down").foregroundStyle(.secondary) }
                    }.buttonStyle(.plain)
                    if iconPickerExpanded {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                            ForEach(DisplayPalette.icons, id: \.self) { option in Button { icon = option } label: { Image(systemName: option).frame(width: 32, height: 32).background(icon == option ? Color(hex: color).opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("主题颜色").font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                            ForEach(DisplayPalette.colors, id: \.self) { option in Button { color = option } label: { Circle().fill(Color(hex: option)).frame(width: 26, height: 26).overlay { if color == option { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } } }.buttonStyle(.plain) }
                        }
                    }
                    Text("图标和主题颜色仅影响界面展示，不影响记账逻辑。").font(.footnote).foregroundStyle(.secondary)
                    Toggle("置顶显示", isOn: $isPinned)
                }
                Section("账本期间") {
                    Toggle("限定账本期间", isOn: $hasDateRange)
                    if hasDateRange {
                        DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                        Toggle("设置结束日期", isOn: $hasEndDate)
                        if hasEndDate { DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date) }
                    }
                }
                Section("预算") {
                    Toggle("启用账本预算", isOn: $budgetEnabled)
                    if budgetEnabled { TextField("预算金额", text: $budgetText).keyboardType(.decimalPad) }
                }
                Section("自动归集") {
                    Toggle("自动归集范围内流水", isOn: Binding(get: { autoCollectEnabled }, set: { enabled in
                        if enabled && !hasDateRange { showDateRangeRequiredAlert = true } else if enabled && !autoCollectEnabled { showAutoCollectSetup = true } else { autoCollectEnabled = enabled }
                    }))
                    if autoCollectEnabled {
                        Text("匹配账本时间范围内的流水；可归集全部收支、全部支出、全部收入或指定分类。") .font(.caption).foregroundStyle(.secondary)
                        Button { showAutoCollectSetup = true } label: {
                            LabeledContent("自动归集分类", value: autoCollectCategorySummary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("共同记账成员") {
                    ForEach(members, id: \.self) { member in Text(member) }
                        .onDelete { members.remove(atOffsets: $0) }
                    HStack { TextField("成员昵称", text: $newMember); Button("添加") { let value = newMember.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty && !members.contains(value) { members.append(value); newMember = "" } } }
                }
            }
            .dismissKeyboardWhenTappedOutside()
            .navigationTitle(book == nil ? "新建账本" : "编辑账本")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } } } }
            .task { if store.categories.isEmpty { await store.loadCategories() } }
            .onChange(of: startDate) { _, _ in promptToCollectForDateRangeChange() }
            .onChange(of: endDate) { _, _ in promptToCollectForDateRangeChange() }
            .onChange(of: hasDateRange) { _, _ in promptToCollectForDateRangeChange() }
            .sheet(isPresented: $showAutoCollectSetup) {
                NavigationStack {
                    BookAutoCollectCategoryPicker(initialSelectedIDs: selectedCategoryIDs) { ids, keepExisting, collectUnassigned in
                        selectedCategoryIDs = ids
                        keepExistingCollected = keepExisting
                        collectUnassignedNow = collectUnassigned
                        Task { await confirmAutoCollectSetup() }
                    }
                    .environmentObject(store)
                }
            }
            .alert("需要先设置账本期间", isPresented: $showDateRangeRequiredAlert) { Button("使用今天作为开始日期") { hasDateRange = true; startDate = Date(); showAutoCollectSetup = true }; Button("暂不开启", role: .cancel) {} } message: { Text("自动归集需要账本开始日期，用于判断哪些流水属于该账本。可以先设置开始日期，结束日期可不填写。") }
            .sheet(isPresented: $showDateRangeCollectionPrompt) {
                NavigationStack {
                    Form {
                        Section("已有流水") {
                            Toggle("保留已归集到本账本的流水", isOn: $keepExistingCollected)
                            Toggle("归集全部匹配流水", isOn: $collectUnassignedNow)
                            Text("将按新的账本期间和归集分类处理流水；关闭“保留”会取消不再符合新范围的现有关联。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("按新期间归集")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("仅保存期间") { showDateRangeCollectionPrompt = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("调整并执行") { showDateRangeCollectionPrompt = false; Task { await confirmAutoCollectSetup() } }.buttonStyle(.borderedProminent) }
                    }
                }
            }
            .alert("无法保存账本", isPresented: Binding(get: { saveFailureMessage != nil }, set: { if !$0 { saveFailureMessage = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(saveFailureMessage ?? "请检查账本设置后重试。") }
            .alert("归集规则已执行", isPresented: Binding(get: { autoCollectExecutionMessage != nil }, set: { if !$0 { autoCollectExecutionMessage = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(autoCollectExecutionMessage ?? "已按当前类别和时间范围处理流水。") }
        }
    }

    private func save() async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            saveFailureMessage = "请填写账本名称。"
            return
        }
        if budgetEnabled && (Double(budgetText) == nil || (Double(budgetText) ?? 0) <= 0) {
            saveFailureMessage = "启用账本预算时，请填写大于 0 的预算金额。"
            return
        }
        let amount = budgetEnabled ? Double(budgetText) : nil
        let draft = BookDraft(name: name.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon.isEmpty ? nil : icon, note: note.isEmpty ? nil : note, color: color.isEmpty ? nil : color, startDate: hasDateRange ? startDate : nil, endDate: hasDateRange && hasEndDate ? endDate : nil, budgetLimitAmount: amount, budgetStartDate: hasDateRange ? startDate : nil, budgetEndDate: hasDateRange && hasEndDate ? endDate : nil, autoCollectEnabled: autoCollectEnabled, participantNames: members, isPinned: isPinned, autoCollectCategoryIds: Array(selectedCategoryIDs).sorted())
        // “调整并执行”已将最新草稿持久化。此时再次点页面上的保存不应静默无响应，
        // 直接关闭编辑页即可；若用户又编辑过任何字段，仍会走正常保存流程。
        if let book, isCurrentPersistedBook(book, matching: draft) {
            dismiss()
            return
        }
        store.errorMessage = nil
        if let book {
            await store.updateBook(book.id, with: draft)
            if autoCollectEnabled && store.errorMessage == nil {
                await store.applyAutoCollectRules(to: book.id, removeNonMatchingExisting: !keepExistingCollected, collectUnassignedNow: collectUnassignedNow)
            }
        } else {
            let id = await store.createBook(draft)
            if autoCollectEnabled && store.errorMessage == nil {
                await store.applyAutoCollectRules(to: id, removeNonMatchingExisting: !keepExistingCollected, collectUnassignedNow: collectUnassignedNow)
            }
        }
        if let error = store.errorMessage { saveFailureMessage = error; return }
        dismiss()
    }

    private func isCurrentPersistedBook(_ current: LedgerBook, matching draft: BookDraft) -> Bool {
        current.name == draft.name &&
        current.icon == draft.icon &&
        current.note == draft.note &&
        current.color == draft.color &&
        current.startDate == draft.startDate &&
        current.endDate == draft.endDate &&
        current.budgetLimitAmount == draft.budgetLimitAmount &&
        current.budgetStartDate == draft.budgetStartDate &&
        current.budgetEndDate == draft.budgetEndDate &&
        current.autoCollectEnabled == draft.autoCollectEnabled &&
        current.participantNames == draft.participantNames &&
        current.isPinned == draft.isPinned &&
        current.autoCollectCategoryIds.sorted() == draft.autoCollectCategoryIds.sorted()
    }

    private func confirmAutoCollectSetup() async {
        autoCollectEnabled = true
        guard let book else {
            showAutoCollectSetup = false
            return
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            saveFailureMessage = "请先填写账本名称，再执行自动归集。"
            return
        }
        if budgetEnabled && (Double(budgetText) == nil || (Double(budgetText) ?? 0) <= 0) {
            saveFailureMessage = "启用账本预算时，请填写大于 0 的预算金额。"
            return
        }

        let draft = BookDraft(name: name.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon.isEmpty ? nil : icon, note: note.isEmpty ? nil : note, color: color.isEmpty ? nil : color, startDate: hasDateRange ? startDate : nil, endDate: hasDateRange && hasEndDate ? endDate : nil, budgetLimitAmount: budgetEnabled ? Double(budgetText) : nil, budgetStartDate: hasDateRange ? startDate : nil, budgetEndDate: hasDateRange && hasEndDate ? endDate : nil, autoCollectEnabled: true, participantNames: members, isPinned: isPinned, autoCollectCategoryIds: Array(selectedCategoryIDs).sorted())
        store.errorMessage = nil
        await store.updateBook(book.id, with: draft)
        if store.errorMessage == nil {
            await store.applyAutoCollectRules(to: book.id, removeNonMatchingExisting: !keepExistingCollected, collectUnassignedNow: collectUnassignedNow)
        }
        if let error = store.errorMessage {
            saveFailureMessage = error
        } else {
            showAutoCollectSetup = false
            autoCollectExecutionMessage = "已保存归集分类，并按当前规则处理已有流水。"
        }
    }

    private func promptToCollectForDateRangeChange() {
        guard book != nil, autoCollectEnabled, hasDateRange else { return }
        keepExistingCollected = true
        collectUnassignedNow = true
        showDateRangeCollectionPrompt = true
    }

    private var autoCollectCategorySummary: String {
        if selectedCategoryIDs.isEmpty { return "全部收支" }
        if selectedCategoryIDs == [-1] { return "全部支出" }
        if selectedCategoryIDs == [-2] { return "全部收入" }
        return "已选 \(selectedCategoryIDs.filter { $0 > 0 }.count) 项"
    }
}
private struct BookAutoCollectCategoryPicker: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let onCommit: (Set<Int>, Bool, Bool) -> Void
    @State private var selectedIDs: Set<Int>
    @State private var flowFilter: AutoCollectFlowFilter = .all
    @State private var showingExecutionConfirmation = false
    @State private var keepExistingCollected = true
    @State private var collectUnassignedNow = true

    init(initialSelectedIDs: Set<Int>, onCommit: @escaping (Set<Int>, Bool, Bool) -> Void) {
        self.onCommit = onCommit
        _selectedIDs = State(initialValue: initialSelectedIDs)
    }

    private var rootCategories: [LedgerCategory] { store.categories.sorted { $0.name < $1.name } }
    private var displayedRoots: [LedgerCategory] {
        rootCategories.filter { flowFilter == .all || $0.flowType == flowFilter.flowType }
    }
    var body: some View {
        List {
            Section {
                Button("全部收支") { selectedIDs.removeAll() }
                    .foregroundStyle(selectedIDs.isEmpty ? .blue : .primary)
                Button("全部支出") { selectedIDs = [-1] }
                    .foregroundStyle(selectedIDs == [-1] ? .blue : .primary)
                Button("全部收入") { selectedIDs = [-2] }
                    .foregroundStyle(selectedIDs == [-2] ? .blue : .primary)
            } header: {
                Text("选择“全部支出”或“全部收入”会按收支类型归集；选择分类时仅归集对应分类。")
            }

            Section {
                Picker("收支类型", selection: $flowFilter) {
                    ForEach(AutoCollectFlowFilter.allCases) { filter in Text(filter.title).tag(filter) }
                }
                .pickerStyle(.segmented)
            }

            Section(flowFilter == .all ? "全部分类" : flowFilter.title) {
                ForEach(displayedRoots) { root in
                    if root.children.isEmpty {
                        rootRow(root)
                    } else {
                        NavigationLink {
                            AutoCollectCategoryBranchPicker(
                                category: root,
                                selectedIDs: $selectedIDs,
                                rootID: root.id
                            )
                        } label: {
                            hierarchyRow(root)
                        }
                    }
                }
            }
        }
        .navigationTitle("自动归集分类")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { showingExecutionConfirmation = true } }
        }
        .sheet(isPresented: $showingExecutionConfirmation) {
            NavigationStack {
                Form {
                    Section("已有流水") {
                        Toggle("保留已归集到本账本的流水", isOn: $keepExistingCollected)
                        Toggle("归集全部匹配流水", isOn: $collectUnassignedNow)
                        Text("默认会将符合期间与类别、但尚未关联当前账本的流水全部归集；关闭“保留”会移除不再符合规则的现有关联。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("确认并执行")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("返回修改") { showingExecutionConfirmation = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("调整并执行") {
                            onCommit(selectedIDs, keepExistingCollected, collectUnassignedNow)
                            showingExecutionConfirmation = false
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func rootRow(_ root: LedgerCategory) -> some View {
        Button { toggleRoot(root) } label: {
            HStack(spacing: 10) {
                Image(systemName: root.icon ?? "folder.fill").foregroundStyle(Color(hex: root.color ?? "#4F46E5"))
                Text(root.name).foregroundStyle(.primary)
                Spacer()
                if selectedIDs.contains(root.id) {
                    Text(root.children.isEmpty ? "已选" : "包含子类").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hierarchyRow(_ category: LedgerCategory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: category.icon ?? "folder.fill").foregroundStyle(Color(hex: category.color ?? "#4F46E5"))
                .frame(width: 28, height: 28).background(Color(hex: category.color ?? "#4F46E5").opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).foregroundStyle(.primary)
                Text("包含 \(category.children.count) 个子分类").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if selectedIDs.contains(category.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func toggleRoot(_ root: LedgerCategory) {
        selectedIDs.remove(-1)
        selectedIDs.remove(-2)
        if selectedIDs.contains(root.id) {
            selectedIDs.remove(root.id)
        } else {
            selectedIDs.subtract(root.flattened().map(\.id))
            selectedIDs.insert(root.id)
        }
    }

}

/// The same one-level-at-a-time interaction used by the transaction picker.
/// It avoids expanding a third level into an unreadable single list.
private struct AutoCollectCategoryBranchPicker: View {
    let category: LedgerCategory
    @Binding var selectedIDs: Set<Int>
    let rootID: Int

    var body: some View {
        List {
            Section("当前分类") {
                Button { toggle(category, includeDescendants: true) } label: { row(category, hierarchy: false) }
                    .buttonStyle(.plain)
            }
            Section("下级分类") {
                ForEach(category.children) { child in
                    if child.children.isEmpty {
                        Button { toggle(child, includeDescendants: false) } label: { row(child, hierarchy: false) }
                            .buttonStyle(.plain)
                    } else {
                        NavigationLink { AutoCollectCategoryBranchPicker(category: child, selectedIDs: $selectedIDs, rootID: rootID) } label: { row(child, hierarchy: true) }
                    }
                }
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ item: LedgerCategory, includeDescendants: Bool) {
        selectedIDs.remove(-1); selectedIDs.remove(-2)
        if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
        else {
            if item.id != rootID { selectedIDs.remove(rootID) }
            if includeDescendants { selectedIDs.subtract(item.flattened().map(\.id)) }
            selectedIDs.insert(item.id)
        }
    }

    private func row(_ item: LedgerCategory, hierarchy: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon ?? "tag.fill").foregroundStyle(Color(hex: item.color ?? "#4F46E5"))
                .frame(width: 28, height: 28).background(Color(hex: item.color ?? "#4F46E5").opacity(0.14), in: Circle())
            Text(item.name).foregroundStyle(.primary)
            Spacer()
            if selectedIDs.contains(item.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
            else if hierarchy { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private enum AutoCollectFlowFilter: String, CaseIterable, Identifiable {
    case all, expense, income
    var id: String { rawValue }
    var title: String { self == .all ? "全部" : (self == .expense ? "支出" : "收入") }
    var flowType: FlowType? { self == .expense ? .expense : (self == .income ? .income : nil) }
}
/*
        selectedIDs.subtract(root.flattened().map(\.id))
            selectedIDs.insert(root.id)
            expandedRootIDs.remove(root.id)
        }
    }

    private func toggleChild(_ child: LedgerCategory) {
        if selectedIDs.contains(child.id) { selectedIDs.remove(child.id) } else { selectedIDs.insert(child.id) }
    }
}
*/
/*
s.remove(child.id) } else { selectedIDs.insert(child.id) }
    }
}
*/
