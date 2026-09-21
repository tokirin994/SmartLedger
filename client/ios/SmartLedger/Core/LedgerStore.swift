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
    @Published private(set) var hasPendingImportSelection = false
    @Published var categoryTrend: CategoryTrendResponse?
    @Published var activeRangePreset: DateRangePreset = .currentMonth
    @Published var activeCustomRange: CustomDateRange = .recent30Days
    @Published var activeGranularity: Granularity = .week
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var cloudSyncEnabled: Bool = UserDefaults.standard.object(forKey: "smartledgerlocal.cloudSyncEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(cloudSyncEnabled, forKey: "smartledgerlocal.cloudSyncEnabled") }
    }

    @Published var cloudSyncSchedule: CloudSyncSchedule = CloudSyncSchedule(rawValue: UserDefaults.standard.string(forKey: "smartledgerlocal.cloudSyncSchedule") ?? "periodic") ?? .periodic {
        didSet { UserDefaults.standard.set(cloudSyncSchedule.rawValue, forKey: "smartledgerlocal.cloudSyncSchedule") }
    }

    @Published var cloudAccountStatus: CloudAccountStatus = .unknown
    @Published var cloudUserRecordName: String?
    @Published var lastSyncAt: Date?
    @Published var lastSyncMessage: String = "尚未同步"
    @Published var cloudConnectionMessage: String = "尚未检查 WebDAV 连接"
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
    private var periodicSyncTask: Task<Void, Never>?
    private var lastSyncedFingerprint: String? = UserDefaults.standard.string(forKey: "smartledgerlocal.lastSyncedFingerprint")
    private var lastSyncedSnapshotUpdatedAt: Date? = {
        let stamp = UserDefaults.standard.double(forKey: "smartledgerlocal.lastSyncedSnapshotUpdatedAt")
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }()

    private var nextTransactionId = 1000
    private var nextBookId = 100
    private var nextCategoryId = 1000
    private var nextBudgetId = 100
    private var inFlightSaveKeys: Set<String> = []
    private var recentlyCompletedSaveKeys: [String: Date] = [:]

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

        if installSupplementalDefaultSubcategoriesIfNeeded() {
            try? await persistLocalSnapshot(markUpdatedAt: true)
        }

        refreshDerivedData()

        if cloudSyncEnabled {
            if cloudSyncSchedule != .onChange {
                await smartSync(showSuccessMessage: false)
            }
            configureScheduledSyncIfNeeded()
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
        hasPendingImportSelection = true
        let result = parser.parse(rawText: text)
        parsedImport = result
        let multiple = parser.parseMultiple(rawText: text)
        parsedImportItems = multiple.isEmpty ? [result] : multiple
    }

    /// Parses several screenshots as one review batch. Each image may contain
    /// one or many transactions; all candidates are kept in the same editable
    /// confirmation list so the user can select, edit, or discard individually.
    func parseOCRBatch(texts: [String]) async {
        hasPendingImportSelection = true
        let candidates = texts.flatMap { text -> [OCRImportResult] in
            let multiple = parser.parseMultiple(rawText: text)
            return multiple.isEmpty ? [parser.parse(rawText: text)] : multiple
        }
        setPendingImportItems(candidates)
    }

    func setPendingImportItems(_ items: [OCRImportResult]) {
        hasPendingImportSelection = !items.isEmpty
        parsedImportItems = items
        parsedImport = items.first
    }

    func beginImportSelection() {
        hasPendingImportSelection = true
    }

    func clearOCRImport() {
        hasPendingImportSelection = false
        parsedImport = nil
        parsedImportItems = []
    }

    var hasPendingOCRImport: Bool {
        hasPendingImportSelection || parsedImport != nil || !parsedImportItems.isEmpty
    }

    func createTransaction(_ draft: TransactionDraft) async {
        let saveKey = "transaction|\(draft.kind.rawValue)|\(draft.title.trimmingCharacters(in: .whitespacesAndNewlines))|\(draft.amount)|\(draft.happenedAt.timeIntervalSince1970.rounded())|\(draft.categoryId ?? -1)|\(draft.bookIds.sorted())"
        guard beginSave(key: saveKey) else { return }
        defer { endSave(key: saveKey) }
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
        let autoCollectBookSplit = selectedBook?.autoCollectEnabled == true && selectedBook?.splitEnabled == true
        let defaultOwnParticipant = autoCollectBookSplit
            && draft.splitParticipantIds.isEmpty
            ? (bookParticipants.first(where: { $0.name == "我" }) ?? bookParticipants.first)
            : nil
        let resolvedSplitParticipants = defaultOwnParticipant.map { [$0] }
            ?? bookParticipants.filter { draft.splitParticipantIds.contains($0.id) }
        let resolvedPayer = bookParticipants.first(where: { $0.id == draft.paidByParticipantId })
            ?? defaultOwnParticipant
        let unboundSplit = selectedBook == nil && draft.splitParticipantIds.count > 1
        let resolvedSplitParticipantIDs = selectedBook == nil
            ? (unboundSplit ? draft.splitParticipantIds : [])
            : resolvedSplitParticipants.map(\.id)
        let resolvedSplitParticipantNames = selectedBook == nil
            ? (unboundSplit ? draft.splitParticipantIds : [])
            : resolvedSplitParticipants.map(\.name)

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
                    splitParticipantIds: resolvedSplitParticipantIDs,
                    splitParticipantNames: resolvedSplitParticipantNames
                )
            )
        }

        // Offsets are independent income records. A legacy single offset is
        // converted to one entry so OCR/import drafts remain backward compatible.
        let requestedOffsets: [OffsetDraft]
        if !draft.offsets.isEmpty {
            requestedOffsets = draft.offsets
        } else if draft.offsetEnabled, let categoryId = draft.offsetCategoryId {
            requestedOffsets = [OffsetDraft(categoryId: categoryId, ratio: draft.offsetRatio, happenedAt: draft.happenedAt)]
        } else {
            requestedOffsets = []
        }
        let sourceTransactionId = created.first?.id
        for offset in requestedOffsets where draft.kind == .expense {
            guard let offsetCategoryId = offset.categoryId,
                  let offsetCategory = flattenedCategories.first(where: { $0.id == offsetCategoryId && $0.flowType == .income }) else { continue }
            let offsetAmount = (amount * max(offset.ratio, 0) / 100 * 100).rounded() / 100
            guard offsetAmount > 0 else { continue }
            created.append(LedgerTransaction(
                id: nextTransactionId + created.count, title: draft.title, amount: offsetAmount, kind: .income,
                happenedAt: offset.happenedAt, note: draft.note.isEmpty ? "抵扣流水" : draft.note,
                merchant: draft.merchant.isEmpty ? nil : draft.merchant,
                paymentMethod: draft.paymentMethod.isEmpty ? nil : draft.paymentMethod, source: offsetSourceMarker(sourceTransactionId, original: draft.source), currency: "CNY",
                categoryId: offsetCategory.id, categoryName: resolvedCategoryName(for: offsetCategory.id),
                bookId: resolvedBook?.id, bookName: bookName, bookIds: resolvedBooks.map(\.id), bookNames: resolvedBooks.map(\.name),
                installmentGroupId: nil, installmentIndex: nil, installmentMonths: nil,
                paidByParticipantId: resolvedPayer?.id, paidByParticipantName: resolvedPayer?.name,
                splitParticipantIds: resolvedSplitParticipantIDs, splitParticipantNames: resolvedSplitParticipantNames,
                installmentOriginalTotal: nil, originalAmount: nil, discountAmount: nil, premiumAmount: nil,
                installmentStartMonth: nil,
                offsetSourceTransactionId: sourceTransactionId
            ))
        }
        nextTransactionId += created.count
        transactions = (created + transactions).sorted { $0.happenedAt > $1.happenedAt }
        refreshDerivedData()
        await persistAndMaybeSync(reason: "新增流水已保存")
        completeSave(key: saveKey)
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
        let autoCollectBookSplit = selectedBook?.autoCollectEnabled == true && selectedBook?.splitEnabled == true
        let defaultOwnParticipant = autoCollectBookSplit
            && draft.splitParticipantIds.isEmpty
            ? (bookParticipants.first(where: { $0.name == "我" }) ?? bookParticipants.first)
            : nil
        let resolvedSplitParticipants = defaultOwnParticipant.map { [$0] }
            ?? bookParticipants.filter { draft.splitParticipantIds.contains($0.id) }
        let resolvedPayer = bookParticipants.first(where: { $0.id == draft.paidByParticipantId })
            ?? defaultOwnParticipant
        let unboundSplit = selectedBook == nil && draft.splitParticipantIds.count > 1
        let resolvedSplitParticipantIDs = selectedBook == nil
            ? (unboundSplit ? draft.splitParticipantIds : [])
            : resolvedSplitParticipants.map(\.id)
        let resolvedSplitParticipantNames = selectedBook == nil
            ? (unboundSplit ? draft.splitParticipantIds : [])
            : resolvedSplitParticipants.map(\.name)

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

        let convertingToInstallments = existing.installmentGroupId == nil
            && draft.installmentEnabled
            && draft.installmentMonths > 1
        if convertingToInstallments {
            let months = max(draft.installmentMonths, 2)
            let groupId = UUID().uuidString
            let baseDate = draft.installmentStartMonth
            let eachAmount = (amount / Double(months) * 100).rounded() / 100
            var accumulated = 0.0
            var installmentRows: [LedgerTransaction] = []

            for index in 0..<months {
                let installmentAmount: Double
                if index == months - 1 {
                    installmentAmount = ((amount - accumulated) * 100).rounded() / 100
                } else {
                    installmentAmount = eachAmount
                }
                accumulated += installmentAmount
                let date = calendar.date(byAdding: .month, value: index, to: baseDate) ?? baseDate
                let transactionID = index == 0 ? existing.id : nextTransactionId + index - 1
                installmentRows.append(LedgerTransaction(
                    id: transactionID,
                    title: "\(draft.title) (分期 \(index + 1)/\(months))",
                    amount: installmentAmount,
                    kind: draft.kind,
                    happenedAt: date,
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
                    installmentGroupId: groupId,
                    installmentIndex: index + 1,
                    installmentMonths: months,
                    paidByParticipantId: resolvedPayer?.id,
                    paidByParticipantName: resolvedPayer?.name,
                    splitParticipantIds: resolvedSplitParticipantIDs,
                    splitParticipantNames: resolvedSplitParticipantNames,
                    installmentOriginalTotal: amount,
                    originalAmount: Double(draft.originalAmount),
                    discountAmount: Double(draft.discountAmount),
                    premiumAmount: Double(draft.premiumAmount),
                    installmentStartMonth: baseDate,
                    offsetSourceTransactionId: existing.offsetSourceTransactionId
                ))
            }

            transactions.removeAll { $0.id == existing.id }
            transactions.append(contentsOf: installmentRows)
            nextTransactionId += max(months - 1, 0)
            synchronizeLinkedOffsets(sourceID: existing.id, with: installmentRows[0])
            transactions.sort { $0.happenedAt > $1.happenedAt }
            refreshDerivedData()
            await persistAndMaybeSync(reason: "流水已拆分为分期")
            return
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
            paidByParticipantId: resolvedPayer?.id,
            paidByParticipantName: resolvedPayer?.name,
            splitParticipantIds: resolvedSplitParticipantIDs,
            splitParticipantNames: resolvedSplitParticipantNames,
            installmentOriginalTotal: existing.installmentOriginalTotal,
            originalAmount: Double(draft.originalAmount),
            discountAmount: Double(draft.discountAmount),
            premiumAmount: Double(draft.premiumAmount),
            installmentStartMonth: existing.installmentStartMonth,
            offsetSourceTransactionId: existing.offsetSourceTransactionId
        )

        synchronizeLinkedOffsets(sourceID: existing.id, with: transactions[existingIndex])

        transactions.sort { $0.happenedAt > $1.happenedAt }
        refreshDerivedData()
        await persistAndMaybeSync(reason: "流水已更新")
    }

    /// Adds reimbursement/refund records to an existing expense without
    /// mutating its amount or creating a duplicate source transaction.
    func createOffsets(for transactionId: Int, offsets: [OffsetDraft]) async {
        guard let source = transactions.first(where: { $0.id == transactionId }), source.kind == .expense else {
            errorMessage = "未找到可抵扣的支出流水"
            return
        }
        let validOffsets = offsets.filter { ($0.categoryId != nil) && $0.ratio > 0 }
        guard !validOffsets.isEmpty else { return }
        let saveKey = "offset|\(transactionId)|\(validOffsets.map { "\($0.categoryId ?? -1)-\($0.ratio)-\($0.happenedAt.timeIntervalSince1970.rounded())" }.joined(separator: "|"))"
        guard beginSave(key: saveKey) else { return }
        defer { endSave(key: saveKey) }

        var generated: [LedgerTransaction] = []
        for offset in validOffsets {
            guard let categoryId = offset.categoryId,
                  let category = flattenedCategories.first(where: { $0.id == categoryId && $0.flowType == .income }) else { continue }
            let amount = (source.amount * offset.ratio / 100 * 100).rounded() / 100
            guard amount > 0 else { continue }
            generated.append(LedgerTransaction(
                id: nextTransactionId + generated.count,
                title: source.title,
                amount: amount,
                kind: .income,
                happenedAt: offset.happenedAt,
                note: source.note?.isEmpty == false ? source.note : "抵扣流水",
                merchant: source.merchant,
                paymentMethod: source.paymentMethod,
                source: offsetSourceMarker(source.id, original: source.source),
                currency: source.currency,
                categoryId: category.id,
                categoryName: resolvedCategoryName(for: category.id),
                bookId: source.bookId,
                bookName: source.bookName,
                bookIds: source.bookIds,
                bookNames: source.bookNames,
                installmentGroupId: nil,
                installmentIndex: nil,
                installmentMonths: nil,
                paidByParticipantId: source.paidByParticipantId,
                paidByParticipantName: source.paidByParticipantName,
                splitParticipantIds: source.splitParticipantIds,
                splitParticipantNames: source.splitParticipantNames,
                installmentOriginalTotal: nil,
                originalAmount: nil,
                discountAmount: nil,
                premiumAmount: nil,
                installmentStartMonth: nil,
                offsetSourceTransactionId: source.id
            ))
        }
        guard !generated.isEmpty else { return }
        nextTransactionId += generated.count
        transactions = (generated + transactions).sorted { $0.happenedAt > $1.happenedAt }
        refreshDerivedData()
        await persistAndMaybeSync(reason: "抵扣流水已保存")
        completeSave(key: saveKey)
    }

    @discardableResult
    func createBook(_ draft: BookDraft) async -> Int {
        let saveKey = "book|\(draft.name.trimmingCharacters(in: .whitespacesAndNewlines))|\(draft.startDate?.timeIntervalSince1970 ?? 0)|\(draft.endDate?.timeIntervalSince1970 ?? 0)"
        guard beginSave(key: saveKey) else { return books.first(where: { $0.name == draft.name })?.id ?? -1 }
        defer { endSave(key: saveKey) }
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
      completeSave(key: saveKey)
      return book.id
    }

  func updateBook(_ id: Int, with draft: BookDraft) async {
    guard let index = books.firstIndex(where: { $0.id == id }) else {
      errorMessage = "无法保存账本：未找到要修改的账本。"
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
        paidByParticipantId: tx.paidByParticipantId,
        paidByParticipantName: tx.paidByParticipantName,
        splitParticipantIds: tx.splitParticipantIds,
        splitParticipantNames: tx.splitParticipantNames,
        installmentOriginalTotal: tx.installmentOriginalTotal,
        originalAmount: tx.originalAmount,
        discountAmount: tx.discountAmount,
        premiumAmount: tx.premiumAmount,
        installmentStartMonth: tx.installmentStartMonth,
        offsetSourceTransactionId: tx.offsetSourceTransactionId
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
      guard shouldAutoCollect(into: book, date: tx.happenedAt, categoryId: tx.categoryId, kind: tx.kind) else { return false }
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
        let own = book.splitEnabled && transactions[index].splitParticipantIds.isEmpty
          ? (book.participants.first(where: { $0.name == "我" }) ?? book.participants.first)
          : nil
        transactions[index] = rebuildTransaction(transactions[index], bookId: primaryId, bookName: primaryName,
          bookIds: ids, bookNames: names,
          defaultSplitParticipantId: own?.id, defaultSplitParticipantName: own?.name)
      }
    }
    refreshDerivedData()
    await persistAndMaybeSync(reason: "已批量归集到账本")
  }

  func applyAutoCollectRules(
    to bookId: Int,
    removeNonMatchingExisting: Bool,
    collectUnassignedNow: Bool
  ) async {
    guard let book = books.first(where: { $0.id == bookId }) else {
      errorMessage = "无法应用归集规则：账本不存在。"
      return
    }

    if removeNonMatchingExisting {
      for index in transactions.indices where transactions[index].bookIds.contains(bookId) || transactions[index].bookId == bookId {
        let transaction = transactions[index]
        guard !shouldAutoCollect(into: book, date: transaction.happenedAt, categoryId: transaction.categoryId, kind: transaction.kind) else { continue }
        var ids = transaction.bookIds
        var names = transaction.bookNames
        if let position = ids.firstIndex(of: bookId) {
          ids.remove(at: position)
          if names.indices.contains(position) { names.remove(at: position) }
          transactions[index] = rebuildTransaction(transaction, bookId: ids.first, bookName: names.first, bookIds: ids, bookNames: names)
        }
      }
    }

    if collectUnassignedNow {
      for index in transactions.indices {
        let transaction = transactions[index]
        guard !transaction.bookIds.contains(bookId),
              shouldAutoCollect(into: book, date: transaction.happenedAt, categoryId: transaction.categoryId, kind: transaction.kind) else { continue }
        var ids = transaction.bookIds
        var names = transaction.bookNames
        ids.append(bookId)
        names.append(book.name)
        let own = book.splitEnabled && transaction.splitParticipantIds.isEmpty
          ? (book.participants.first(where: { $0.name == "我" }) ?? book.participants.first)
          : nil
        transactions[index] = rebuildTransaction(transaction, bookId: ids.first, bookName: names.first, bookIds: ids, bookNames: names,
          defaultSplitParticipantId: own?.id, defaultSplitParticipantName: own?.name)
      }
    }

    refreshDerivedData()
    await persistAndMaybeSync(reason: "自动归集规则已应用")
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
    // A reimbursement/refund is a child of its source expense. Deleting the
    // source must remove those generated records as well, including records
    // loaded from older SwiftData stores that only have the source marker.
    let linkedIDs = Set(transactions.filter { $0.linkedOffsetSourceID == transactionId }.map(\.id))
    let idsToDelete = linkedIDs.union([transactionId])
    transactions.removeAll { idsToDelete.contains($0.id) }
    refreshDerivedData()
    await persistAndMaybeSync(reason: "流水已删除")
  }

  /// Merges every installment in a group into the original transaction and
  /// clears its installment metadata. This is intentionally an explicit
  /// action from the edit screen; changing an existing amount never creates a
  /// new installment group behind the user's back.
  func cancelInstallment(for transactionId: Int) async {
    guard let current = transactions.first(where: { $0.id == transactionId }),
          let groupID = current.installmentGroupId else {
      errorMessage = "这笔流水不是分期流水。"
      return
    }
    let group = transactions.filter { $0.installmentGroupId == groupID }
    guard group.count > 1 else {
      errorMessage = "未找到可合并的分期记录。"
      return
    }
    let representative = group.sorted { ($0.installmentIndex ?? 0) < ($1.installmentIndex ?? 0) }.first ?? current
    let groupIDs = Set(group.map(\.id))
    let total = group.reduce(0) { $0 + $1.amount }
    let title = installmentBaseTitle(representative.title)
    let merged = LedgerTransaction(
      id: representative.id,
      title: title,
      amount: (total * 100).rounded() / 100,
      kind: representative.kind,
      happenedAt: group.map(\.happenedAt).min() ?? representative.happenedAt,
      note: representative.note,
      merchant: representative.merchant,
      paymentMethod: representative.paymentMethod,
      source: representative.source,
      currency: representative.currency,
      categoryId: representative.categoryId,
      categoryName: representative.categoryName,
      bookId: representative.bookId,
      bookName: representative.bookName,
      bookIds: representative.bookIds,
      bookNames: representative.bookNames,
      installmentGroupId: nil,
      installmentIndex: nil,
      installmentMonths: nil,
      paidByParticipantId: representative.paidByParticipantId,
      paidByParticipantName: representative.paidByParticipantName,
      splitParticipantIds: representative.splitParticipantIds,
      splitParticipantNames: representative.splitParticipantNames,
      installmentOriginalTotal: nil,
      originalAmount: representative.originalAmount,
      discountAmount: representative.discountAmount,
      premiumAmount: representative.premiumAmount,
      installmentStartMonth: nil,
      offsetSourceTransactionId: representative.offsetSourceTransactionId
    )

    var rebuilt = transactions.filter { !groupIDs.contains($0.id) }
    // Keep refunds attached to the surviving representative. Refunds for a
    // removed installment are moved to that representative instead of being
    // orphaned.
    for offset in rebuilt where groupIDs.contains(offset.linkedOffsetSourceID ?? -1) && offset.linkedOffsetSourceID != representative.id {
      if let index = rebuilt.firstIndex(where: { $0.id == offset.id }) {
        rebuilt[index] = rebuildTransaction(offset, bookId: offset.bookId, bookName: offset.bookName,
          bookIds: offset.bookIds, bookNames: offset.bookNames,
          source: offsetSourceMarker(representative.id, original: offset.source),
          offsetSourceTransactionId: representative.id)
      }
    }
    rebuilt.append(merged)
    transactions = rebuilt.sorted { $0.happenedAt > $1.happenedAt }
    refreshDerivedData()
    await persistAndMaybeSync(reason: "已取消分期并合并流水")
  }

  /// Creates one payment at the current time for all not-yet-due installments
  /// and removes those future installment rows so they cannot be counted twice.
  func payOffInstallment(for transactionId: Int) async {
    guard let current = transactions.first(where: { $0.id == transactionId }),
          let groupID = current.installmentGroupId else {
      errorMessage = "这笔流水不是分期流水。"
      return
    }
    let marker = "installment_payoff:\(groupID)"
    guard !transactions.contains(where: { $0.source == marker }) else {
      errorMessage = "这笔分期已经立即还清。"
      return
    }
    let now = Date()
    let future = transactions.filter { $0.installmentGroupId == groupID && $0.happenedAt > now }
    let remaining = future.reduce(0) { $0 + $1.amount }
    guard remaining > 0 else {
      errorMessage = "没有尚未到期的分期可立即还清。"
      return
    }
    let removeIDs = Set(future.map(\.id))
    let linkedOffsetIDs = Set(transactions.filter { removeIDs.contains($0.linkedOffsetSourceID ?? -1) }.map(\.id))
    let payoff = LedgerTransaction(
      id: nextTransactionId,
      title: "\(installmentBaseTitle(current.title))（立即还清）",
      amount: (remaining * 100).rounded() / 100,
      kind: current.kind,
      happenedAt: now,
      note: [current.note, "分期立即还清"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
      merchant: current.merchant,
      paymentMethod: current.paymentMethod,
      source: marker,
      currency: current.currency,
      categoryId: current.categoryId,
      categoryName: current.categoryName,
      bookId: current.bookId,
      bookName: current.bookName,
      bookIds: current.bookIds,
      bookNames: current.bookNames,
      installmentGroupId: nil,
      installmentIndex: nil,
      installmentMonths: nil,
      paidByParticipantId: current.paidByParticipantId,
      paidByParticipantName: current.paidByParticipantName,
      splitParticipantIds: current.splitParticipantIds,
      splitParticipantNames: current.splitParticipantNames,
      installmentOriginalTotal: nil,
      originalAmount: current.originalAmount,
      discountAmount: current.discountAmount,
      premiumAmount: current.premiumAmount,
      installmentStartMonth: nil,
      offsetSourceTransactionId: nil
    )
    nextTransactionId += 1
    transactions.removeAll { removeIDs.contains($0.id) || linkedOffsetIDs.contains($0.id) }
    transactions.append(payoff)
    transactions.sort { $0.happenedAt > $1.happenedAt }
    refreshDerivedData()
    await persistAndMaybeSync(reason: "分期已立即还清")
  }

  func createBudget(_ draft: BudgetDraft) async {
    let saveKey = "budget|\(draft.name)|\(draft.limitAmount)|\(draft.categoryId ?? -1)|\(draft.startDate?.timeIntervalSince1970 ?? 0)|\(draft.endDate?.timeIntervalSince1970 ?? 0)"
    guard beginSave(key: saveKey) else { return }
    defer { endSave(key: saveKey) }
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
    completeSave(key: saveKey)
  }

  func createCategory(_ draft: CategoryDraft) async {
    let saveKey = "category|\(draft.flowType.rawValue)|\(draft.parentId ?? -1)|\(draft.name.trimmingCharacters(in: .whitespacesAndNewlines))"
    guard beginSave(key: saveKey) else { return }
    defer { endSave(key: saveKey) }
    let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      errorMessage = "分类名称不能为空。"
      return
    }
    if flattenedCategories.contains(where: { $0.parentId == draft.parentId && $0.flowType == draft.flowType && $0.pathComponents.last == name }) {
      errorMessage = "同一上级分类下已存在“\(name)”。"
      return
    }
    let parent = flattenedCategories.first(where: { $0.id == draft.parentId })
    let level = (parent?.level ?? 0) + 1
    let node = LedgerCategory(
      id: nextCategoryId,
      name: name,
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
    completeSave(key: saveKey)
  }

  /// Keeps the category ID unchanged, so existing transaction/budget bindings remain valid.
  func updateCategory(_ categoryId: Int, draft: CategoryDraft) async {
    let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { errorMessage = "分类名称不能为空。"; return }
    guard let current = flattenedCategories.first(where: { $0.id == categoryId }) else { return }
    if flattenedCategories.contains(where: { $0.id != categoryId && $0.parentId == current.parentId && $0.flowType == current.flowType && $0.pathComponents.last == name }) {
      errorMessage = "同一上级分类下已存在“\(name)”。"
      return
    }
    categories = CategoryTreeBuilder.replacing(categoryId: categoryId, in: categories) { old in
      LedgerCategory(id: old.id, name: name, flowType: old.flowType, icon: draft.icon, color: draft.color, parentId: old.parentId, level: old.level, children: old.children)
    }
    transactions = transactions.map { tx in
      guard tx.categoryId == categoryId else { return tx }
      return rebuildTransaction(tx, bookId: tx.bookId, bookName: tx.bookName, bookIds: tx.bookIds, bookNames: tx.bookNames, categoryId: categoryId, categoryName: name, replacingCategory: true)
    }
    refreshDerivedData()
    await persistAndMaybeSync(reason: "分类已修改")
  }

  func deleteCategory(_ categoryId: Int) async {
    // 必须从原始树取节点；flattenedCategories 会将 children 展平为空数组。
    guard let target = categoryTreeNode(withID: categoryId, in: categories) else { return }
    guard target.children.isEmpty else {
      errorMessage = "“\(target.name)”下还有子分类，不能删除。请先处理或删除其子分类。"
      return
    }
    let collectingBooks = books.filter {
      $0.autoCollectEnabled && $0.autoCollectCategoryIds.contains(target.id)
    }
    guard collectingBooks.isEmpty else {
      let names = collectingBooks.map(\.name).joined(separator: "、")
      errorMessage = "“\(target.name)”正在被账本“\(names)”的自动归集使用，无法删除。请先在账本设置中移除该归集分类。"
      return
    }

    // 删除叶子分类时，流水回退至直属上级；一级分类没有上级时回退为未分类（nil）。
    let parent = target.parentId.flatMap { parentID in
      flattenedCategories.first(where: { $0.id == parentID })
    }
    categories = CategoryTreeBuilder.removing(ids: [target.id], from: categories)
    transactions = transactions.map { transaction in
      guard transaction.categoryId == target.id else { return transaction }
      return rebuildTransaction(transaction, bookId: transaction.bookId, bookName: transaction.bookName, bookIds: transaction.bookIds, bookNames: transaction.bookNames, categoryId: parent?.id, categoryName: parent?.name, replacingCategory: true)
    }
    refreshDerivedData()
    let destination = parent?.name ?? "未分类"
    await persistAndMaybeSync(reason: "分类已删除，相关流水已归入\(destination)")
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

  private func categoryTreeNode(withID id: Int, in nodes: [LedgerCategory]) -> LedgerCategory? {
    for node in nodes {
      if node.id == id { return node }
      if let child = categoryTreeNode(withID: id, in: node.children) {
        return child
      }
    }
    return nil
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

  func shouldAutoCollect(into book: LedgerBook, date: Date, categoryId: Int? = nil, kind: FlowType? = nil) -> Bool {
    guard book.autoCollectEnabled, matchesBookDateRange(book, date: date) else { return false }
    guard !book.autoCollectCategoryIds.isEmpty else { return true }
    // Negative IDs are stable rule tokens instead of category IDs. They avoid
    // fabricating visible categories just to represent “all expenses/income”.
    if book.autoCollectCategoryIds.contains(-1), kind == .expense { return true }
    if book.autoCollectCategoryIds.contains(-2), kind == .income { return true }
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
            markSnapshotSynced(pendingRemoteSnapshot)
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
            let income = items.filter { $0.kind == .income }.reduce(0.0) { $0 + $1.selfShareAmount }
            let expense = items.filter { $0.kind == .expense }.reduce(0.0) { $0 + $1.selfShareAmount }
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
        let check = await cloudStore.checkConfiguration()
        cloudAccountStatus = check.status
        cloudConnectionMessage = check.message
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
            lastSyncMessage = "坚果云当前不可用: \(cloudAccountStatus.title)"
            syncState = .idle
            return
        }
        do {
            let localSnapshot = currentSnapshot(markUpdatedAt: false)
            let remoteSnapshot = try await cloudStore.fetchSnapshot()
            if let remoteSnapshot {
                let localFingerprint = snapshotContentFingerprint(localSnapshot)
                let remoteFingerprint = snapshotContentFingerprint(remoteSnapshot)
                if localFingerprint == remoteFingerprint {
                    markSnapshotSynced(localSnapshot)
                    lastSyncAt = Date()
                    lastSyncMessage = "本地与坚果云已一致"
                } else if let lastSyncedFingerprint,
                          localFingerprint != lastSyncedFingerprint,
                          remoteFingerprint != lastSyncedFingerprint,
                          hasBothSidesChangedSinceLastAgreement(local: localSnapshot, remote: remoteSnapshot) {
                    // A real conflict means both sides changed since their shared base.
                    // Timestamp proximity alone caused normal consecutive saves to be
                    // incorrectly presented as conflicts.
                    pendingRemoteSnapshot = remoteSnapshot
                    pendingSyncConflict = SyncConflictSummary(
                        localUpdatedAt: localSnapshot.updatedAt,
                        remoteUpdatedAt: remoteSnapshot.updatedAt,
                        localTransactionCount: localSnapshot.transactions.count,
                        remoteTransactionCount: remoteSnapshot.transactions.count,
                        localBookCount: localSnapshot.books.count,
                        remoteBookCount: remoteSnapshot.books.count
                    )
                    lastSyncMessage = "检测到本地与坚果云同时有更新，请选择保留哪一份"
                    syncState = .conflict
                } else if localFingerprint == lastSyncedFingerprint || remoteSnapshot.updatedAt > localSnapshot.updatedAt {
                    apply(remoteSnapshot)
                    refreshDerivedData()
                    localUpdatedAt = remoteSnapshot.updatedAt
                    try await localStore.save(remoteSnapshot)
                    markSnapshotSynced(remoteSnapshot)
                    lastSyncAt = Date()
                    lastSyncMessage = "已从坚果云拉取最新数据"
                } else {
                    let pushedSnapshot = currentSnapshot(markUpdatedAt: true)
                    try await cloudStore.pushSnapshot(pushedSnapshot)
                    try await localStore.save(pushedSnapshot)
                    localUpdatedAt = pushedSnapshot.updatedAt
                    markSnapshotSynced(pushedSnapshot)
                    lastSyncAt = Date()
                    lastSyncMessage = "已将本地更新推送到坚果云"
                }
            } else {
                let pushedSnapshot = currentSnapshot(markUpdatedAt: true)
                try await cloudStore.pushSnapshot(pushedSnapshot)
                try await localStore.save(pushedSnapshot)
                localUpdatedAt = pushedSnapshot.updatedAt
                markSnapshotSynced(pushedSnapshot)
                lastSyncAt = Date()
                lastSyncMessage = "已初始化坚果云账本快照"
            }
            if syncState != .conflict {
                syncState = .success
            }
        } catch {
            errorMessage = "坚果云同步失败: \(error.localizedDescription)"
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
            markSnapshotSynced(snapshot)
            lastSyncAt = Date()
            lastSyncMessage = "已手动推送到坚果云"
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
                lastSyncMessage = "坚果云还没有可拉取的数据"
                syncState = .idle
                return
            }
            apply(remote)
            refreshDerivedData()
            try await localStore.save(remote)
            localUpdatedAt = remote.updatedAt
            markSnapshotSynced(remote)
            lastSyncAt = Date()
            lastSyncMessage = "已从坚果云拉取最新数据"
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
            lastSyncMessage = "已开启坚果云同步，准备检查 WebDAV 状态"
            if cloudSyncSchedule != .onChange {
                await smartSync(showSuccessMessage: false)
            }
            configureScheduledSyncIfNeeded()
        } else {
            periodicSyncTask?.cancel()
            periodicSyncTask = nil
            syncState = .idle
            cloudAccountStatus = .unknown
            cloudUserRecordName = nil
            lastSyncMessage = "当前仅本地模式"
        }
    }

    func updateCloudSyncSchedule(_ schedule: CloudSyncSchedule) async {
        cloudSyncSchedule = schedule
        configureScheduledSyncIfNeeded()
        guard cloudSyncEnabled else { return }
        if schedule == .periodic || schedule == .onAppOpen {
            await smartSync(showSuccessMessage: false)
        } else {
            lastSyncMessage = "已设置为每次保存后同步"
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

    private func installSupplementalDefaultSubcategoriesIfNeeded() -> Bool {
        let versionKey = "smartledgerlocal.defaultCategoryCatalogVersion"
        guard UserDefaults.standard.integer(forKey: versionKey) < 6 else { return false }
        defer { UserDefaults.standard.set(6, forKey: versionKey) }

        var inserted = false
        for definition in DemoData.supplementalDefaultRoots {
            guard !categories.contains(where: { $0.parentId == nil && $0.name == definition.name && $0.flowType == definition.flowType }) else { continue }
            let rootID = nextCategoryId
            nextCategoryId += 1
            let children = definition.children.map { child -> LedgerCategory in
                let id = nextCategoryId
                nextCategoryId += 1
                return LedgerCategory(id: id, name: child.0, flowType: definition.flowType, icon: child.1, color: child.2, parentId: rootID, level: 1, children: [])
            }
            categories.append(LedgerCategory(id: rootID, name: definition.name, flowType: definition.flowType, icon: definition.icon, color: definition.color, parentId: nil, level: 0, children: children))
            inserted = true
        }
        for (rootName, childNames) in DemoData.supplementalDefaultSubcategories {
            guard let root = flattenedCategories.first(where: { $0.parentId == nil && $0.name == rootName }) else { continue }
            let existingNames = Set(flattenedCategories.compactMap { category -> String? in
                guard category.parentId == root.id else { return nil }
                return category.pathComponents.last
            })
            for childName in childNames where !existingNames.contains(childName) {
                let child = LedgerCategory(
                    id: nextCategoryId,
                    name: childName,
                    flowType: root.flowType,
                    icon: DemoData.categoryIcon(for: childName, fallback: root.icon ?? "tag.fill"),
                    color: root.color,
                    parentId: root.id,
                    level: root.level + 1,
                    children: []
                )
                nextCategoryId += 1
                categories = CategoryTreeBuilder.insert(child, into: categories)
                inserted = true
            }
        }
        if nestDailyMealsUnderDailyDiningIfNeeded() { inserted = true }
        return inserted
    }

    private func nestDailyMealsUnderDailyDiningIfNeeded() -> Bool {
        guard let rootIndex = categories.firstIndex(where: { $0.parentId == nil && $0.name == "餐饮" }) else { return false }
        let mealNames: Set<String> = ["早餐", "午餐", "晚餐"]
        var root = categories[rootIndex]
        var children = root.children
        let movable = children.filter { mealNames.contains($0.name) }
        guard !movable.isEmpty else { return false }
        let dailyIndex: Int
        if let existing = children.firstIndex(where: { $0.name == "日常吃饭" }) {
            dailyIndex = existing
        } else {
            let daily = LedgerCategory(id: nextCategoryId, name: "日常吃饭", flowType: root.flowType, icon: "takeoutbag.and.cup.and.straw", color: root.color, parentId: root.id, level: root.level + 1, children: [])
            nextCategoryId += 1
            children.append(daily)
            dailyIndex = children.count - 1
        }
        let daily = children[dailyIndex]
        let nested = movable.map { meal in
            LedgerCategory(id: meal.id, name: meal.name, flowType: meal.flowType, icon: meal.icon, color: meal.color, parentId: daily.id, level: daily.level + 1, children: meal.children)
        }
        let updatedDaily = LedgerCategory(id: daily.id, name: daily.name, flowType: daily.flowType, icon: daily.icon, color: daily.color, parentId: daily.parentId, level: daily.level, children: daily.children + nested)
        children.removeAll { mealNames.contains($0.name) }
        guard let replacementIndex = children.firstIndex(where: { $0.id == daily.id }) else { return false }
        children[replacementIndex] = updatedDaily
        root = LedgerCategory(id: root.id, name: root.name, flowType: root.flowType, icon: root.icon, color: root.color, parentId: root.parentId, level: root.level, children: children)
        categories[rootIndex] = root
        return true
    }

    private func refreshDerivedData() {
        books = recomputeBookSummaries(from: books, transactions: transactions)
        budgets = LocalAnalytics.computeBudgetProgress(transactions: transactions, categories: flattenedCategories, budgets: budgets)
    }

    private func recomputeBookSummaries(from books: [LedgerBook], transactions: [LedgerTransaction]) -> [LedgerBook] {
        books.map { book in
            let scoped = transactions.filter { $0.bookIds.contains(book.id) || $0.bookId == book.id }
            let income = scoped.filter { $0.kind == .income }.reduce(0.0) { $0 + $1.selfShareAmount }
            let expense = scoped.filter { $0.kind == .expense }.reduce(0.0) { $0 + $1.selfShareAmount }
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
        let autoCollected = recommendedBooks(for: draft.happenedAt).filter { shouldAutoCollect(into: $0, date: draft.happenedAt, categoryId: draft.categoryId, kind: draft.kind) }
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
  [String], categoryId: Int? = nil, categoryName: String? = nil, replacingCategory: Bool = false, source: String? = nil, offsetSourceTransactionId: Int? = nil, defaultSplitParticipantId: String? = nil, defaultSplitParticipantName: String? = nil) -> LedgerTransaction {
        let splitIDs = defaultSplitParticipantId.map { [$0] } ?? tx.splitParticipantIds
        let splitNames = defaultSplitParticipantName.map { [$0] } ?? tx.splitParticipantNames
        let paidByID = defaultSplitParticipantId ?? tx.paidByParticipantId
        let paidByName = defaultSplitParticipantName ?? tx.paidByParticipantName
        return LedgerTransaction(
            id: tx.id,
            title: tx.title,
            amount: tx.amount,
            kind: tx.kind,
            happenedAt: tx.happenedAt,
            note: tx.note,
            merchant: tx.merchant,
            paymentMethod: tx.paymentMethod,
            source: source ?? tx.source,
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
            paidByParticipantId: paidByID,
            paidByParticipantName: paidByName,
            splitParticipantIds: splitIDs,
            splitParticipantNames: splitNames,
            installmentOriginalTotal: tx.installmentOriginalTotal,
            originalAmount: tx.originalAmount,
            discountAmount: tx.discountAmount,
            premiumAmount: tx.premiumAmount,
            installmentStartMonth: tx.installmentStartMonth,
            offsetSourceTransactionId: offsetSourceTransactionId ?? tx.offsetSourceTransactionId
        )
    }

    private func offsetSourceMarker(_ id: Int?, original: String) -> String {
        guard let id else { return original }
        return "offset:\(id)|\(original)"
    }

    /// Reimbursement/refund records keep their own income category, but all
    /// descriptive fields follow the source expense so edits stay consistent.
    private func synchronizeLinkedOffsets(sourceID: Int, with source: LedgerTransaction) {
        transactions = transactions.map { offset in
            guard offset.kind == .income, offset.linkedOffsetSourceID == sourceID else { return offset }
            return LedgerTransaction(
                id: offset.id,
                title: source.title,
                amount: offset.amount,
                kind: .income,
                happenedAt: offset.happenedAt,
                note: source.note?.isEmpty == false ? source.note : "抵扣流水",
                merchant: source.merchant,
                paymentMethod: source.paymentMethod,
                source: offsetSourceMarker(source.id, original: source.source),
                currency: offset.currency,
                categoryId: offset.categoryId,
                categoryName: offset.categoryName,
                bookId: source.bookId,
                bookName: source.bookName,
                bookIds: source.bookIds,
                bookNames: source.bookNames,
                installmentGroupId: nil,
                installmentIndex: nil,
                installmentMonths: nil,
                paidByParticipantId: source.paidByParticipantId,
                paidByParticipantName: source.paidByParticipantName,
                splitParticipantIds: source.splitParticipantIds,
                splitParticipantNames: source.splitParticipantNames,
                installmentOriginalTotal: nil,
                originalAmount: nil,
                discountAmount: nil,
                premiumAmount: nil,
                installmentStartMonth: nil,
                offsetSourceTransactionId: source.id
            )
        }
    }

    private func installmentBaseTitle(_ title: String) -> String {
        guard let range = title.range(of: " (分期 ") else { return title }
        return String(title[..<range.lowerBound])
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

    /// Returns a stable representation of every synchronised domain object,
    /// deliberately excluding only the timestamp used for version ordering.
    private func snapshotContentData(_ snapshot: PersistedLedgerSnapshot) -> Data? {
        var content = snapshot
        content.updatedAt = Date(timeIntervalSince1970: 0)
        return try? JSONEncoder.iso8601.encode(content)
    }

    private func snapshotContentFingerprint(_ snapshot: PersistedLedgerSnapshot) -> String {
        let data = snapshotContentData(snapshot) ?? Data()
        // Stable FNV-1a fingerprint; it is a sync base marker, not a security hash.
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func markSnapshotSynced(_ snapshot: PersistedLedgerSnapshot) {
        let fingerprint = snapshotContentFingerprint(snapshot)
        lastSyncedFingerprint = fingerprint
        UserDefaults.standard.set(fingerprint, forKey: "smartledgerlocal.lastSyncedFingerprint")
        lastSyncedSnapshotUpdatedAt = snapshot.updatedAt
        UserDefaults.standard.set(snapshot.updatedAt.timeIntervalSince1970, forKey: "smartledgerlocal.lastSyncedSnapshotUpdatedAt")
    }

    private func hasBothSidesChangedSinceLastAgreement(local: PersistedLedgerSnapshot, remote: PersistedLedgerSnapshot) -> Bool {
        guard let agreedAt = lastSyncedSnapshotUpdatedAt else { return false }
        return local.updatedAt > agreedAt.addingTimeInterval(0.5) && remote.updatedAt > agreedAt.addingTimeInterval(0.5)
    }

    private func configureScheduledSyncIfNeeded() {
        periodicSyncTask?.cancel()
        periodicSyncTask = nil
        guard cloudSyncEnabled, cloudSyncSchedule == .periodic else { return }
        periodicSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.smartSync(showSuccessMessage: false)
            }
        }
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

    /// Prevents double taps and concurrent tasks from creating duplicate data.
    /// A completed key is held briefly, while failed validation paths are free
    /// to retry immediately because they never call `completeSave`.
    private func beginSave(key: String) -> Bool {
        let now = Date()
        recentlyCompletedSaveKeys = recentlyCompletedSaveKeys.filter { now.timeIntervalSince($0.value) < 2.5 }
        guard !inFlightSaveKeys.contains(key), recentlyCompletedSaveKeys[key] == nil else { return false }
        inFlightSaveKeys.insert(key)
        return true
    }

    private func endSave(key: String) { inFlightSaveKeys.remove(key) }
    private func completeSave(key: String) { recentlyCompletedSaveKeys[key] = Date() }

    private func persistAndMaybeSync(reason: String) async {
        do {
            try await persistLocalSnapshot(markUpdatedAt: true)
            lastSyncMessage = reason
        } catch {
            errorMessage = "保存本地数据失败: \(error.localizedDescription)"
        }
        await refreshDashboard(range: activeRangePreset, granularity: activeGranularity)
        if cloudSyncEnabled && cloudSyncSchedule == .onChange {
            await smartSync(showSuccessMessage: false)
        } else if cloudSyncEnabled {
            lastSyncMessage = "\(reason)，将按\(cloudSyncSchedule.title)同步"
        }
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
    static func replacing(categoryId: Int, in tree: [LedgerCategory], transform: (LedgerCategory) -> LedgerCategory) -> [LedgerCategory] {
        tree.map { item in
            if item.id == categoryId { return transform(item) }
            guard !item.children.isEmpty else { return item }
            return LedgerCategory(id: item.id, name: item.name, flowType: item.flowType, icon: item.icon, color: item.color, parentId: item.parentId, level: item.level, children: replacing(categoryId: categoryId, in: item.children, transform: transform))
        }
    }

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
