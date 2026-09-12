import AuthenticationServices
import Foundation

@MainActor
final class LedgerStore: ObservableObject {
    @Published var categories: [LedgerCategory] = []
    @Published var books: [LedgerBook] = []
    @Published var transactions: [LedgerTransaction] = []
    @Published var overview: AnalyticsOverview?
    @Published var budgets: [BudgetItem] = []
    @Published var parsedImport: OCRImportResult?
    @Published var parsedImportItems: [OCRImportResult] = []
    @Published var categoryTrend: CategoryTrendResponse?
    @Published var activeRangePreset: DateRangePreset = .currentMonth
    @Published var activeCustomRange: CustomDateRange = .recent30Days
    @Published var activeGranularity: Granularity = .week
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var cloudSyncEnabled: Bool = UserDefaults.standard.object(forKey: "smartledgerlocal.cloudSyncEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(cloudSyncEnabled, forKey: "smartledgerlocal.cloudSyncEnabled") }
    }

    @Published var cloudAccountStatus: CloudAccountStatus = .unknown
    @Published var cloudUserRecordName: String?
    @Published var lastSyncAt: Date?
    @Published var lastSyncMessage: String = "尚未同步"
    @Published var syncState: SyncState = .idle
    @Published var appleProfile: AppleAccountProfile?
    @Published var recommendedBookForDraft: LedgerBook?
    @Published var pendingSyncConflict: SyncConflictSummary?

    private let calendar = Calendar.current
    private let parser = ReceiptParser()
    private let legacyLocalStore = LocalSnapshotStore()
    private let localStore = SwiftDataSnapshotStore()
    private let cloudStore = CloudSyncService()

    private var localUpdatedAt: Date?
    private var hasBootstrapped = false
    private var pendingRemoteSnapshot: PersistedLedgerSnapshot?

    private var nextTransactionId = 1000
    private var nextBookId = 100
    private var nextCategoryId = 1000
    private var nextBudgetId = 100

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        isLoading = true
        defer { isLoading = false }

        await loadAppleProfileFromStorage()
        await validateAppleCredentialIfNeeded()

        if cloudSyncEnabled {
            await refreshCloudAccountState()
        } else {
            cloudAccountStatus = .unknown
            cloudUserRecordName = nil
            lastSyncMessage = "当前仅本地模式"
        }

        do {
            if let snapshot = try await localStore.load() {
                apply(snapshot)
                localUpdatedAt = snapshot.updatedAt
            } else if let legacySnapshot = try await legacyLocalStore.load() {
                apply(legacySnapshot)
                localUpdatedAt = legacySnapshot.updatedAt
                try await localStore.save(legacySnapshot)
                lastSyncMessage = "已从旧版本快照迁移到 SwiftData"
            } else {
                seedLocalData()
                try await persistLocalSnapshot(markUpdatedAt: true)
            }
        } catch {
            seedLocalData()
            errorMessage = "读取本地数据失败，已回退到默认数据: \(error.localizedDescription)"
        }

        refreshDerivedData()

        if cloudSyncEnabled {
            await smartSync(showSuccessMessage: false)
        } else {
            lastSyncMessage = "当前仅本地模式"
        }

        await refreshDashboard(range: activeRangePreset, granularity: activeGranularity)
    }

    func bootstrapIfNeeded() async {
        await bootstrap()
    }

    func refreshDashboard(range: DateRangePreset, granularity: Granularity) async {
        activeRangePreset = range
        activeGranularity = granularity
        await refreshDashboard(window: range.resolve(), granularity: granularity)
    }

    func refreshDashboard(customRange: CustomDateRange, granularity: Granularity) async {
        activeCustomRange = customRange
        activeGranularity = granularity
        await refreshDashboard(window: customRange.resolvedWindow, granularity: granularity)
    }

    private func refreshDashboard(window: DateWindow, granularity: Granularity) async {
        let filtered = allTransactions(in: window)
        budgets = LocalAnalytics.computeBudgetProgress(transactions: transactions, categories: flattenedCategories, budgets: budgets)
        overview = LocalAnalytics.makeOverview(
            transactions: filtered,
            categories: flattenedCategories,
            budgets: budgets,
            start: window.start,
            end: window.end,
            granularity: granularity
        )
        categoryTrend = LocalAnalytics.makeCategoryTrend(
            transactions: filtered,
            categories: flattenedCategories,
            start: window.start,
            end: window.end,
            granularity: granularity,
            flowType: .expense
        )
    }

    func loadCategories() async {}
    func loadTransactions() async {}
    func loadBooks() async {}
    func loadTransactions(bookId: Int?) async {}

    func parseOCR(text: String) async {
        let result = parser.parse(rawText: text)
        parsedImport = result
        parsedImportItems = parser.parseMultiple(rawText: text)
    }

    func createTransaction(_ draft: TransactionDraft) async {
        guard let amount = Double(draft.amount), !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            errorMessage = "请填写有效的标题和金额"
            return
        }

        let resolvedBooks = resolveBooksForTransactionDraft(draft)
        let resolvedBook = resolvedBooks.first

        let selectedBook = resolvedBook
        let bookName = selectedBook?.name
        let categoryName = resolvedCategoryName(for: draft.categoryId)
        let bookParticipants = selectedBook?.participants ?? []
        let resolvedSplitParticipants = bookParticipants.filter { draft.splitParticipantIds.contains($0.id) }
        let resolvedPayer = bookParticipants.first(where: { $0.id == draft.paidByParticipantId })

        if selectedBook?.splitEnabled == true {
            guard !resolvedSplitParticipants.isEmpty else {
                errorMessage = "账本流水请至少选择 1 位分账成员"
                return
            }
            guard resolvedPayer != nil else {
                errorMessage = "账本流水请先选择付款人"
                return
            }
        }

        let months = max(draft.installmentMonths, 1)
        let eachAmount = (amount / Double(months) * 100).rounded() / 100
        let baseDate = months > 1 ? draft.installmentStartMonth : draft.happenedAt
        let groupId = months > 1 ? UUID().uuidString : nil
        var accumulated = 0.0
        var created: [LedgerTransaction] = []

        for index in 0..<months {
            var installmentAmount = eachAmount
            if index == months - 1 {
                installmentAmount = ((amount - accumulated) * 100).rounded() / 100
            }
            accumulated += installmentAmount
            let date = calendar.date(byAdding: .month, value: index, to: baseDate) ?? baseDate
            created.append(
                LedgerTransaction(
                    id: nextTransactionId + index,
                    title: months == 1 ? draft.title : "\(draft.title) (分期 \(index + 1)/\(months))",
                    amount: installmentAmount,
                    kind: draft.kind,
                    happenedAt: date,
                    note: draft.note.isEmpty ? nil : draft.note,
                    merchant: draft.merchant.isEmpty ? nil : draft.merchant,
                    paymentMethod: draft.paymentMethod.isEmpty ? nil : draft.paymentMethod,
                    source: draft.source,
                    currency: "CNY",
                    categoryId: draft.categoryId,
                    categoryName: categoryName,
                    bookId: resolvedBook?.id,
                    bookName: bookName,
                    bookIds: resolvedBooks.map(\.id),
                    bookNames: resolvedBooks.map(\.name),
                    installmentGroupId: groupId,
                    installmentIndex: months > 1 ? index + 1 : nil,
                    installmentMonths: months > 1 ? months : nil,
                    installmentOriginalTotal: months > 1 ? amount : nil,
                    originalAmount: Double(draft.originalAmount),
                    discountAmount: Double(draft.discountAmount),
                    premiumAmount: Double(draft.premiumAmount),
                    paidByParticipantId: resolvedPayer?.id,
                    paidByParticipantName: resolvedPayer?.name,
                    splitParticipantIds: resolvedSplitParticipants.map(\.id),
                    splitParticipantNames: resolvedSplitParticipants.map(\.name)
                )
            )
        }

        nextTransactionId += months
        transactions = (created + transactions).sorted { $0.happenedAt > $1.happenedAt }
        refreshDerivedData()
        await persistAndMaybeSync(reason: "新增流水已保存")
    }

    func updateTransaction(_ id: Int, with draft: TransactionDraft) async {
        guard let amount = Double(draft.amount), !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            errorMessage = "请填写有效的标题和金额"
            return
        }

        guard let existingIndex = transactions.firstIndex(where: { $0.id == id }) else {
            errorMessage = "未找到要修改的流水"
            return
        }

        let existing = transactions[existingIndex]
        let resolvedBooks = resolveBooksForTransactionDraft(draft)
        let resolvedBook = resolvedBooks.first
        let selectedBook = resolvedBook
        let categoryName = resolvedCategoryName(for: draft.categoryId)
        let bookParticipants = selectedBook?.participants ?? []
        let resolvedSplitParticipants = bookParticipants.filter { draft.splitParticipantIds.contains($0.id) }
        let resolvedPayer = bookParticipants.first(where: { $0.id == draft.paidByParticipantId })

        if selectedBook?.splitEnabled == true {
            guard !resolvedSplitParticipants.isEmpty else {
                errorMessage = "账本流水请至少选择 1 位分账成员"
                return
            }
            guard resolvedPayer != nil else {
                errorMessage = "账本流水请先选择付款人"
                return
            }
        }

        transactions[existingIndex] = LedgerTransaction(
            id: existing.id,
            title: draft.title,
            amount: amount,
            kind: draft.kind,
            happenedAt: draft.happenedAt,
            note: draft.note.isEmpty ? nil : draft.note,
            merchant: draft.merchant.isEmpty ? nil : draft.merchant,
            paymentMethod: draft.paymentMethod.isEmpty ? nil : draft.paymentMethod,
            source: draft.source,
            currency: existing.currency,
            categoryId: draft.categoryId,
            categoryName: categoryName,
            bookId: resolvedBook?.id,
            bookName: resolvedBook?.name,
            bookIds: resolvedBooks.map(\.id),
            bookNames: resolvedBooks.map(\.name),
            installmentGroupId: existing.installmentGroupId,
            installmentIndex: existing.installmentIndex,
            installmentMonths: existing.installmentMonths,
            installmentOriginalTotal: existing.installmentOriginalTotal,
            originalAmount: Double(draft.originalAmount),
            discountAmount: Double(draft.discountAmount),
            premiumAmount: Double(draft.premiumAmount),
            paidByParticipantId: resolvedPayer?.id,
            paidByParticipantName: resolvedPayer?.name,
            splitParticipantIds: resolvedSplitParticipants.map(\.id),
            splitParticipantNames: resolvedSplitParticipants.map(\.name)
        )

        transactions.sort { $0.happenedAt > $1.happenedAt }
        refreshDerivedData()
        await persistAndMaybeSync(reason: "流水已更新")
    }

    @discardableResult
    func createBook(_ draft: BookDraft) async -> Int {
        let book = LedgerBook(
            id: nextBookId,



        name: draft.name,
        icon: draft.icon,
        color: draft.color,
        note: draft.note,
        startDate: draft.startDate,
        endDate: draft.endDate,
        autoCollectEnabled: draft.autoCollectEnabled,
        budgetLimitAmount: draft.budgetLimitAmount,
        budgetStartDate: draft.budgetStartDate,
        budgetEndDate: draft.budgetEndDate,
        expenseAmount: 0,
        incomeAmount: 0,
        balance: 0,
        transactionCount: 0,
        participantNames: draft.participantNames,
        isPinned: draft.isPinned,
        autoCollectCategoryIds: draft.autoCollectCategoryIds
      )
      nextBookId += 1
      books.insert(book, at: 0)
      refreshDerivedData()
      await persistAndMaybeSync(reason: "新账本已保存")
      return book.id
    }

  func updateBook(_ id: Int, with draft: BookDraft) async {
    guard let index = books.firstIndex(where: { $0.id == id }) else {
      let errorMessage = "未找到要修改的账本"
      return
    }

    let current = books[index]
    books[index] = LedgerBook(
      id: current.id,
      name: draft.name,
      icon: draft.icon,
      color: draft.color,
      note: draft.note,
      startDate: draft.startDate,
      endDate: draft.endDate,
      autoCollectEnabled: draft.autoCollectEnabled,
      budgetLimitAmount: draft.budgetLimitAmount,
      budgetStartDate: draft.budgetStartDate,
      budgetEndDate: draft.budgetEndDate,
      expenseAmount: current.expenseAmount,
      incomeAmount: current.incomeAmount,
      balance: current.balance,
      transactionCount: current.transactionCount,
      participantNames: draft.participantNames,
      isPinned: draft.isPinned,
      autoCollectCategoryIds: draft.autoCollectCategoryIds
    )

    transactions = transactions.map { tx in
      guard tx.bookIds.contains(id) || tx.bookId == id else { return tx }
      let updatedNames = tx.bookIds.enumerated().map { offset, bookID in
        if bookID == id { return draft.name }
        if let liveName = books.first(where: { $0.id == bookID })?.name {
          return liveName
        }
        if tx.bookNames.indices.contains(offset) {
          return tx.bookNames[offset]
        }
        return draft.name
      }
      return LedgerTransaction(
        id: tx.id,
        title: tx.title,
        amount: tx.amount,
        kind: tx.kind,
        happenedAt: tx.happenedAt,
        note: tx.note,
        merchant: tx.merchant,
        paymentMethod: tx.paymentMethod,
        source: tx.source,
        currency: tx.currency,
        categoryId: tx.categoryId,
        categoryName: tx.categoryName,
        bookId: tx.bookId,
        bookName: tx.bookId == id ? draft.name : tx.bookName,
        bookIds: tx.bookIds,
        bookNames: updatedNames,
        installmentGroupId: tx.installmentGroupId,
        installmentIndex: tx.installmentIndex,
        installmentMonths: tx.installmentMonths,
        installmentOriginalTotal: tx.installmentOriginalTotal,
        originalAmount: tx.originalAmount,
        discountAmount: tx.discountAmount,
        premiumAmount: tx.premiumAmount,
        paidByParticipantId: tx.paidByParticipantId,
        paidByParticipantName: tx.paidByParticipantName,
        splitParticipantIds: tx.splitParticipantIds,
        splitParticipantNames: tx.splitParticipantNames
      )
    }
    refreshDerivedData()
    await persistAndMaybeSync(reason: "账本已更新")
  }

  func assignTransaction(_ transactionId: Int, to bookId: Int) async {
    guard let txIndex = transactions.firstIndex(where: { $0.id == transactionId }),
          let book = books.first(where: { $0.id == bookId }) else { return }
    var ids = transactions[txIndex].bookIds
    var names = transactions[txIndex].bookNames
    if !ids.contains(bookId) {
      ids.append(bookId)
      names.append(book.name)
    }

    let primaryId = ids.first
    let primaryName = names.first
    transactions[txIndex] = rebuildTransaction(transactions[txIndex], bookId: primaryId, bookName: primaryName,
      bookIds: ids, bookNames: names)
    refreshDerivedData()
    await persistAndMaybeSync(reason: "已关联到账本")
  }

  func removeTransaction(_ transactionId: Int, from bookId: Int) async {
    guard let txIndex = transactions.firstIndex(where: { $0.id == transactionId }) else { return }
    var ids = transactions[txIndex].bookIds
    var names = transactions[txIndex].bookNames
    guard let removeIndex = ids.firstIndex(of: bookId) else { return }
    ids.remove(at: removeIndex)
    if names.indices.contains(removeIndex) { names.remove(at: removeIndex) }

    let primaryId = ids.first
    let primaryName = names.first
    transactions[txIndex] = rebuildTransaction(transactions[txIndex], bookId: primaryId, bookName: primaryName,
      bookIds: ids, bookNames: names)
    refreshDerivedData()
    await persistAndMaybeSync(reason: "已从账本中删除流水")
  }

  func collectTransactionsIntoBook(_ bookId: Int, includeAlreadyAssignedOnly: Bool = false) async {
    guard let book = books.first(where: { $0.id == bookId }) else { return }
    let matching = transactions.indices.filter { index in
      let tx = transactions[index]
      guard shouldAutoCollect(into: book, date: tx.happenedAt, categoryId: tx.categoryId) else { return false }
      if includeAlreadyAssignedOnly {
        return !tx.bookIds.isEmpty || tx.bookId != nil
      }
      return !tx.bookIds.contains(bookId)
    }

    for index in matching {
      var ids = transactions[index].bookIds
      var names = transactions[index].bookNames
      if !ids.contains(bookId) {
        ids.append(bookId)
        names.append(book.name)
        let primaryId = ids.first
        let primaryName = names.first
        transactions[index] = rebuildTransaction(transactions[index], bookId: primaryId, bookName: primaryName,
          bookIds: ids, bookNames: names)
      }
    }
    refreshDerivedData()
    await persistAndMaybeSync(reason: "已批量归集到账本")
  }

  func deleteBook(_ bookId: Int) async {
    guard let deletingBook = books.first(where: { $0.id == bookId }) else { return }
    books.removeAll { $0.id == bookId }
    budgets.removeAll { $0.name == deletingBook.name }

    transactions = transactions.map { tx in
      guard tx.bookIds.contains(bookId) || tx.bookId == bookId else { return tx }
      var ids = tx.bookIds
      var names = tx.bookNames
      if let index = ids.firstIndex(of: bookId) {
        ids.remove(at: index)
        if names.indices.contains(index) { names.remove(at: index) }
      }
      let primaryId = ids.first
      let primaryName = names.first
      return rebuildTransaction(tx, bookId: primaryId, bookName: primaryName, bookIds: ids, bookNames: names)
    }

    refreshDerivedData()
    await persistAndMaybeSync(reason: "账本已删除")
  }

  func setBookPinned(_ bookId: Int, pinned: Bool) async {
    guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }
    let current = books[index]
    books[index] = LedgerBook(
      id: current.id,
      name: current.name,
      icon: current.icon,
      color: current.color,
      note: current.note,
      startDate: current.startDate,
      endDate: current.endDate,
      autoCollectEnabled: current.autoCollectEnabled,
      budgetLimitAmount: current.budgetLimitAmount,
      budgetStartDate: current.budgetStartDate,
      budgetEndDate: current.budgetEndDate,
      expenseAmount: current.expenseAmount,
      incomeAmount: current.incomeAmount,
      balance: current.balance,
      transactionCount: current.transactionCount,
      participantNames: current.participantNames,
      isPinned: pinned,
      autoCollectCategoryIds: current.autoCollectCategoryIds
    )
    refreshDerivedData()
    await persistAndMaybeSync(reason: pinned ? "账本已置顶" : "已取消账本置顶")
  }

  func deleteTransaction(_ transactionId: Int) async {
    transactions.removeAll { $0.id == transactionId }
    refreshDerivedData()
    await persistAndMaybeSync(reason: "流水已删除")
  }

  func createBudget(_ draft: BudgetDraft) async {
    budgets.append(
      BudgetItem(
        id: nextBudgetId,
        name: draft.name,
        limitAmount: draft.limitAmount,
        periodType: draft.periodType,
        year: draft.year,
        month: draft.month,
        startDate: draft.startDate,
        endDate: draft.endDate,
        categoryId: draft.categoryId,
        categoryName: flattenedCategories.first(where: { $0.id == draft.categoryId })?.name,
        spentAmount: 0,
        usageRatio: 0
      )
    )
    nextBudgetId += 1
    refreshDerivedData()
    await persistAndMaybeSync(reason: "预算已保存")
  }

  func createCategory(_ draft: CategoryDraft) async {
    let parent = flattenedCategories.first(where: { $0.id == draft.parentId })
    let level = (parent?.level ?? 0) + 1
    let node = LedgerCategory(
      id: nextCategoryId,
      name: draft.name,
      flowType: draft.flowType,
      icon: draft.icon,
      color: draft.color,
      parentId: draft.parentId,
      level: level,
      children: []
    )
    nextCategoryId += 1
    categories = CategoryTreeBuilder.insert(node, into: categories)
    await persistAndMaybeSync(reason: "分类已保存")
  }

  func deleteCategory(_ categoryId: Int) async {
    guard let target = flattenedCategories.first(where: { $0.id == categoryId }) else { return }
    let removedIDs = Set(target.flattened().map(\.id))
    let fallback = selectableCategories.first { $0.flowType == target.flowType && $0.name.hasSuffix("未分类") && !removedIDs.contains($0.id) }
    categories = CategoryTreeBuilder.removing(ids: removedIDs, from: categories)
    transactions = transactions.map { transaction in
      guard let id = transaction.categoryId, removedIDs.contains(id) else { return transaction }
      return rebuildTransaction(transaction, bookId: transaction.bookId, bookName: transaction.bookName, bookIds: transaction.bookIds, bookNames: transaction.bookNames, categoryId: fallback?.id, categoryName: fallback?.name, replacingCategory: true)
    }
    refreshDerivedData()
    await persistAndMaybeSync(reason: "分类已删除，相关流水已归入未分类")
  }

  func appendExtendedDemoData() async {
    let existingBookNames = Set(books.map(\.name))
    let newBooks = DemoData.extendedBooks(startingAt: nextBookId)
      .filter { !existingBookNames.contains($0.name) }
    let booksEnd = (newBooks.map(\.id).max() ?? nextBookId - 1) + 1

    let existingBudgetNames = Set(budgets.map(\.name))
    let newBudgets = DemoData.extendedBudgets(categories: flattenedCategories, startingAt: nextBudgetId)
      .filter { !existingBudgetNames.contains($0.name) }
    let budgetsEnd = (newBudgets.map(\.id).max() ?? nextBudgetId - 1) + 1

    let mergedBooks = books + newBooks
    let newTransactions = DemoData.extendedTransactions(categories: flattenedCategories, books: mergedBooks,
      startingAt: nextTransactionId)
    let transactionsEnd = (newTransactions.map(\.id).max() ?? nextTransactionId - 1) + 1

    books = mergedBooks
    budgets += newBudgets
    transactions = (transactions + newTransactions).sorted { $0.happenedAt > $1.happenedAt }

    nextBookId = max(nextBookId, booksEnd)
    nextBudgetId = max(nextBudgetId, budgetsEnd)
    nextTransactionId = max(nextTransactionId, transactionsEnd)

    refreshDerivedData()
    await persistAndMaybeSync(reason: "已生成一批模拟数据")
  }

  func loadTransactions(in window: DateWindow) async throws -> [LedgerTransaction] {
    allTransactions(in: window)
  }

  func findCategory(bySuggestedPath path: [String]) -> LedgerCategory? {
    guard !path.isEmpty else { return nil }
    return selectableCategories.first(where: { $0.pathComponents == path || $0.displayName == path.last })
  }

  var flattenedCategories: [LedgerCategory] {
    categories.flatMap { $0.flattened() }
  }

  var selectableCategories: [LedgerCategory] {
    categories.flatMap { $0.selectableFlattened() }
  }

  func selectableCategories(for flowType: FlowType) -> [LedgerCategory] {
    selectableCategories.filter { $0.flowType == flowType }
  }

  func resolvedCategoryName(for categoryId: Int?) -> String? {
    guard let categoryId else { return nil }
    return selectableCategories.first(where: { $0.id == categoryId })?.name
      ?? flattenedCategories.first(where: { $0.id == categoryId })?.name
  }

  func recommendedBooks(for date: Date) -> [LedgerBook] {
    books
      .filter { matchesBookDateRange($0, date: date) }
      .sorted { lhs, rhs in
        let lhsRange = dateRangeSpan(of: lhs)
        let rhsRange = dateRangeSpan(of: rhs)
        if lhs.autoCollectEnabled != rhs.autoCollectEnabled {
          return lhs.autoCollectEnabled && !rhs.autoCollectEnabled
        }
        if lhsRange != rhsRange { return lhsRange < rhsRange }
        return lhs.id > rhs.id
      }
  }

  func recommendedBook(for date: Date) -> LedgerBook? {
    recommendedBooks(for: date).first
  }

  func shouldAutoCollect(into book: LedgerBook, date: Date, categoryId: Int? = nil) -> Bool {
    guard book.autoCollectEnabled, matchesBookDateRange(book, date: date) else { return false }
    guard !book.autoCollectCategoryIds.isEmpty else { return true }
    guard let categoryId else { return false }
    return matchesAutoCollectCategory(book: book, transactionCategoryId: categoryId)
  }

  func useLocalForSyncConflict() async {
    pendingRemoteSnapshot = nil
    pendingSyncConflict = nil
    syncState = .idle
    await pushToCloud()
  }

  func useRemoteForSyncConflict() async {
    guard let pendingRemoteSnapshot else { return }
    apply(pendingRemoteSnapshot)
    refreshDerivedData()
        do {
            try await localStore.save(pendingRemoteSnapshot)
            localUpdatedAt = pendingRemoteSnapshot.updatedAt
            lastSyncAt = Date()
            lastSyncMessage = "已采用 iCloud 版本覆盖本地"
            syncState = .success
        } catch {
            errorMessage = "应用远端版本失败: \(error.localizedDescription)"
            syncState = .failed
        }
        self.pendingRemoteSnapshot = nil
        pendingSyncConflict = nil
        await refreshDashboard(range: activeRangePreset, granularity: activeGranularity)
    }

    var categoryTrendPoints: [CategoryTrendChartPoint] {
        guard let categoryTrend else { return [] }
        return categoryTrend.series.flatMap { series in
            series.values.enumerated().compactMap { index, value in
                guard index < categoryTrend.labels.count else { return nil }
                return CategoryTrendChartPoint(category: series.category, label: categoryTrend.labels[index], value:
        value)
            }
        }
    }

    func dailySummaries(for month: Date, from transactions: [LedgerTransaction]) -> [Date: DailyFinanceSummary] {
        let interval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 31 * 24 * 60 * 60)

        let filtered = transactions.filter { interval.contains($0.happenedAt) }
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.happenedAt) }
        return grouped.mapValues { items in
            let income = items.filter { $0.kind == .income }.reduce(0.0) { $0 + $1.amount }
            let expense = items.filter { $0.kind == .expense }.reduce(0.0) { $0 + $1.amount }
            return DailyFinanceSummary(income: income, expense: expense)
        }
    }

    // MARK: - Apple account + iCloud sync

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "未获取到 Apple 账号凭证"
                return
            }
            let formatter = PersonNameComponentsFormatter()
            let fullName = credential.fullName.flatMap { formatter.string(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
            let profile = AppleAccountProfile(
                userIdentifier: credential.user,
                fullName: fullName ?? appleProfile?.fullName,
                email: credential.email ?? appleProfile?.email,
                authorizedAt: Date()
            )
            appleProfile = profile
            saveAppleProfile(profile)
            lastSyncMessage = "Apple 账号已绑定: \(profile.fullName ?? profile.email ?? profile.userIdentifier)"
        case .failure(let error):
            errorMessage = "Apple 登录失败: \(error.localizedDescription)"
        }
    }

    func clearAppleProfile() {
        appleProfile = nil
        UserDefaults.standard.removeObject(forKey: "smartledgerlocal.appleProfile")
    }

    func refreshCloudAccountState() async {
        syncState = .checking
        cloudAccountStatus = await cloudStore.accountStatus()
        cloudUserRecordName = await cloudStore.userRecordName()
        if syncState == .checking {
            syncState = .idle
        }
    }

    func smartSync(showSuccessMessage: Bool = true) async {
        syncState = .syncing
        await refreshCloudAccountState()
        guard cloudSyncEnabled else {
            lastSyncMessage = "云同步已关闭"
            syncState = .idle
            return
        }
        guard cloudAccountStatus == .available else {
            lastSyncMessage = "iCloud 当前不可用: \(cloudAccountStatus.title)"
            syncState = .idle
            return
        }
        do {
            let localSnapshot = currentSnapshot(markUpdatedAt: false)
            let remoteSnapshot = try await cloudStore.fetchSnapshot()
            if let remoteSnapshot {
                let interval = abs(remoteSnapshot.updatedAt.timeIntervalSince(localSnapshot.updatedAt))
                let localTransactionsData = try? JSONEncoder.iso8601.encode(localSnapshot.transactions)
                let remoteTransactionsData = try? JSONEncoder.iso8601.encode(remoteSnapshot.transactions)
                let diverged = remoteSnapshot.updatedAt != localSnapshot.updatedAt && localTransactionsData != remoteTransactionsData

                if diverged && interval < 300 {
                    pendingRemoteSnapshot = remoteSnapshot
                    pendingSyncConflict = SyncConflictSummary(
                        localUpdatedAt: localSnapshot.updatedAt,
                        remoteUpdatedAt: remoteSnapshot.updatedAt,
                        localTransactionCount: localSnapshot.transactions.count,
                        remoteTransactionCount: remoteSnapshot.transactions.count,
                        localBookCount: localSnapshot.books.count,
                        remoteBookCount: remoteSnapshot.books.count
                    )
                    lastSyncMessage = "检测到本地与 iCloud 同时有更新，请选择保留哪一份"
                    syncState = .conflict
                } else if remoteSnapshot.updatedAt > localSnapshot.updatedAt {
                    apply(remoteSnapshot)
                    refreshDerivedData()
                    localUpdatedAt = remoteSnapshot.updatedAt
                    try await localStore.save(remoteSnapshot)
                    lastSyncAt = Date()
                    lastSyncMessage = "已从 iCloud 拉取最新数据"
                } else if remoteSnapshot.updatedAt < localSnapshot.updatedAt {
                    let pushedSnapshot = currentSnapshot(markUpdatedAt: true)
                    try await cloudStore.pushSnapshot(pushedSnapshot)
                    try await localStore.save(pushedSnapshot)
                    localUpdatedAt = pushedSnapshot.updatedAt
                    lastSyncAt = Date()
                    lastSyncMessage = "已将本地更新推送到 iCloud"
                } else {
                    lastSyncAt = Date()
                    lastSyncMessage = "本地与 iCloud 已一致"
                }
            } else {
                let pushedSnapshot = currentSnapshot(markUpdatedAt: true)
                try await cloudStore.pushSnapshot(pushedSnapshot)
                try await localStore.save(pushedSnapshot)
                localUpdatedAt = pushedSnapshot.updatedAt
                lastSyncAt = Date()
                lastSyncMessage = "已初始化 iCloud 账本快照"
            }
            if syncState != .conflict {
                syncState = .success
            }
        } catch {
            errorMessage = "iCloud 同步失败: \(error.localizedDescription)"
            lastSyncMessage = "同步失败"
            syncState = .failed
        }

        if showSuccessMessage {
            await refreshDashboard(range: activeRangePreset, granularity: activeGranularity)
        }
    }

    func pushToCloud() async {
        syncState = .syncing
        await refreshCloudAccountState()
        guard cloudAccountStatus == .available else {
            lastSyncMessage = "无法推送: \(cloudAccountStatus.title)"
            syncState = .idle
            return
        }
        do {
            let snapshot = currentSnapshot(markUpdatedAt: true)
            try await cloudStore.pushSnapshot(snapshot)
            try await localStore.save(snapshot)
            apply(snapshot)
            localUpdatedAt = snapshot.updatedAt
            lastSyncAt = Date()
            lastSyncMessage = "已手动推送到 iCloud"
            syncState = .success
        } catch {
            errorMessage = "推送失败: \(error.localizedDescription)"
            syncState = .failed
        }
    }

    func pullFromCloud() async {
        syncState = .syncing
        await refreshCloudAccountState()
        guard cloudAccountStatus == .available else {
            lastSyncMessage = "无法拉取: \(cloudAccountStatus.title)"
            syncState = .idle
            return
        }
        do {
            guard let remote = try await cloudStore.fetchSnapshot() else {
                lastSyncMessage = "iCloud 还没有可拉取的数据"
                syncState = .idle
                return
            }
            apply(remote)
            refreshDerivedData()
            try await localStore.save(remote)
            localUpdatedAt = remote.updatedAt
            lastSyncAt = Date()
            lastSyncMessage = "已从 iCloud 拉取最新数据"
            syncState = .success
            await refreshDashboard(range: activeRangePreset, granularity: activeGranularity)
        } catch {
            errorMessage = "拉取失败: \(error.localizedDescription)"
            syncState = .failed
        }
    }

    func setCloudSyncEnabled(_ enabled: Bool) async {
        cloudSyncEnabled = enabled
        if enabled {
            lastSyncMessage = "已开启云同步，准备检查 iCloud 状态"
            await smartSync(showSuccessMessage: false)
        } else {
            syncState = .idle
            cloudAccountStatus = .unknown
            cloudUserRecordName = nil
            lastSyncMessage = "当前仅本地模式"
        }
    }

    // MARK: - Helpers

    private func seedLocalData() {
        categories = DemoData.defaultCategories()
        books = DemoData.defaultBooks()
        transactions = DemoData.defaultTransactions(categories: flattenedCategories, books: books)
        budgets = DemoData.defaultBudgets(categories: flattenedCategories, books: books)
        nextTransactionId = (transactions.map(\.id).max() ?? 0) + 1
        nextBookId = (books.map(\.id).max() ?? 0) + 1
        nextCategoryId = (flattenedCategories.map(\.id).max() ?? 0) + 1
        nextBudgetId = (budgets.map(\.id).max() ?? 0) + 1
        refreshDerivedData()
    }

    private func refreshDerivedData() {
        books = recomputeBookSummaries(from: books, transactions: transactions)
        budgets = LocalAnalytics.computeBudgetProgress(transactions: transactions, categories: flattenedCategories, budgets: budgets)
    }

    private func recomputeBookSummaries(from books: [LedgerBook], transactions: [LedgerTransaction]) -> [LedgerBook] {
        books.map { book in
            let scoped = transactions.filter { $0.bookIds.contains(book.id) || $0.bookId == book.id }
            let income = scoped.filter { $0.kind == .income }.reduce(0.0) { $0 + $1.amount }
            let expense = scoped.filter { $0.kind == .expense }.reduce(0.0) { $0 + $1.amount }
            return LedgerBook(
                id: book.id,
                name: book.name,
                icon: book.icon,
                color: book.color,
                note: book.note,
                startDate: book.startDate,
                endDate: book.endDate,
                autoCollectEnabled: book.autoCollectEnabled,
                budgetLimitAmount: book.budgetLimitAmount,
                budgetStartDate: book.budgetStartDate,
                budgetEndDate: book.budgetEndDate,
                expenseAmount: expense,
                incomeAmount: income,
                balance: income - expense,
                transactionCount: scoped.count,
                participantNames: book.participantNames,
                isPinned: book.isPinned,
                autoCollectCategoryIds: book.autoCollectCategoryIds
            )
        }
    }

    private func allTransactions(in window: DateWindow) -> [LedgerTransaction] {
        transactions.filter { $0.happenedAt >= window.start && $0.happenedAt < window.end }
    }

    private func matchesBookDateRange(_ book: LedgerBook, date: Date) -> Bool {
        if let start = book.startDate, Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: start) {
            return false
        }
        if let end = book.endDate,
           let endExclusive = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)),
           date >= endExclusive {
            return false
        }
        return book.startDate != nil || book.endDate != nil
    }

    private func dateRangeSpan(of book: LedgerBook) -> TimeInterval {
        let start = book.startDate ?? .distantPast
        let end = book.endDate ?? .distantFuture
        return end.timeIntervalSince(start)
    }

    private func resolveBookForTransactionDraft(_ draft: TransactionDraft) -> LedgerBook? {
        resolveBooksForTransactionDraft(draft).first
    }

    private func resolveBooksForTransactionDraft(_ draft: TransactionDraft) -> [LedgerBook] {
        let explicitlySelectedIds = !draft.bookIds.isEmpty ? draft.bookIds : (draft.bookId.map { [$0] } ?? [])
        if !explicitlySelectedIds.isEmpty {
            return books.filter { explicitlySelectedIds.contains($0.id) }
        }
        let autoCollected = recommendedBooks(for: draft.happenedAt).filter { shouldAutoCollect(into: $0, date: draft.happenedAt, categoryId: draft.categoryId) }
        guard !autoCollected.isEmpty else {
            return []
        }
        return autoCollected
    }

    private func matchesAutoCollectCategory(book: LedgerBook, transactionCategoryId: Int) -> Bool {
        if book.autoCollectCategoryIds.contains(transactionCategoryId) { return true }

        guard let transactionCategory = flattenedCategories.first(where: { $0.id == transactionCategoryId }) else {
            return false
        }
        for selectedCategoryId in book.autoCollectCategoryIds {
            guard let selectedCategory = flattenedCategories.first(where: { $0.id == selectedCategoryId }) else {
                continue
            }
            if transactionCategory.pathComponents.starts(with: selectedCategory.pathComponents) {
                return true
            }
        }
        return false
    }

    private func rebuildTransaction(_ tx: LedgerTransaction, bookId: Int?, bookName: String?, bookIds: [Int], bookNames:
[String], categoryId: Int? = nil, categoryName: String? = nil, replacingCategory: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: tx.id,
            title: tx.title,
            amount: tx.amount,
            kind: tx.kind,
            happenedAt: tx.happenedAt,
            note: tx.note,
            merchant: tx.merchant,
            paymentMethod: tx.paymentMethod,
            source: tx.source,
            currency: tx.currency,
            categoryId: replacingCategory ? categoryId : tx.categoryId,
            categoryName: replacingCategory ? categoryName : tx.categoryName,
            bookId: bookId,
            bookName: bookName,
            bookIds: bookIds,
            bookNames: bookNames,
            installmentGroupId: tx.installmentGroupId,
            installmentIndex: tx.installmentIndex,
            installmentMonths: tx.installmentMonths,
            installmentOriginalTotal: tx.installmentOriginalTotal,
            originalAmount: tx.originalAmount,
            discountAmount: tx.discountAmount,
            premiumAmount: tx.premiumAmount,
            paidByParticipantId: tx.paidByParticipantId,
            paidByParticipantName: tx.paidByParticipantName,
            splitParticipantIds: tx.splitParticipantIds,
            splitParticipantNames: tx.splitParticipantNames
        )
    }

    private func currentSnapshot(markUpdatedAt: Bool) -> PersistedLedgerSnapshot {
        let snapshotUpdatedAt = markUpdatedAt ? Date() : (localUpdatedAt ?? lastSyncAt ?? Date())
        return PersistedLedgerSnapshot(
            categories: categories,
            books: books,
            transactions: transactions,
            budgets: budgets,
            nextTransactionId: nextTransactionId,
            nextBookId: nextBookId,
            nextCategoryId: nextCategoryId,
            nextBudgetId: nextBudgetId,
            updatedAt: snapshotUpdatedAt
        )
    }

    private func apply(_ snapshot: PersistedLedgerSnapshot) {
        categories = snapshot.categories
        books = snapshot.books
        transactions = snapshot.transactions
        budgets = snapshot.budgets
        nextTransactionId = snapshot.nextTransactionId
        nextBookId = snapshot.nextBookId
        nextCategoryId = snapshot.nextCategoryId
        nextBudgetId = snapshot.nextBudgetId
        localUpdatedAt = snapshot.updatedAt
    }

    private func persistAndMaybeSync(reason: String) async {
        do {
            try await persistLocalSnapshot(markUpdatedAt: true)
            lastSyncMessage = reason
        } catch {
            errorMessage = "保存本地数据失败: \(error.localizedDescription)"
        }
        await refreshDashboard(range: activeRangePreset, granularity: activeGranularity)
        if cloudSyncEnabled { await smartSync(showSuccessMessage: false) }
    }

    private func persistLocalSnapshot(markUpdatedAt: Bool) async throws {
        let snapshot = currentSnapshot(markUpdatedAt: markUpdatedAt)
        try await localStore.save(snapshot)
        localUpdatedAt = snapshot.updatedAt
    }

    private func loadAppleProfileFromStorage() async {
        guard let data = UserDefaults.standard.data(forKey: "smartledgerlocal.appleProfile") else { return }
        appleProfile = try? JSONDecoder.iso8601.decode(AppleAccountProfile.self, from: data)
    }

    private func saveAppleProfile(_ profile: AppleAccountProfile) {
        if let data = try? JSONEncoder.iso8601.encode(profile) {
            UserDefaults.standard.set(data, forKey: "smartledgerlocal.appleProfile")
        }
    }

    private func validateAppleCredentialIfNeeded() async {
        guard let userIdentifier = appleProfile?.userIdentifier else { return }
        let provider = ASAuthorizationAppleIDProvider()
        let state: ASAuthorizationAppleIDProvider.CredentialState = await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: userIdentifier) { state, _ in
                continuation.resume(returning: state)
            }
        }
        if state == .revoked || state == .notFound {
            clearAppleProfile()
            lastSyncMessage = "已清理失效的 Apple 账号信息"
        }
    }
}

struct DailyFinanceSummary {
    let income: Double
    let expense: Double

    var balance: Double { income - expense }
    var intensity: Double { max(income, expense) }
}

private enum CategoryTreeBuilder {
    static func removing(ids: Set<Int>, from tree: [LedgerCategory]) -> [LedgerCategory] {
        tree.compactMap { item in
            guard !ids.contains(item.id) else { return nil }
            return LedgerCategory(id: item.id, name: item.name, flowType: item.flowType, icon: item.icon, color: item.color, parentId: item.parentId, level: item.level, children: removing(ids: ids, from: item.children))
        }
    }

    static func insert(_ node: LedgerCategory, into tree: [LedgerCategory]) -> [LedgerCategory] {
        guard let parentId = node.parentId else { return tree + [node] }
        return tree.map { item in
            if item.id == parentId {
                return LedgerCategory(id: item.id, name: item.name, flowType: item.flowType, icon: item.icon, color: item.color, parentId: item.parentId, level: item.level, children: item.children + [node])
            }
            guard !item.children.isEmpty else { return item }
            return LedgerCategory(id: item.id, name: item.name, flowType: item.flowType, icon: item.icon, color: item.color, parentId: item.parentId, level: item.level, children: insert(node, into: item.children))
        }
    }
}
