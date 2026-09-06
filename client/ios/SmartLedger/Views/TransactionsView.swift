import SwiftUI
import SwiftData

struct TransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var navPath = NavigationPath()
    @State private var showAddSheet = false
    @State private var editingTransaction: LedgerTransaction?
    @State private var pendingDeleteTransaction: LedgerTransaction?
    @State private var showFilter = false
    @State private var selectedCategoryId: Int?
    @State private var selectedDateScope: TransactionDateScope = .recent30Days
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate = Date()

    var body: some View {
        Group {
            if filteredTransactions.isEmpty {
                ContentUnavailableView("暂无流水", systemImage: "list.bullet.rectangle.portrait")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(groupedTransactions, id: \.key) { group in
                        Section(header: Text(group.key)) {
                            ForEach(group.items, id: \.id) { tx in
                                TransactionRow(tx: tx)
                                    .onTapGesture {
                                        editingTransaction = tx
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("编辑", role: .none) {
                                            editingTransaction = tx
                                        }
                                        Button("删除", role: .destructive) {
                                            pendingDeleteTransaction = tx
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .appBackdrop()
            }
        }
        .navigationTitle("流水")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showFilter = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CreateTransactionView(transaction: nil)
                .environmentObject(store)
        }
        .sheet(item: $editingTransaction) { tx in
            EditTransactionView(transaction: tx)
                .environmentObject(store)
        }
        .alert("删除确认", isPresented: Binding(get: { pendingDeleteTransaction != nil }, set: { _ in pendingDeleteTransaction = nil })) {
            Button("删除", role: .destructive) {
                if let tx = pendingDeleteTransaction {
                    Task { await store.deleteTransaction(tx.id) }
                }
                pendingDeleteTransaction = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认删除该记录？")
        }
        .onAppear {
            Task {
                if store.transactions.isEmpty {
                    await store.loadTransactions()
                }
                await store.refreshOverview(range: store.activeRangePhase, granularity: store.activeGranularity)
            }
        }
    }

    private var groupedTransactions: [(key: String, items: [LedgerTransaction])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        let groups = Dictionary(grouping: filteredTransactions) { formatter.string(from: $0.happenedAt) }
        return groups.sorted { $0.key > $1.key }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Filter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedFilter == filter ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedFilter == filter ? Color.blue : Color.white.opacity(0.10), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var categoryFilterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("全部分类") {
                    selectedCategoryId = nil
                }
                Spacer()
                Menu {
                    ForEach(Category.transactionRootOptions) { category in
                        Button(category.name) {
                            selectedCategoryId = category.id
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedCategoryTitle)
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Text("时间范围")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedDateScope) {
                    ForEach(TransactionDateScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                if selectedDateScope == .custom {
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                    Text("至")
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                }
            }
            .onChange(of: selectedCategoryId) { _, _ in
                Task { await reloadTransactions() }
            }
            .onChange(of: selectedDateScope) { _, _ in
                Task { await reloadTransactions() }
            }
        }
        .padding(.horizontal, 16)
    }

    private var summaryHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                compactStat(title: "收入", value: totalIncome.cnfText, tint: .green)
                compactStat(title: "支出", value: totalExpense.cnfText, tint: .red)
                compactStat(title: "余额", value: netAmount.cnfText, tint: netAmount >= 0 ? .blue : .red)
            }
            .padding(.vertical, 6)
        }
    }

    private func compactStat(title: String, value: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
        }
    }

    private func transactionRow(_ tx: LedgerTransaction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(badgeColor(for: tx.categoryId))
                    .frame(width: 42, height: 42)
                Image(systemName: categoryIcon(for: tx.categoryId))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(tx.title)
                    .font(.headline.weight(.semibold))
                Text(tx.happenedAt.cnfText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if tx.source == "ocr" {
                    Label("OCR", systemImage: "camera.viewfinder", tint: .blue)
                }
                if tx.installmentMonths != nil {
                    Label("分期", systemImage: "repeat.circle", tint: .orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(tx.kind == .expense ? "-" : "+")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tx.kind == .expense ? .red : .green)
                if let original = tx.originalAmount {
                    if original > tx.amount {
                        Text("原价:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(original.cnfText)
                            .font(.caption)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        if let discount = tx.discountAmount, discount > 0 {
                            Text("优惠:")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(discount.cnfText)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        if let premium = tx.premiumAmount, premium > 0 {
                            Text("溢价:")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text(premium.cnfText)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            if let merchant = tx.merchant {
                HStack(spacing: 6) {
                    Image(systemName: "storefront")
                    Text(merchant)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let paymentMethod = tx.paymentMethod, paymentMethod != "manual" {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.fill")
                    Text(paymentMethod)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if tx.discountAmount != nil || tx.premiumAmount != nil || tx.originalAmount != nil {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                    Text("详情")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .glassBackground(cornerRadius: 22, strokeOpacity: 0.22)
    }

    private func infoPill(title: String, systemImage: String, trailingText: String, tint: Color = .primary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
            Spacer()
            Text(trailingText)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.14), in: Capsule())
    }

    private func amountPill(title: String, value: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.14), in: Capsule())
    }
}
       let sign = tx.kind == .income ? "+" : "-"
       return "\(sign)\(tx.amount.cnfText)"
   }
   private func installmentText(for tx: LedgerTransaction) -> String {
       if let index = tx.installmentIndex, let months = tx.installmentMonths {
           return "分期 (\(index)/\(months))"
       }
       return "分期"
   }
   private func badgeIcon(for tx: LedgerTransaction) -> String {
       if tx.kind == .income {
           return "arrow.down.left"
       }
       if tx.installmentMonths != nil {
           return "repeat.circle"
       }
       if tx.source == "ocr" {
           return "camera.viewfinder"
       }
       return "arrow.up.right"
   }
   private func categoryIcon(for tx: LedgerTransaction) -> String {
       if let categoryId = tx.categoryId {
           let category = store.flattenedCategories.first(where: { $0.id == categoryId })
           return category?.icon ?? "square.grid.2x2"
       }
       return "square.grid.2x2"
   }
   private func badgeColor(for tx: LedgerTransaction) -> Color {
       tx.kind == .income ? .green : (tx.installmentMonths != nil ? .orange : .accentColor)
   }
   private func displayBookNames(for tx: LedgerTransaction) -> [String] {
       let names = tx.bookNames ?? []
       var seen = Set<String>()
       return names.filter { seen.insert($0).inserted }
   }
   private var filteredTransactions: [LedgerTransaction] {
       let start = Calendar.current.startOfDay(for: startDate)
       let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate))!
       var result = store.transactions.filter { $0.happenedAt >= start && $0.happenedAt < end }
       if let selectedCategoryId = selectedCategoryId {
           result = result.filter { transaction in
               guard let category = store.flattenedCategories.first(where: { $0.id == transaction.categoryId }) else { return false }
               return categoryMatchesFilter(transactionCategoryId: categoryId, selectedCategoryId: selectedCategoryId)
           }
       }
       switch selectedFlow {
       case .all:
           return result
       case .expense:
           return result.filter { $0.kind == .expense }
       case .income:
           return result.filter { $0.kind == .income }
       }
   }
   private var categoryFilterOptions: [LedgerCategory] {
       var flattened = store.flattenedCategories.filter { category in
           switch category.flowType {
           case .expense: return true
           case .income: return true
           }
       }
       flattened.sort { lhs, rhs in
           if lhs.level == rhs.level {
               return lhs.name < rhs.name
           }
           return lhs.level < rhs.level
       }
       return flattened
   }
   private var selectedCategoryTitle: String {
       guard let selectedCategoryId = selectedCategoryId else { return "全部分类" }
       let category = store.flattenedCategories.first(where: { $0.id == selectedCategoryId }) else { return "全部分类" }
       return category.name
   }
   private func filterChip(title: String, systemImage: String?, isSelected: Bool) -> some View {
       HStack(spacing: 4) {
           if let systemImage = systemImage {
               Image(systemName: systemImage)
           }
           Text(title)
               .font(.subheadline.weight(.semibold))
       }
       .padding(.horizontal, 12)
       .padding(.vertical, 8)
       .background(filterChipBackground, in: Capsule())
       .overlay(
           RoundedRectangle(cornerRadius: 12, style: .continuous)
               .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.28), lineWidth: 1)
       )
   }
   private var filterChipBackground: Color {
       colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
   }
   private var groupHeaderBackground: Color {
       colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.84)
   }
   private var calendarMonthBackground: Color {
       colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
   }
   private var calendarHeaderBackground: Color {
       colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.80)
   }
   private var filterBackground: Color {
       colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
   }
   private func categoryMatchesFilter(transactionCategoryId: Int, selectedCategoryId: Int) -> Bool {
       guard let transactionCategory = store.flattenedCategories.first(where: { $0.id == transactionCategoryId }) else { return false }
       guard let selectedCategory = store.flattenedCategories.first(where: { $0.id == selectedCategoryId }) else { return false }
       return transactionCategory.pathComponents.starts(with: selectedCategory.pathComponents)
   }
   private func groupTransactionsByDate(_ transactions: [LedgerTransaction]) -> [TransactionDayGroup] {
       let grouped = Dictionary(grouping: transactions) { tx in
           Calendar.current.startOfDay(for: tx.happenedAt)
       }
       return grouped.map { date, items in
           let total = items.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
               - items.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
           return TransactionDayGroup(date: date, title: date.formatted(date: .abbreviated, time: .omitted), total: total, items: items.sorted { $0.happenedAt > $1.happenedAt })
       }
       .sorted { $0.dateKey > $1.dateKey }
   }
   private var totalIncome: Double {
       filteredTransactions.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
   }
   private var totalExpense: Double {
       filteredTransactions.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
   }
   private var netAmount: Double {
       totalIncome - totalExpense
   }
   private func reloadTransactions() async {
       await store.refreshOverview(range: store.activeDateRange, granularity: store.activeGranularity)
   }
   @EnvironmentObject private var store: LedgerStore
   @Binding var transaction: LedgerTransaction?
   @State private var dismiss = false
   var body: some View {
       NavigationStack {
           List {
               Section {
                   Button("全部分类") {
                       selectedCategoryId = nil
                   }
               }
               Section("账本") {
                   ForEach(store.books) { book in
                       Button {
                           if store.associatedBooks.contains(where: { $0.id == book.id }) {
                               await store.removeTransaction(transactionId: transaction?.id ?? 0, from: book.id)
                           } else {
                               await store.assignTransaction(transactionId: transaction?.id ?? 0, to: book.id)
                           }
                       } label: {
                           HStack {
                               Text(book.name)
                               Spacer()
                               if store.associatedBooks.contains(where: { $0.id == book.id }) {
                                   Image(systemName: "checkmark")
                                       .foregroundStyle(.blue)
                               }
                           }
                       }
                       .buttonStyle(.plain)
                   }
               }
           }
           .navigationTitle("快捷分账")
           .toolbar {
               ToolbarItem(placement: .cancellationAction) {
                   Button("取消") { dismiss.toggle() }
               }
               ToolbarItem(placement: .confirmationAction) {
                   Button("保存") {
                       var draft = TransactionDraft(transaction: transaction!)
                       draft.categoryId = selectedCategoryId
                       await store.updateTransaction(transactionId, with: draft)
                       dismiss.toggle()
                   }
               }
           }
           .onDisappear {
               selectedCategoryId = transaction?.categoryId
           }
       }
   }
   private var selectedCategoryId: Int?
   let category: LedgerCategory
   @Binding var selectedCategoryId: Int?
   @State private var expanded = false
   var body: some View {
       if category.children.isEmpty {
           Button {
               selectedCategoryId = category.id
           } label: {
               HStack {
                   Text(category.name)
                   Spacer()
                   if selectedCategoryId == category.id {
                       Image(systemName: "checkmark")
                           .foregroundStyle(.blue)
                   }
               }
           }
           .buttonStyle(.plain)
       } else {
           DisclosureGroup(isExpanded: $expanded) {
               ForEach(category.children) { child in
                   ExpandableCategoryRow(category: child, selectedCategoryId: $selectedCategoryId)
                       .padding(.leading, 12)
               }
           } label: {
               Button {
                   selectedCategoryId = category.id
               } label: {
                   HStack {
                       Text(category.name)
                       Spacer()
                       if selectedCategoryId == category.id {
                           Image(systemName: "checkmark")
                               .foregroundStyle(.blue)
                       }
                   }
               }
               .buttonStyle(.plain)
           }
       }
   }
   let item: LedgerCategory
   var isEmpty: Bool
   var body: some View {
       HStack(spacing: 10) {
           if let icon = item.icon {
               Image(systemName: icon)
                   .frame(width: 18)
                   .foregroundStyle(.secondary)
           }
           Text(item.name)
               .foregroundStyle(.primary)
           Spacer()
           if selectedCategoryId == item.id {
               Image(systemName: "checkmark")
                   .foregroundStyle(.blue)
           }
       }
       .contentShape(Rectangle())
   }
   @EnvironmentObject private var store: LedgerStore
   let transaction: LedgerTransaction
   var body: some View {
       NavigationStack {
           List {
               Section("选择账本") {
                   ForEach(store.books) { book in
                       Button {
                           if store.associatedBooks.contains(where: { $0.id == book.id }) {
                               await store.removeTransaction(transactionId: transaction.id, from: book.id)
                           } else {
                               await store.assignTransaction(transactionId: transaction.id, to: book.id)
                           }
                       } label: {
                           HStack {
                               Text(book.name)
                               Spacer()
                               if store.associatedBooks.contains(where: { $0.id == book.id }) {
                                   Image(systemName: "checkmark")
                                       .foregroundStyle(.blue)
                               }
                           }
                       }
                       .buttonStyle(.plain)
                   }
               }
           }
           .navigationTitle("快捷分账")
           .toolbar {
               ToolbarItem(placement: .cancellationAction) {
                   Button("关闭") { dismiss.toggle() }
               }
           }
       }
   }
   private var liveTransaction: LedgerTransaction? {
       store.transactions.first(where: { $0.id == transaction.id })
   }
   private var associatedBooks: [LedgerBook] {
       guard let liveTransaction = liveTransaction else { return [] }
       return store.books.filter { liveTransaction.bookIds.contains($0.id) || liveTransaction.bookId == $0.id }
   }
   private var transactionBooksPopover: View {
       let bookNames = transaction.bookNames ?? []
       var body: some View {
           VStack(alignment: .leading, spacing: 10) {
               ForEach(bookNames, id: \.self) { name in
                   HStack(spacing: 8) {
                       Image(systemName: "books.vertical.fill")
                           .foregroundStyle(.purple)
                       Text(name)
                           .font(.subheadline)
                           .foregroundStyle(.primary)
                   }
               }
           }
           .padding(16)
           .frame(minWidth: 160, alignment: .leading)
           .presentationCompactAdaptation(.popover)
       }
   }
   case recent30Days
   case currentMonth
   case currentQuarter
   case currentYear
   case custom
   var id: String { rawValue }
   var title: String {
       switch self {
       case .recent30Days: return "近30天"
       case .currentMonth: return "本月"
       case .currentQuarter: return "本季度"
       case .currentYear: return "本年"
       case .custom: return "自定义"
       }
   }
   var defaultDates: (start: Date, end: Date) {
       let calendar = Calendar.current
       let now = Date()
       switch self {
       case .recent30Days:
           let start = calendar.date(byAdding: .day, value: -30, to: now)!
           return (calendar.startOfDay(for: start), now)
       case .currentMonth:
           let interval = calendar.dateInterval(of: .month, for: now)!
           return (interval.start, min(interval.end, now))
       case .currentQuarter:
           let interval = calendar.dateInterval(of: .quarter, for: now)!
           return (interval.start, min(interval.end, now))
       case .currentYear:
           let interval = calendar.dateInterval(of: .year, for: now)!
           return (interval.start, min(interval.end, now))
       case .custom:
           return (calendar.startOfDay(for: now), now)
       }
   }
   case all
   case expense
   case income
   var id: String { rawValue }
   var title: String {
       switch self {
       case .all: return "全部"
       case .expense: return "支出"
       case .income: return "收入"
       }
   }
   var tint: Color {
       switch self {
       case .all: return .blue
       case .expense: return .orange
       case .income: return .green
       }
   }
   let dateKey: Date
   let title: String
   let total: Double
   let items: [LedgerTransaction]
