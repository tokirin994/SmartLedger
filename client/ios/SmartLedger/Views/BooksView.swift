import SwiftUI

struct BooksView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var showingCreate = false
    @State private var selectedBook: LedgerBook?

    var body: some View {
        NavigationStack {
            Group {
                if store.books.isEmpty {
                    ContentUnavailableView("暂无账本", systemImage: "books.vertical", description: Text("点击右上角新建账本"))
                } else {
                    List {
                        ForEach(store.books, id: \.id) { book in
                            Button { selectedBook = book } label: { BookRow(book: book) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { Task { await store.setBookPinned(book.id, pinned: !book.isPinned) } } label: {
                                        Label(book.isPinned ? "取消置顶" : "置顶", systemImage: book.isPinned ? "pin.slash" : "pin")
                                    }.tint(.orange)
                                }
                                .swipeActions {
                                    Button(role: .destructive) { Task { await store.deleteBook(book.id) } } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("账本")
            .toolbar { Button { showingCreate = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $showingCreate) { BookEditorView(book: nil).environmentObject(store) }
            .sheet(item: $selectedBook) { book in BookDetailView(book: book).environmentObject(store) }
            .task { await store.loadBooks() }
        }
    }
}

private struct BookRow: View {
    let book: LedgerBook
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: book.icon ?? "book.closed.fill")
                .font(.title3).foregroundStyle(Color(hex: book.color ?? "#4F46E5"))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(book.name).font(.headline); if book.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) } }
                Text(book.note ?? "未填写说明").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("流水 \(book.transactionCount) 笔 · 余额 \(book.balance.cnyText)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(.vertical, 5)
    }
}

private struct BookDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let book: LedgerBook
    @State private var showingEditor = false

    private var current: LedgerBook { store.books.first(where: { $0.id == book.id }) ?? book }
    var body: some View {
        NavigationStack {
            List {
                Section("概览") {
                    LabeledContent("流水数量", value: "\(current.transactionCount) 笔")
                    LabeledContent("收入", value: current.incomeAmount.cnyText)
                    LabeledContent("支出", value: current.expenseAmount.cnyText)
                    LabeledContent("结余", value: current.balance.cnyText)
                }
                Section("高级规则") {
                    LabeledContent("自动归集", value: current.autoCollectEnabled ? "已启用" : "未启用")
                    LabeledContent("归集分类", value: current.autoCollectCategoryIds.isEmpty ? "全部分类" : "\(current.autoCollectCategoryIds.count) 个分类")
                    LabeledContent("预算", value: current.budgetEnabled ? (current.budgetLimitAmount ?? 0).cnyText : "未设置")
                    LabeledContent("成员", value: current.participantNames.isEmpty ? "仅自己" : current.participantNames.joined(separator: "、"))
                }
                if let start = current.startDate { Section("账本期间") { LabeledContent("开始", value: start.formatted(date: .abbreviated, time: .omitted)); if let end = current.endDate { LabeledContent("结束", value: end.formatted(date: .abbreviated, time: .omitted)) } } }
            }
            .navigationTitle(current.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("编辑") { showingEditor = true } }
            }
            .sheet(isPresented: $showingEditor) { BookEditorView(book: current).environmentObject(store) }
        }
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
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var members: [String]
    @State private var newMember = ""

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
        _members = State(initialValue: book?.participantNames ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账本名称", text: $name)
                    TextField("备注", text: $note)
                    TextField("图标（SF Symbol）", text: $icon)
                    TextField("颜色（Hex）", text: $color)
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
                    Toggle("按分类自动归集流水", isOn: $autoCollectEnabled)
                    if autoCollectEnabled {
                        Text("未选择分类时，将匹配全部分类。") .font(.caption).foregroundStyle(.secondary)
                        ForEach(store.categories.flatMap { $0.leafFlattened() }, id: \.id) { category in
                            Toggle(category.displayName, isOn: Binding(get: { selectedCategoryIDs.contains(category.id) }, set: { enabled in if enabled { selectedCategoryIDs.insert(category.id) } else { selectedCategoryIDs.remove(category.id) } }))
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
        }
    }

    private func save() async {
        let amount = budgetEnabled ? Double(budgetText) : nil
        let draft = BookDraft(name: name.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon.isEmpty ? nil : icon, note: note.isEmpty ? nil : note, color: color.isEmpty ? nil : color, startDate: hasDateRange ? startDate : nil, endDate: hasDateRange ? endDate : nil, budgetLimitAmount: amount, budgetStartDate: hasDateRange ? startDate : nil, budgetEndDate: hasDateRange ? endDate : nil, autoCollectEnabled: autoCollectEnabled, participantNames: members, isPinned: isPinned, autoCollectCategoryIds: Array(selectedCategoryIDs).sorted())
        if let book { await store.updateBook(book.id, with: draft) } else { _ = await store.createBook(draft) }
        dismiss()
    }
}