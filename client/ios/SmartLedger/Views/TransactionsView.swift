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
     @State private var searchText = ""
     @State private var selectedDateScope: TransactionDateScope = .thisMonth
    @State private var selectedCategoryFilter: TransactionCategoryFilter = .all
    @State private var showCategoryFilterSheet = false
     @State private var startDate = TransactionDateScope.thisMonth.defaultDates.start
    @State private var endDate = Date()
    @State private var bookPopoverTransactionId: Int?
    @State private var isBatchSelecting = false
    @State private var selectedTransactionIDs: Set<Int> = []
    @State private var showBatchCategoryEditor = false
    @State private var categoryPathsByID: [Int: [String]] = [:]
    @State private var categoryIconsByID: [Int: String] = [:]

   var body: some View {
        let visibleTransactions = filteredTransactions
        let visibleGroups = groupedTransactions(from: visibleTransactions)
        let totals = transactionTotals(for: visibleTransactions)
        NavigationStack {
            List {
                if visibleTransactions.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "暂无流水" : "没有匹配的流水",
                        systemImage: "list.bullet.rectangle.portrait"
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .listRowBackground(Color.clear)
                } else {
                    summaryHeader(totals)

                    ForEach(visibleGroups, id: \.dateKey) { group in
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
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(isBatchSelecting ? "已选 \(selectedTransactionIDs.count) 笔" : "流水")
            .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(isBatchSelecting ? "取消" : "选择") {
                            isBatchSelecting.toggle()
                            selectedTransactionIDs.removeAll()
                        }
                    }
                    if isBatchSelecting {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button("全选") { selectedTransactionIDs = Set(filteredTransactions.map(\.id)) }
                            Button("改分类") { showBatchCategoryEditor = true }
                                .disabled(selectedTransactionIDs.isEmpty)
                        }
                    } else {
                        ToolbarItem(placement: .topBarTrailing) { Button { Task { await reloadTransactions() } } label: { Image(systemName: "arrow.clockwise") } }
                        ToolbarItem(placement: .topBarTrailing) { Button { showCreateSheet = true } label: { Image(systemName: "plus") } }
                    }
                }
                 .safeAreaInset(edge: .top) {
                     VStack(spacing: 10) {
                         searchBar
                         filterBar
                        categoryFilterBar
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .background(Color(uiColor: .systemGroupedBackground))
                    .overlay(alignment: .bottom) {
                        Divider().opacity(0.35)
                    }
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
                .sheet(isPresented: $showCategoryFilterSheet) {
                    TransactionCategoryFilterSheet(
                        selection: $selectedCategoryFilter,
                        categories: transactionCategoryRoots,
                        flowType: selectedFlow == .income ? .income : .expense
                    )
                    .environmentObject(store)
                }
                .sheet(isPresented: $showBatchCategoryEditor) {
                    BatchCategoryEditorSheet(flowTypes: Set(store.transactions.filter { selectedTransactionIDs.contains($0.id) }.map(\.kind))) { updateExpense, expenseCategoryId, updateIncome, incomeCategoryId in
                        var updates: [(transactionId: Int, categoryId: Int?)] = []
                        for transaction in store.transactions where selectedTransactionIDs.contains(transaction.id) {
                            if transaction.kind == .expense, updateExpense {
                                updates.append((transaction.id, expenseCategoryId))
                            } else if transaction.kind == .income, updateIncome {
                                updates.append((transaction.id, incomeCategoryId))
                            }
                        }
                        await store.batchUpdateTransactionCategories(updates)
                        selectedTransactionIDs.removeAll()
                        isBatchSelecting = false
                    }
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
                    rebuildCategoryCaches()
                    Task {
                        if store.transactions.isEmpty {
                            await store.loadTransactions()
                            await reloadTransactions()
                        }
                    }
                }
                .onChange(of: store.categories) { _, _ in rebuildCategoryCaches() }
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

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索标题、商户、备注或分类", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1) }
    }

    private var categoryFilterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(TransactionDateScope.presets) { scope in
                    Button {
                        applyDateScope(scope)
                    } label: {
                        Text(scope.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedDateScope == scope ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(selectedDateScope == scope ? Color.accentColor : filterChipBackground, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    applyDateScope(.custom)
                } label: {
                    Label("自定义", systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .foregroundStyle(selectedDateScope == .custom ? .white : .primary)
                        .background(selectedDateScope == .custom ? Color.accentColor : filterChipBackground, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if selectedDateScope == .custom {
                HStack(spacing: 8) {
                    DatePicker("开始", selection: $startDate, displayedComponents: .date)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    DatePicker("结束", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                .font(.caption)
            }

            Button {
                showCategoryFilterSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    Text("分类")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(selectedCategoryFilterTitle)
                        .foregroundStyle(selectedCategoryFilter == .all ? Color.secondary : Color.blue)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack {
                if selectedCategoryFilter != .all || selectedDateScope != .thisMonth || selectedFlow != .all || !searchText.isEmpty {
                    Button("重置") {
                        selectedCategoryFilter = .all
                        selectedFlow = .all
                        searchText = ""
                        applyDateScope(.thisMonth)
                    }.font(.caption.weight(.semibold))
                }
                Spacer()
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 18, strokeOpacity: 0.18)
        .onChange(of: selectedDateScope) { _, scope in
            if scope != .custom {
                let dates = scope.defaultDates
                startDate = dates.start
                endDate = dates.end
            }
        }
        .onChange(of: selectedFlow) { _, flow in
            guard case let .category(selectedCategoryId) = selectedCategoryFilter,
                  let selected = store.flattenedCategories.first(where: { $0.id == selectedCategoryId }) else { return }
            if flow != .all && selected.flowType != (flow == .income ? .income : .expense) {
                selectedCategoryFilter = .all
            }
        }
    }

	private func summaryHeader(_ totals: TransactionTotals) -> some View {
		Section {
 			VStack(spacing: 12) {
 				HStack(spacing: 12) {
					compactStat(title: "收入", value: totals.income.cnyText, tint: .green)
					compactStat(title: "支出", value: totals.expense.cnyText, tint: .orange)
					compactStat(title: "净额", value: totals.net.cnyText, tint: totals.net >= 0 ? .blue : .red)
 				}
 			}
 			.padding(.vertical, 6)
			HStack(spacing: 12) {
				compactStat(title: "优惠", value: totals.discount.cnyText, tint: .green)
				compactStat(title: "溢价", value: totals.premium.cnyText, tint: .red)
			}
		}
 		.listRowBackground(Color.clear)
 	}

	private func compactStat(title: String, value: String, tint: Color) -> some View {
		VStack(alignment: .leading, spacing: 7) {
			Text(title)
				.font(.caption)
				.foregroundStyle(.secondary)
			Text(value)
				.font(.system(size: 18, weight: .bold, design: .rounded))
				.foregroundStyle(tint)
				.lineLimit(1)
				.minimumScaleFactor(0.52)
				.allowsTightening(true)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74, alignment: .leading)
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.glassCard(cornerRadius: 18, strokeOpacity: 0.22)
	}
    private func transactionListRow(_ tx: LedgerTransaction) -> some View {
        Group {
            if isBatchSelecting {
                Button {
                    if selectedTransactionIDs.contains(tx.id) { selectedTransactionIDs.remove(tx.id) }
                    else { selectedTransactionIDs.insert(tx.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selectedTransactionIDs.contains(tx.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedTransactionIDs.contains(tx.id) ? .blue : .secondary)
                        transactionRow(tx)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                transactionRow(tx)
                    .contentShape(Rectangle())
                    .onTapGesture { editingTransaction = tx }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingDeleteTransaction = tx } label: { Label("删除", systemImage: "trash") }
                        Button { quickBookTransaction = tx } label: { Label("账本", systemImage: "books.vertical") }.tint(.purple)
                        Button { quickAssignTransaction = tx } label: { Label("分类", systemImage: "tag") }.tint(.blue)
                    }
            }
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
                    Text(signedAmountText(for: tx))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(tx.kind == .income ? .green : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                HStack(spacing: 6) {
                    infoPill(text: tx.categoryName ?? "未分类", systemImage: "tag")
                        .layoutPriority(1)
                    let bookNames = displayBookNames(for: tx)
                    if bookNames.count == 1 { infoPill(text: bookNames[0], systemImage: "books.vertical", tint: .purple) }
                    else if bookNames.count > 1 {
                        Button { bookPopoverTransactionId = tx.id } label: { infoPill(text: "多账本", systemImage: "books.vertical", tint: .purple) }
                            .buttonStyle(.plain)
                            .popover(isPresented: Binding(get: { bookPopoverTransactionId == tx.id }, set: { if !$0 { bookPopoverTransactionId = nil } })) {
                                TransactionBooksPopover(bookNames: bookNames)
                            }
                    }
                    if tx.source == "ocr" { infoPill(text: "OCR", systemImage: "camera.viewfinder", tint: .blue) }
                    if tx.installmentMonths != nil { infoPill(text: installmentText(for: tx), systemImage: "repeat.circle", tint: .orange) }
                }
                HStack(spacing: 12) {
                    Label(tx.happenedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    if let merchant = tx.merchant, !merchant.isEmpty { Label(merchant, systemImage: "storefront").lineLimit(1) }
                }.font(.caption).foregroundStyle(.secondary)
                if let payment = tx.paymentMethod, !payment.isEmpty { infoPill(text: payment, systemImage: "creditcard.fill", tint: .teal) }
                if tx.discountAmount != nil || tx.premiumAmount != nil {
                    HStack(spacing: 8) {
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
		HStack(spacing: 4) {
			Text(title).font(.caption2).foregroundStyle(.secondary)
			Text(value).font(.caption.weight(.semibold)).foregroundStyle(tint)
		}
		.lineLimit(1)
		.minimumScaleFactor(0.72)
		.padding(.horizontal, 9)
		.padding(.vertical, 6)
		.background(Color.white.opacity(0.16), in: Capsule())
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
		guard let categoryId = tx.categoryId else { return "square.grid.2x2" }
		return categoryIconsByID[categoryId] ?? "square.grid.2x2"
 	}

    private func rebuildCategoryCaches() {
        let categories = store.flattenedCategories
        categoryPathsByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.pathComponents) })
        categoryIconsByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.icon ?? "square.grid.2x2") })
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
 
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { matchesSearch($0, query: query) }
        }

        switch selectedCategoryFilter {
        case .all:
            break
        case .uncategorized:
            result = result.filter { $0.categoryId == nil }
        case let .category(selectedCategoryId):
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

    private func matchesSearch(_ transaction: LedgerTransaction, query: String) -> Bool {
        let searchable = [
            transaction.title,
            transaction.merchant ?? "",
            transaction.note ?? "",
            transaction.categoryName ?? "",
            transaction.bookName ?? "",
            transaction.bookNames.joined(separator: " "),
            transaction.paymentMethod ?? ""
        ].joined(separator: " ")
        return searchable.localizedCaseInsensitiveContains(query)
    }
 
	private var transactionCategoryRoots: [LedgerCategory] {
		guard selectedFlow != .all else { return store.categories }
		return store.categories.filter { $0.flowType == (selectedFlow == .income ? .income : .expense) }
	}

    private var selectedCategoryFilterTitle: String {
        switch selectedCategoryFilter {
        case .all:
            return "全部分类"
        case .uncategorized:
            return "未分类"
        case let .category(id):
            return store.flattenedCategories.first(where: { $0.id == id })?.displayName ?? "指定分类"
        }
    }
 
    private func applyDateScope(_ scope: TransactionDateScope) {
        selectedDateScope = scope
        guard scope != .custom else { return }
        let dates = scope.defaultDates
        startDate = dates.start
        endDate = dates.end
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
 
		guard let selectedPath = categoryPathsByID[selectedCategoryId],
              let transactionPath = categoryPathsByID[transactionCategoryId] else { return false }
		return transactionPath.starts(with: selectedPath)
 	}
 
	private func groupedTransactions(from transactions: [LedgerTransaction]) -> [TransactionDayGroup] {
 		let calendar = Calendar.current
		let grouped = Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.happenedAt) }
 
 		return grouped
 			.map { day, items in
 				let partial = items.reduce(0.0) { partial, tx in
					partial + (tx.kind == .income ? tx.selfShareAmount : -tx.selfShareAmount)
 				}
 				return TransactionDayGroup(dateKey: day, title: day.formatted(date: .abbreviated, time: .omitted), total: partial, items: items.sorted { $0.happenedAt > $1.happenedAt })
 			}
 			.sorted { $0.dateKey > $1.dateKey }
 	}
 
    private func transactionTotals(for transactions: [LedgerTransaction]) -> TransactionTotals {
        transactions.reduce(into: TransactionTotals()) { totals, transaction in
            if transaction.kind == .income { totals.income += transaction.selfShareAmount }
            else { totals.expense += transaction.selfShareAmount }
            totals.discount += transaction.discountAmount ?? 0
            totals.premium += transaction.premiumAmount ?? 0
        }
    }
 
 	private func reloadTransactions() async {
 	}
}

private struct TransactionTotals {
    var income: Double = 0
    var expense: Double = 0
    var discount: Double = 0
    var premium: Double = 0

    var net: Double { income - expense }
}

struct BatchCategoryEditorSheet: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let flowTypes: Set<FlowType>
    let onSave: (Bool, Int?, Bool, Int?) async -> Void
    @State private var applyExpense = false
    @State private var expenseCategoryId: Int?
    @State private var applyIncome = false
    @State private var incomeCategoryId: Int?

    var body: some View {
        NavigationStack {
            Form {
                if flowTypes.contains(.expense) {
                    categorySection(title: "支出分类", enabled: $applyExpense, selection: $expenseCategoryId, flowType: .expense)
                }
                if flowTypes.contains(.income) {
                    categorySection(title: "收入分类", enabled: $applyIncome, selection: $incomeCategoryId, flowType: .income)
                }
                Section {
                    Text("未分类会清除所选流水当前分类；未开启修改的收支类型保持不变。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("批量改分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        Task {
                            await onSave(applyExpense, expenseCategoryId, applyIncome, incomeCategoryId)
                            dismiss()
                        }
                    }
                    .disabled(!applyExpense && !applyIncome)
                }
            }
            .task { if store.categories.isEmpty { await store.loadCategories() } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func categorySection(title: String, enabled: Binding<Bool>, selection: Binding<Int?>, flowType: FlowType) -> some View {
        Section(title) {
            Toggle("应用到所选流水", isOn: enabled)
            if enabled.wrappedValue {
                HierarchicalCategoryPicker(
                    title: "分类",
                    categories: store.categories.filter { $0.flowType == flowType },
                    placeholder: "未分类",
                    helperText: nil,
                    selectedCategoryId: selection,
                    flowType: flowType,
                    onCreateCategory: nil
                )
            }
        }
    }
}

private struct QuickCategoryAssignSheet: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let transaction: LedgerTransaction
    @State private var selectedCategoryId: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section("快速修改") {
                    HierarchicalCategoryPicker(
                        title: "分类",
                        categories: store.categories.filter { $0.flowType == transaction.kind },
                        placeholder: "未分类",
                        helperText: "先选一级分类，再逐级进入子分类。",
                        selectedCategoryId: $selectedCategoryId,
                        flowType: transaction.kind,
                        onCreateCategory: nil
                    )
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
                if store.categories.isEmpty {
                    Task { await store.loadCategories() }
                }
            }
        }
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
        let linkedBookIDs = Set(store.transactionLinks(for: liveTransaction.id).map(\.ledgerId))
        return store.books.filter { linkedBookIDs.contains($0.id) || liveTransaction.bookIds.contains($0.id) || liveTransaction.bookId == $0.id }
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

private enum TransactionCategoryFilter: Equatable {
    case all
    case uncategorized
    case category(Int)
}

private struct TransactionCategoryFilterSheet: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: TransactionCategoryFilter
    let categories: [LedgerCategory]
    let flowType: FlowType
    @State private var selectedCategoryId: Int?

    init(selection: Binding<TransactionCategoryFilter>, categories: [LedgerCategory], flowType: FlowType) {
        _selection = selection
        self.categories = categories
        self.flowType = flowType
        let currentCategoryId: Int?
        if case let .category(id) = selection.wrappedValue {
            currentCategoryId = id
        } else {
            currentCategoryId = nil
        }
        _selectedCategoryId = State(initialValue: currentCategoryId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("快速筛选") {
                    filterOption("全部分类", subtitle: "显示已分类和未分类流水", isSelected: selection == .all) {
                        selectedCategoryId = nil
                        selection = .all
                    }
                    filterOption("未分类", subtitle: "仅显示没有指定分类的流水", isSelected: selection == .uncategorized) {
                        selectedCategoryId = nil
                        selection = .uncategorized
                    }
                }

                Section("指定分类") {
                    HierarchicalCategoryPicker(
                        title: "选择分类",
                        categories: categories,
                        placeholder: "不限分类",
                        helperText: nil,
                        selectedCategoryId: $selectedCategoryId,
                        flowType: flowType,
                        onCreateCategory: nil,
                        showsUncategorizedOption: false
                    )
                    .onChange(of: selectedCategoryId) { _, id in
                        if let id { selection = .category(id) }
                    }
                }
            }
            .navigationTitle("筛选分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func filterOption(_ title: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    case thisWeek
    case thisMonth
    case thisYear
    case custom

    var id: String { rawValue }

    static var presets: [TransactionDateScope] { [.thisWeek, .thisMonth, .thisYear] }

    var title: String {
        switch self {
        case .thisWeek: return "本周"
        case .thisMonth: return "本月"
        case .thisYear: return "本年"
        case .custom: return "自定义"
        }
    }

    var summaryText: String { title }

    var defaultDates: (start: Date, end: Date) {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let now = Date()
        switch self {
        case .thisWeek:
            return (calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now), now)
        case .thisMonth:
            return (calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now), now)
        case .thisYear:
            return (calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now), now)
        case .custom:
            return (calendar.startOfDay(for: now), now)
        }
    }
}

private struct TransactionDayGroup {
    let dateKey: Date
    let title: String
    let total: Double
    let items: [LedgerTransaction]
}
