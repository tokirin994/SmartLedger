import SwiftUI

// MARK: - BooksView（图252-254）
struct BooksView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var searchText: String = ""
    @State private var showingNewBook: Bool = false
    @State private var bookToDelete: LedgerBook?

    // 图252：NavigationStack + 搜索栏 + TextField + 放大镜 + 清除按钮
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                contentList
            }
            .navigationTitle("账本")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewBook = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewBook) {
                BookEditor(book: nil)
            }
            .alert("删除账本？", isPresented: Binding(
                get: { bookToDelete != nil },
                set: { if !$0 { bookToDelete = nil } }
            )) {
                Button("删除", role: .destructive) {
                    if let book = bookToDelete {
                        store.deleteBook(book)
                    }
                    bookToDelete = nil
                }
                Button("取消", role: .cancel) {
                    bookToDelete = nil
                }
            } message: {
                Text("删除后该账本下的所有流水将被一并清除，此操作不可撤销。")
            }
            // 图254：Task await store.loadBooks()
            .task {
                await store.loadBooks()
            }
        }
    }

    // MARK: - 搜索栏（图252）
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("搜索账本", text: $searchText)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - 列表（图253）
    @ViewBuilder
    private var contentList: some View {
        let filtered = store.books.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }

        if filtered.isEmpty {
            ContentUnavailableView("没有匹配的账本", systemImage: "book.closed")
        } else {
            List {
                Section("账本") {
                    ForEach(filtered) { book in
                        NavigationLink(value: book) {
                            BookRow(book: book)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // 图253：取消置顶 + 删除 + 橙色 tint
                            if store.pinnedBookIDs.contains(book.id) {
                                Button {
                                    store.unpinBook(book)
                                } label: {
                                    Label("取消置顶", systemImage: "pin.slash")
                                }
                                .tint(.orange)
                            }
                            Button(role: .destructive) {
                                bookToDelete = book
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

// MARK: - BookRow（图255-256）
struct BookRow: View {
    let book: LedgerBook

    var body: some View {
        HStack(spacing: 12) {
            // 图256：Circle + Image(systemName:) + foregroundStyle + pill()
            Circle()
                .fill(book.color.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: book.iconName)
                        .foregroundStyle(book.color)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(book.name)
                    .font(.headline)
                // 图255：.blue / .orange / .green + "账本数"/"主题支出"/"主题收入"
                HStack(spacing: 6) {
                    Text("\(book.transactionCount) 笔")
                        .foregroundStyle(.blue)
                    Text("支出 \(book.expenseAmount.compactMoney)")
                        .foregroundStyle(.orange)
                    Text("收入 \(book.incomeAmount.compactMoney)")
                        .foregroundStyle(.green)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // 图256：book.balance / dateRangeText
            VStack(alignment: .trailing, spacing: 4) {
                Text(book.balance.compactMoney)
                    .font(.subheadline.weight(.semibold))
                Text(dateRangeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // 图257："起始于" + 日期区间格式化
    private var dateRangeText: String {
        guard let start = book.earliestDate, let end = book.latestDate else {
            return "暂无交易"
        }
        let df: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy.MM.dd"
            return f
        }()
        return "起始于 \(df.string(from: start)) – \(df.string(from: end))"
    }
}

// MARK: - BookDetailView（图257）
struct BookDetailView: View {
    let book: LedgerBook
    @EnvironmentObject var store: LedgerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BookRow(book: book)
                    .padding()
                    .glassCard(cornerRadius: 16)

                // 图257：private func + @State
                SectionCard(title: "统计概览") {
                    HStack {
                        Text("总笔数：\(book.transactionCount)")
                        Spacer()
                        Text("结余：\(book.balance.compactMoney)")
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - BookEditor（图258）
struct BookEditor: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    // 图258：@State + init + NavigationStack + Form + TextField + VStack + Button + Circle + Image(systemName:)
    @State private var name: String
    @State private var selectedColor: Color
    @State private var selectedIcon: String

    private let isNew: Bool

    init(book: LedgerBook?) {
        if let book {
            _name = State(initialValue: book.name)
            _selectedColor = State(initialValue: book.color)
            _selectedIcon = State(initialValue: book.iconName)
            isNew = false
        } else {
            _name = State(initialValue: "")
            _selectedColor = State(initialValue: .accentColor)
            _selectedIcon = State(initialValue: "book.fill")
            isNew = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账本名称", text: $name)
                }
                Section("外观") {
                    ColorPicker("主题色", selection: $selectedColor)
                    iconPicker
                }
            }
            .navigationTitle(isNew ? "新建账本" : "编辑账本")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save(); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // 图258：Circle + Image(systemName:) 图标选择器
    @ViewBuilder
    private var iconPicker: some View {
        let icons = ["book.fill", "cart.fill", "creditcard.fill", "house.fill", "car.fill"]
        VStack(alignment: .leading, spacing: 8) {
            Text("图标")
            HStack(spacing: 12) {
                ForEach(icons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Circle()
                            .fill(selectedIcon == icon ? selectedColor.opacity(0.2) : Color(.secondarySystemBackground))
                            .frame(width: 36, height: 36)
                            .overlay {
                                Image(systemName: icon)
                                    .foregroundStyle(selectedIcon == icon ? selectedColor : .gray)
                            }
                    }
                }
            }
        }
    }

    private func save() {
        // 以原图为准
    }
}
