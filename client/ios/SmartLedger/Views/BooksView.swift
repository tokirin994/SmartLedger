import SwiftUI

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
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: book.icon ?? "book.closed.fill")
                .font(.title3.weight(.semibold)).foregroundStyle(Color(hex: book.color ?? "#4F46E5"))
                .frame(width: 44, height: 44)
                .background(Color(hex: book.color ?? "#4F46E5").opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(book.name).font(.headline); if book.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) } }
                Text(book.note ?? "未填写说明").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) { Label("\(book.transactionCount)", systemImage: "list.bullet"); Text("净额 \(book.balance.cnyText)") }
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(hex: book.color ?? "#4F46E5").opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: book.color ?? "#4F46E5").opacity(0.14), lineWidth: 1) }
        .padding(.vertical, 3)
    }
}

private struct BookDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let book: LedgerBook
    @State private var showingEditor = false
    @State private var deleteRequested = false

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
                    if !current.participantNames.isEmpty { Text("分账成员").font(.caption).foregroundStyle(.secondary); ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(current.participantNames, id: \.self) { Text($0).padding(.horizontal, 11).padding(.vertical, 6).background(.blue.opacity(0.1), in: Capsule()) } } } }
                }.padding().glassCard(cornerRadius: 20, strokeOpacity: 0.15)
                if current.budgetEnabled { budgetCard }
                if !splitTransactions.isEmpty { splitCard }
                transactionsCard
            }.padding()
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(current.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Button("设置") { showingEditor = true }; Button(current.isPinned ? "取消置顶" : "置顶") { Task { await store.setBookPinned(current.id, pinned: !current.isPinned) } }; Button("删除账本", role: .destructive) { deleteRequested = true } } label: { Image(systemName: "gearshape") } } }
        .sheet(isPresented: $showingEditor) { BookEditorView(book: current).environmentObject(store) }
        .alert("删除账本？", isPresented: $deleteRequested) { Button("取消", role: .cancel) {}; Button("删除", role: .destructive) { Task { await store.deleteBook(current.id) }; dismiss() } } message: { Text("删除账本不会删除流水，只会移除关联。") }
    }

    private var budgetCard: some View { let limit = current.budgetLimitAmount ?? 0; let remaining = limit - current.expenseAmount; return VStack(alignment: .leading, spacing: 12) { Text("账本预算").font(.title3.bold()); HStack(spacing: 10) { metric("预算", limit.cnyText, .blue); metric("已用", current.expenseAmount.cnyText, .orange); metric("剩余", remaining.cnyText, remaining < 0 ? .red : .green) }; ProgressView(value: min(max(current.expenseAmount / max(limit, 1), 0), 1)).tint(remaining < 0 ? .red : .blue); Text("预算周期：\(periodText)").font(.caption).foregroundStyle(.secondary) }.padding().glassCard(cornerRadius: 20, strokeOpacity: 0.15) }
    private var splitCard: some View { VStack(alignment: .leading, spacing: 14) { Text("最终分账").font(.title3.bold()); ForEach(current.participants) { member in let paid = splitTransactions.filter { $0.paidByParticipantId == member.id }.reduce(0) { $0 + $1.amount }; let owed = splitTransactions.filter { $0.splitParticipantIds.contains(member.id) }.reduce(0) { $0 + $1.amount / Double(max($1.splitParticipantIds.count, 1)) }; let net = paid - owed; VStack(alignment: .leading, spacing: 8) { HStack { Text(member.name).font(.headline); Spacer(); Text(net >= 0 ? "应收 \(net.cnyText)" : "应付 \((-net).cnyText)").foregroundStyle(net >= 0 ? .green : .orange) }; HStack(spacing: 10) { metric("已支付", paid.cnyText, .blue); metric("应承担", owed.cnyText, .purple) } } } }.padding().glassCard(cornerRadius: 20, strokeOpacity: 0.15) }
    private var transactionsCard: some View { VStack(alignment: .leading, spacing: 10) { HStack { Text("归集流水").font(.title3.bold()); Spacer(); Text("\(relatedTransactions.count) 笔").font(.caption).foregroundStyle(.secondary) }; if relatedTransactions.isEmpty { ContentUnavailableView("暂无归集流水", systemImage: "tray") }; ForEach(relatedTransactions) { tx in HStack(spacing: 12) { Image(systemName: tx.kind == .expense ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill").font(.title3).foregroundStyle(tx.kind == .expense ? .orange : .green).frame(width: 30); VStack(alignment: .leading, spacing: 4) { Text(tx.title).font(.subheadline.weight(.semibold)); HStack(spacing: 6) { Text(tx.categoryName ?? "未分类"); Text("·"); Text(tx.happenedAt.formatted(date: .abbreviated, time: .shortened)) }.font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(transactionAmountText(tx)).font(.subheadline.weight(.bold)).foregroundStyle(transactionAmountColor(tx)) }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1) }.contextMenu { Button(role: .destructive) { Task { await store.removeTransaction(tx.id, from: current.id) } } label: { Label("从账本剔除", systemImage: "minus.circle") } } } } }
    private var periodText: String { guard let start = current.startDate else { return "未限定" }; let begin = start.formatted(date: .abbreviated, time: .omitted); return current.endDate.map { "\(begin) - \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "自 \(begin) 起" }
    private func metric(_ title: String, _ value: String, _ color: Color) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.bold()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65) }.frame(maxWidth: .infinity, minHeight: 62, alignment: .leading).padding(10).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12)) }
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
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var members: [String]
    @State private var newMember = ""
    @State private var showAutoCollectSetup = false
    @State private var collectExistingNow = false
    @State private var autoCollectScopeConfirmed = false
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
        _hasDateRange = State(initialValue: book?.startDate != nil)
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
                    if hasDateRange { DatePicker("开始日期", selection: $startDate, displayedComponents: .date); DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date) }
                }
                Section("预算") {
                    Toggle("启用账本预算", isOn: $budgetEnabled)
                    if budgetEnabled { TextField("预算金额", text: $budgetText).keyboardType(.decimalPad) }
                }
                Section("自动归集") {
                    Toggle("自动归集范围内流水", isOn: Binding(get: { autoCollectEnabled }, set: { enabled in
                        if enabled && !hasDateRange { autoCollectEnabled = false } else if enabled && !autoCollectEnabled { showAutoCollectSetup = true } else { autoCollectEnabled = enabled }
                    }))
                    if autoCollectEnabled {
                        Text("仅匹配账本时间范围内的支出流水；未选分类表示全部分类。") .font(.caption).foregroundStyle(.secondary)
                        NavigationLink { BookAutoCollectCategoryPicker(selectedIDs: $selectedCategoryIDs).environmentObject(store) } label: {
                            LabeledContent("自动归集分类", value: selectedCategoryIDs.isEmpty ? "全部分类" : "已选 \(selectedCategoryIDs.count) 项")
                        }
                    }
                }
                Section("共同记账成员") {
                    ForEach(members, id: \.self) { member in Text(member) }
                        .onDelete { members.remove(atOffsets: $0) }
                    HStack { TextField("成员昵称", text: $newMember); Button("添加") { let value = newMember.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty && !members.contains(value) { members.append(value); newMember = "" } } }
                }
            }
            .navigationTitle(book == nil ? "新建账本" : "编辑账本")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
            .task { if store.categories.isEmpty { await store.loadCategories() } }
            .sheet(isPresented: $showAutoCollectSetup) {
                NavigationStack { Form { Section { Text("请先确认归集范围。开启后，新流水会按账本日期范围及所选分类自动归入本账本。").foregroundStyle(.secondary) }; Section("归集类别") { NavigationLink { BookAutoCollectCategoryPicker(selectedIDs: $selectedCategoryIDs).environmentObject(store) } label: { LabeledContent("归集分类", value: selectedCategoryIDs.isEmpty ? "全部支出分类" : "已选 \(selectedCategoryIDs.count) 项") }; Toggle("我已确认归集类别", isOn: $autoCollectScopeConfirmed) }; Section("历史流水") { Toggle("立即全量归集现有符合条件的流水", isOn: $collectExistingNow); Text("不勾选则只对之后新增的流水生效。") .font(.footnote).foregroundStyle(.secondary) } }.navigationTitle("开启自动归集").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showAutoCollectSetup = false } }; ToolbarItem(placement: .confirmationAction) { Button("确认开启") { autoCollectEnabled = true; showAutoCollectSetup = false }.disabled(!autoCollectScopeConfirmed) } } }
            }
        }
    }

    private func save() async {
        let amount = budgetEnabled ? Double(budgetText) : nil
        let draft = BookDraft(name: name.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon.isEmpty ? nil : icon, note: note.isEmpty ? nil : note, color: color.isEmpty ? nil : color, startDate: hasDateRange ? startDate : nil, endDate: hasDateRange ? endDate : nil, budgetLimitAmount: amount, budgetStartDate: hasDateRange ? startDate : nil, budgetEndDate: hasDateRange ? endDate : nil, autoCollectEnabled: autoCollectEnabled, participantNames: members, isPinned: isPinned, autoCollectCategoryIds: Array(selectedCategoryIDs).sorted())
        if let book { await store.updateBook(book.id, with: draft); if collectExistingNow { await store.collectTransactionsIntoBook(book.id) } } else { let id = await store.createBook(draft); if collectExistingNow { await store.collectTransactionsIntoBook(id) } }
        dismiss()
    }
}
private struct BookAutoCollectCategoryPicker: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var selectedIDs: Set<Int>
    var body: some View { List { Section { Button("全部分类") { selectedIDs.removeAll() }.foregroundStyle(selectedIDs.isEmpty ? .blue : .primary) }; Section("支出分类") { ForEach(store.selectableCategories(for: .expense)) { category in Button { if selectedIDs.contains(category.id) { selectedIDs.remove(category.id) } else { selectedIDs.insert(category.id) } } label: { HStack { Text(category.displayName); Spacer(); if selectedIDs.contains(category.id) { Image(systemName: "checkmark").foregroundStyle(.blue) } } } } } }.navigationTitle("自动归集分类") }
}
