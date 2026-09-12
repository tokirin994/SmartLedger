import SwiftUI
struct TransactionsView: View {
   @EnvironmentObject private var store: LedgerStore
   @Environment(\.colorScheme) private var colorScheme
   @State private var navPath = NavigationPath()
    @State private var showCreateSheet = false
    @State private var editingTransaction: LedgerTransaction?
    @State private var quickAssignTransaction: LedgerTransaction?
    @State private var quickBookTransaction: LedgerTransaction?
   @State private var pendingDeleteTransaction: LedgerTransaction?
    @State private var selectedFlow: FlowFilter = .all
    @State private var selectedDateScope: TransactionDateScope = .recent30Days
    @State private var selectedCategoryId: Int?
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var bookPopoverTransactionId: Int?

   var body: some View {

        NavigationStack {
            Group {
                if filteredTransactions.isEmpty {
                    ContentUnavailableView(
                        "暂无流水",
                        systemImage: "list.bullet.rectangle.portrait"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
                } else {
                    List {
                        summaryHeader

                        ForEach(groupedTransactions, id: \.dateKey) { group in
                            Section {
                                ForEach(group.items, id: \.id) { tx in
                                    transactionListRow(tx)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                        .listRowBackground(Color.clear)
                                }
                            } header: {
                                HStack {
                                    Text(group.title)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(groupHeaderForeground)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(groupHeaderBackground, in: Capsule())

                                    Spacer()

                                    Text(group.total.cnyText)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(groupHeaderForeground)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(groupHeaderBackground.opacity(0.92), in: Capsule())
                                }
                                .padding(.top, 6)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .appBackground()
                }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("流水")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button { Task { await reloadTransactions() } } label: { Image(systemName: "arrow.clockwise") } }
                    ToolbarItem(placement: .topBarTrailing) { Button { showCreateSheet = true } label: { Image(systemName: "plus") } }
                }
                .safeAreaInset(edge: .top) {
                    VStack(spacing: 10) {
                        filterBar
                        categoryFilterBar
                        customDateFilterBar
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .background(.ultraThinMaterial)
                }
                .sheet(isPresented: $showCreateSheet) {
                    CreateTransactionView()
                        .environmentObject(store)
                }
                .sheet(item: $editingTransaction) { tx in
                    CreateTransactionView(editingTransaction: tx)
                        .environmentObject(store)
                }
                .sheet(item: $quickAssignTransaction) { tx in
                    QuickCategoryAssignSheet(transaction: tx)
                        .environmentObject(store)
                }
                .sheet(item: $quickBookTransaction) { tx in
                    QuickBookAssignSheet(transaction: tx)
                        .environmentObject(store)
                }
                .alert("删除这笔流水?", isPresented: deleteAlertBinding) {
                    Button("取消", role: .cancel) {}
                    Button("删除", role: .destructive) {
                        if let tx = pendingDeleteTransaction {
                            Task { await store.deleteTransaction(tx.id) }
                        }
                        pendingDeleteTransaction = nil
                    }
                } message: {
                    Text("确认删除该记录?")
                }
                .onAppear {
                    Task {
                        if store.transactions.isEmpty {
                            await store.loadTransactions()
                            await reloadTransactions()
                        }
                    }
                }
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteTransaction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteTransaction = nil
                }
            }
        )
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(FlowFilter.allCases) { flow in
                Button { selectedFlow = flow } label: {
                    Text(flow.title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .foregroundStyle(selectedFlow == flow ? .white : .primary)
                        .background(selectedFlow == flow ? flow.tint : Color.secondary.opacity(0.12), in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(6)
        .glassCard(cornerRadius: 18, strokeOpacity: 0.18)
    }

    private var categoryFilterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(TransactionDateScope.allCases) { scope in
                        Button(scope.title) {
                            selectedDateScope = scope
                            if scope != .custom { let dates = scope.defaultDates; startDate = dates.start; endDate = dates.end }
                        }
                    }
                } label: { filterChip(title: selectedDateScope.title, systemImage: "calendar") }

                Menu {
                    Button("全部分类") { selectedCategoryId = nil }
                    Divider()
                    ForEach(categoryFilterOptions) { category in
                        Button(category.displayName) { selectedCategoryId = category.id }
                    }
                } label: { filterChip(title: selectedCategoryTitle, systemImage: "line.3.horizontal.decrease.circle") }

                Spacer(minLength: 0)
                if selectedCategoryId != nil || selectedDateScope != .recent30Days {
                    Button("重置") {
                        selectedCategoryId = nil; selectedDateScope = .recent30Days
                        let dates = TransactionDateScope.recent30Days.defaultDates; startDate = dates.start; endDate = dates.end
                    }.font(.caption.weight(.semibold))
                }
            }
            Text(dateScopeSummary).font(.caption).foregroundStyle(.secondary)
            if selectedDateScope == .custom {
                HStack {
                    DatePicker("开始", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束", selection: $endDate, in: startDate..., displayedComponents: .date)
                }.font(.caption)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 18, strokeOpacity: 0.18)
        .onChange(of: selectedDateScope) { _, _ in Task { await reloadTransactions() } }
        .onChange(of: selectedCategoryId) { _, _ in Task { await reloadTransactions() } }
        .onChange(of: startDate) { _, _ in if selectedDateScope == .custom { Task { await reloadTransactions() } } }
        .onChange(of: endDate) { _, _ in if selectedDateScope == .custom { Task { await reloadTransactions() } } }
    }

    private var customDateFilterBar: some View { EmptyView() }

	private var summaryHeader: some View {
		Section {
 			VStack(spacing: 12) {
 				HStack(spacing: 12) {
 					compactStat(title: "收入", value: totalIncome.cnyText, tint: .green)
 					compactStat(title: "支出", value: totalExpense.cnyText, tint: .orange)
 					compactStat(title: "净额", value: netAmount.cnyText, tint: netAmount >= 0 ? .blue : .red)
 				}
 			}
 			.padding(.vertical, 6)
		}
 		.listRowBackground(Color.clear)
 	}

	private func compactStat(title: String, value: String, tint: Color) -> some View {
 		HStack(alignment: .firstTextBaseline, spacing: 6) {
 			VStack(alignment: .leading, spacing: 6) {
				Text(title)
					.font(.caption)
					.foregroundStyle(.secondary)
				Text(value)
 					.font(.subheadline.weight(.bold))
 					.foregroundStyle(tint)
			}
 			.frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
 			.padding(12)
 			.glassCard(cornerRadius: 18, strokeOpacity: 0.22)
 		}
	}
    private func transactionListRow(_ tx: LedgerTransaction) -> some View {
        transactionRow(tx)
            .contentShape(Rectangle())
            .onTapGesture { editingTransaction = tx }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { pendingDeleteTransaction = tx } label: { Label("删除", systemImage: "trash") }
                Button { quickBookTransaction = tx } label: { Label("账本", systemImage: "books.vertical") }.tint(.purple)
                Button { quickAssignTransaction = tx } label: { Label("分类", systemImage: "tag") }.tint(.blue)
            }
    }

    private func transactionRow(_ tx: LedgerTransaction) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: categoryIcon(for: tx))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(badgeColor(for: tx))
                .frame(width: 42, height: 42)
                .background(badgeColor(for: tx).opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tx.title).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(signedAmountText(for: tx)).font(.headline.weight(.bold)).foregroundStyle(tx.kind == .income ? .green : .primary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        infoPill(text: tx.categoryName ?? "未分类", systemImage: "tag")
                        let bookNames = displayBookNames(for: tx)
                        if bookNames.count == 1 { infoPill(text: bookNames[0], systemImage: "books.vertical", tint: .purple) }
                        else if bookNames.count > 1 {
                            Button { bookPopoverTransactionId = tx.id } label: { infoPill(text: "…", systemImage: "books.vertical", tint: .purple) }
                                .buttonStyle(.plain)
                                .popover(isPresented: Binding(get: { bookPopoverTransactionId == tx.id }, set: { if !$0 { bookPopoverTransactionId = nil } })) {
                                    TransactionBooksPopover(bookNames: bookNames)
                                }
                        }
                        if tx.source == "ocr" { infoPill(text: "OCR", systemImage: "camera.viewfinder", tint: .blue) }
                        if tx.installmentMonths != nil { infoPill(text: installmentText(for: tx), systemImage: "repeat.circle", tint: .orange) }
                    }
                }
                HStack(spacing: 12) {
                    Label(tx.happenedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    if let merchant = tx.merchant, !merchant.isEmpty { Label(merchant, systemImage: "storefront").lineLimit(1) }
                }.font(.caption).foregroundStyle(.secondary)
                if let payment = tx.paymentMethod, !payment.isEmpty { infoPill(text: payment, systemImage: "creditcard.fill", tint: .teal) }
                if tx.originalAmount != nil || tx.discountAmount != nil || tx.premiumAmount != nil {
                    HStack(spacing: 14) {
                        if let value = tx.originalAmount { miniMetric(title: "原价", value: value.cnyText, tint: .secondary) }
                        if let value = tx.discountAmount { miniMetric(title: "优惠", value: value.cnyText, tint: .green) }
                        if let value = tx.premiumAmount { miniMetric(title: "溢价", value: value.cnyText, tint: .red) }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

 	private func infoPill(text: String, systemImage: String, tint: Color = .secondary) -> some View {
 		Label(text, systemImage: systemImage)
 			.font(.caption.weight(.medium))
 			.foregroundStyle(tint)
 			.lineLimit(1)
 			.padding(.horizontal, 10)
 			.frame(height: 30)
 			.background(Color.white.opacity(0.14), in: Capsule())
 	}
 
 	private func iconOnlyPill(systemImage: String, trailingText: String, tint: Color = .purple) -> some View {
 		HStack(spacing: 6) {
 			Image(systemName: systemImage)
 			Spacer()
 			Text(trailingText)
 		}
 		.font(.caption.weight(.medium))
 		.foregroundStyle(tint)
 		.lineLimit(1)
 		.padding(.horizontal, 10)
 		.padding(.vertical, 6)
 		.frame(height: 30)
 		.background(Color.white.opacity(0.14), in: Capsule())
 	}
 
    private func amountPill(title: String, value: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

 	private func miniMetric(title: String, value: String, tint: Color) -> some View {
 		VStack(alignment: .leading, spacing: 2) {
			Text(title)
 				.font(.caption2)
				.foregroundStyle(.secondary)
			Text(value)
 				.font(.caption.weight(.semibold))
 				.foregroundStyle(tint)
		}
 		.padding(.horizontal, 10)
 		.background(Color.white.opacity(0.14), in: Capsule())
 		.padding(.vertical, 8)
 		.background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
 	}
 
 	private func signedAmountText(for tx: LedgerTransaction) -> String {
        (tx.kind == .expense ? -tx.amount : tx.amount).cnyText
 	}
 
 	private func installmentText(for tx: LedgerTransaction) -> String {
 		if let index = tx.installmentIndex, let months = tx.installmentMonths {
 			return "分期 \(index)/\(months)"
 		}
 		return "分期"
 	}
 
 	private func badgeIcon(for tx: LedgerTransaction) -> String {
 		if tx.kind == .income {
 			return "arrow.down.left"
 		}
 		if tx.installmentMonths != nil {
 			return "creditcard"
 		}
 		if tx.source == "ocr" {
 			return "camera.viewfinder"
 		}
 		return "arrow.up.right"
 	}
 
 	private func categoryIcon(for tx: LedgerTransaction) -> String {
 		if let categoryId = tx.categoryId,
 		   let category = store.flattenedCategories.first(where: { $0.id == categoryId }) {
 			return category.icon ?? "square.grid.2x2"
 		}
 		return "square.grid.2x2"
 	}
 
 	private func badgeColor(for tx: LedgerTransaction) -> Color {
 		tx.kind == .income ? .green : (tx.installmentMonths != nil ? .orange : .blue)
 	}
 
 	private func displayBookNames(for tx: LedgerTransaction) -> [String] {
 		let names = !tx.bookNames.isEmpty ? tx.bookNames : (tx.bookName.map { [$0] } ?? [])
 		var seen = Set<String>()
 		return names.filter { seen.insert($0).inserted }
 	}
 
 	private var filteredTransactions: [LedgerTransaction] {
 		let start = Calendar.current.startOfDay(for: startDate)
 		let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
 		var result = store.transactions.filter { $0.happenedAt >= start && $0.happenedAt < end }
 
 		if let selectedCategoryId {
 			result = result.filter { transaction in
 				guard let categoryId = transaction.categoryId else { return false }
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
 		let flowScoped = store.flattenedCategories.filter { category in
 			switch selectedFlow {
 			case .all: return true
 			case .expense: return category.flowType == .expense
 			case .income: return category.flowType == .income
 			}
 		}
 
 		return flowScoped.sorted { lhs, rhs in
 			if lhs.level == rhs.level {
 				return lhs.name < rhs.name
 			}
 			return lhs.level < rhs.level
 		}
 	}
 
 	private var selectedCategoryTitle: String {
 		guard let selectedCategoryId,
 			  let category = store.flattenedCategories.first(where: { $0.id == selectedCategoryId }) else {
 			return "全部分类"
 		}
 		return category.name
 	}
 
 	private var dateScopeSummary: String {
 		if selectedDateScope == .custom {
 			return "\(startDate.formatted(date: .abbreviated, time: .omitted)) — \(endDate.formatted(date: .abbreviated, time: .omitted))"
 		}
 		return selectedDateScope.summaryText
 	}
 
 	private func filterChip(title: String, systemImage: String) -> some View {
 		Label(title, systemImage: systemImage)
 			.font(.subheadline.weight(.semibold))
 			.foregroundStyle(.primary)
 			.padding(.horizontal, 12)
 			.padding(.vertical, 10)
 			.background(filterChipBackground, in: Capsule())
 			.overlay {
 				Capsule()
 					.stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.28), lineWidth: 1)
 			}
 	}
 
 	private var groupHeaderForeground: Color {
 		colorScheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.78)
 	}
 
 	private var groupHeaderBackground: Color {
 		colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.44)
 	}
 
 	private var calendarMetadataForeground: Color {
 		colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.72)
 	}
 
 	private var calendarMetadataBackground: Color {
 		colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.40)
 	}
 
 	private var filterChipBackground: Color {
 		colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.34)
 	}
 
 	private func categoryMatchesFilter(transactionCategoryId: Int, selectedCategoryId: Int) -> Bool {
 		if transactionCategoryId == selectedCategoryId { return true }
 
 		guard let selectedCategory = store.flattenedCategories.first(where: { $0.id == selectedCategoryId }) else {
 			return false
 		}
 
 		guard let transactionCategory = store.flattenedCategories.first(where: { $0.id == transactionCategoryId }) else { return false }
		return transactionCategory.pathComponents.starts(with: selectedCategory.pathComponents)
 	}
 
 	private var groupedTransactions: [TransactionDayGroup] {
 		let calendar = Calendar.current
 		let grouped = Dictionary(grouping: filteredTransactions) { calendar.startOfDay(for: $0.happenedAt) }
 
 		return grouped
 			.map { day, items in
 				let partial = items.reduce(0.0) { partial, tx in
 					partial + (tx.kind == .income ? tx.amount : -tx.amount)
 				}
 				return TransactionDayGroup(dateKey: day, title: day.formatted(date: .abbreviated, time: .omitted), total: partial, items: items.sorted { $0.happenedAt > $1.happenedAt })
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
 	}
}

private struct QuickCategoryAssignSheet: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let transaction: LedgerTransaction
    @State private var selectedCategoryId: Int?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedCategoryId = nil
                    } label: {
                        HStack {
                            Text("未分类")
                            Spacer()
                            if selectedCategoryId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("分类") {
                    ForEach(store.categories.filter { $0.flowType == transaction.kind }) { category in
                        ExpandableCategoryRow(category: category, selectedCategoryId: $selectedCategoryId)
                    }
                }
            }
            .navigationTitle("快速改分类")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            var draft = TransactionDraft(transaction: transaction)
                            draft.categoryId = selectedCategoryId
                            await store.updateTransaction(transaction.id, with: draft)
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                selectedCategoryId = transaction.categoryId
            }
        }
    }
}

private struct ExpandableCategoryRow: View {
    let category: LedgerCategory
    @Binding var selectedCategoryId: Int?
    @State private var expanded = false

    var body: some View {
        if category.children.isEmpty {
            Button {
                selectedCategoryId = category.id
            } label: {
                rowContent(category)
            }
            .buttonStyle(.plain)
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 6) {
                    ForEach(category.children) { child in
                        ExpandableCategoryRow(category: child, selectedCategoryId: $selectedCategoryId)
                            .padding(.leading, 12)
                    }
                }
                .padding(.top, 6)
            } label: {
                Button {
                    selectedCategoryId = category.id
                } label: {
                    rowContent(category)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ item: LedgerCategory) -> some View {
        HStack(spacing: 10) {
            if let icon = item.icon, !icon.isEmpty {
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
}

private struct QuickBookAssignSheet: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let transaction: LedgerTransaction

    var body: some View {
        NavigationStack {
            List {
                Section("全部账本") {
                    ForEach(store.books) { book in
                        Button {
                            Task {
                                if associatedBooks.contains(where: { $0.id == book.id }) {
                                    await store.removeTransaction(transaction.id, from: book.id)
                                } else {
                                    await store.assignTransaction(transaction.id, to: book.id)
                                }
                            }
                        } label: {
                            HStack {
                                Text(book.name)
                                Spacer()
                                if associatedBooks.contains(where: { $0.id == book.id }) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("账本归属")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
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
}

private struct TransactionBooksPopover: View {
    let bookNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关联账本")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(bookNames, id: \.self) { name in
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical.fill")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 160, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }
}

private enum FlowFilter: String, CaseIterable, Identifiable {
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
}

private enum TransactionDateScope: String, CaseIterable, Identifiable {
    case recent7Days
    case recent30Days
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent7Days: return "近 7 天"
        case .recent30Days: return "近 30 天"
        case .custom: return "自定义"
        }
    }

    var summaryText: String { title }

    var defaultDates: (start: Date, end: Date) {
        switch self {
        case .recent7Days:
            let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return (start, Date())
        case .recent30Days:
            let start = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            return (start, Date())
        case .custom:
            return (Date(), Date())
        }
    }
}

private struct TransactionDayGroup {
    let dateKey: Date
    let title: String
    let total: Double
    let items: [LedgerTransaction]
}
