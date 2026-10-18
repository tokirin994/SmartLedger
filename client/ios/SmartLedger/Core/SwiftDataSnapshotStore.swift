import Foundation
import SwiftData

@Model
final class LedgerCategoryRecord {
  @Attribute(.unique) var id: Int
  var name: String
  var flowTypeRaw: String
  var icon: String?
  var color: String?
  var parentId: Int?
  var level: Int
  var sortOrder: Int?

  init(id: Int, name: String, flowTypeRaw: String, icon: String?, color: String?, parentId: Int?, level: Int, sortOrder: Int? = nil) {
    self.id = id
    self.name = name
    self.flowTypeRaw = flowTypeRaw
    self.icon = icon
    self.color = color
    self.parentId = parentId
    self.level = level
    self.sortOrder = sortOrder
  }
}

@Model
final class LedgerBookRecord {
  @Attribute(.unique) var id: Int
  var name: String
  var icon: String?
  var color: String?
  var note: String?
  var startDate: Date?
  var endDate: Date?
  var autoCollectEnabled: Bool
  var budgetLimitAmount: Double?
  var budgetStartDate: Date?
  var budgetEndDate: Date?
  var expenseAmount: Double
  var incomeAmount: Double
  var balance: Double
  var transactionCount: Int
  var participantNamesData: Data
  var isPinned: Bool
  var autoCollectCategoryIdsData: Data

  init(id: Int, name: String, icon: String?, color: String?, note: String?, startDate: Date?, endDate: Date?, autoCollectEnabled: Bool, budgetLimitAmount: Double?, budgetStartDate: Date?, budgetEndDate: Date?, expenseAmount: Double, incomeAmount: Double, balance: Double, transactionCount: Int, participantNamesData: Data, isPinned: Bool, autoCollectCategoryIdsData: Data) {
    self.id = id
    self.name = name
    self.icon = icon
    self.color = color
    self.note = note
    self.startDate = startDate
    self.endDate = endDate
    self.autoCollectEnabled = autoCollectEnabled
    self.budgetLimitAmount = budgetLimitAmount
    self.budgetStartDate = budgetStartDate
    self.budgetEndDate = budgetEndDate
    self.expenseAmount = expenseAmount
    self.incomeAmount = incomeAmount
    self.balance = balance
    self.transactionCount = transactionCount
    self.participantNamesData = participantNamesData
    self.isPinned = isPinned
    self.autoCollectCategoryIdsData = autoCollectCategoryIdsData
  }
}

@Model
final class LedgerTransactionRecord {
  @Attribute(.unique) var id: Int
  var title: String
  var amount: Double
  var kindRaw: String
  var date: Date
  var note: String?
  var merchant: String?
  var paymentMethod: String?
  var source: String
  var currency: String
  var categoryId: Int?
  var categoryName: String?
  var bookId: Int
  var bookName: String?
  var bookIdsData: Data
  var bookNamesData: Data
  var installmentGroupId: String?
  var installmentIndex: Int?
  var installmentMonths: Int?
  var installmentOriginalTotal: Double?
  var originalAmount: Double?
  var discountAmount: Double?
  var preAmount: Double?
  var paidByParticipantId: String?
  var paidByParticipantName: String?
  var splitParticipantIdsData: Data?
  var splitParticipantNamesData: Data?

  init(id: Int, title: String, amount: Double, kindRaw: String, date: Date, note: String?, merchant: String?, paymentMethod: String?, source: String, currency: String, categoryId: Int?, categoryName: String?, bookId: Int, bookName: String?, bookIdsData: Data, bookNamesData: Data, installmentGroupId: String?, installmentIndex: Int?, installmentMonths: Int?, installmentOriginalTotal: Double?, originalAmount: Double?, discountAmount: Double?, preAmount: Double?, paidByParticipantId: String?, paidByParticipantName: String?, splitParticipantIdsData: Data?, splitParticipantNamesData: Data?) {
    self.id = id
    self.title = title
    self.amount = amount
    self.kindRaw = kindRaw
    self.date = date
    self.note = note
    self.merchant = merchant
    self.paymentMethod = paymentMethod
    self.source = source
    self.currency = currency
    self.categoryId = categoryId
    self.categoryName = categoryName
    self.bookId = bookId
    self.bookName = bookName
    self.bookIdsData = bookIdsData
    self.bookNamesData = bookNamesData
    self.installmentGroupId = installmentGroupId
    self.installmentIndex = installmentIndex
    self.installmentMonths = installmentMonths
    self.installmentOriginalTotal = installmentOriginalTotal
    self.originalAmount = originalAmount
    self.discountAmount = discountAmount
    self.preAmount = preAmount
    self.paidByParticipantId = paidByParticipantId
    self.paidByParticipantName = paidByParticipantName
    self.splitParticipantIdsData = splitParticipantIdsData
    self.splitParticipantNamesData = splitParticipantNamesData
  }
}

@Model
final class LedgerBudgetRecord {
  @Attribute(.unique) var id: Int
  var name: String
  var limitAmount: Double
  var periodType: String
  var year: Int
  var month: Int?
  var startDate: Date?
  var endDate: Date?
  var categoryId: Int?
  var categoryName: String?
  var parentBudgetId: Int?
  var categoryIdsData: Data?
  var keyword: String?
  var spentAmount: Double
  var usageRatio: Double

  init(id: Int, name: String, limitAmount: Double, periodType: String, year: Int, month: Int?, startDate: Date?, endDate: Date?, categoryId: Int?, categoryName: String?, spentAmount: Double, usageRatio: Double, parentBudgetId: Int? = nil, categoryIds: [Int]? = nil, keyword: String? = nil) {
    self.id = id
    self.name = name
    self.limitAmount = limitAmount
    self.periodType = periodType
    self.year = year
    self.month = month
    self.startDate = startDate
    self.endDate = endDate
    self.categoryId = categoryId
    self.categoryName = categoryName
    self.parentBudgetId = parentBudgetId
    self.categoryIdsData = categoryIds.flatMap { try? JSONEncoder().encode($0) }
    self.keyword = keyword
    self.spentAmount = spentAmount
    self.usageRatio = usageRatio
  }
}

@Model
final class LedgerMetaRecord {
  @Attribute(.unique) var key: String
  var nextTransactionId: Int
  var nextBookId: Int
  var nextCategoryId: Int
  var nextBudgetId: Int
  var updatedAt: Date

  init(key: String = "primary", nextTransactionId: Int, nextBookId: Int, nextCategoryId: Int, nextBudgetId: Int, updatedAt: Date) {
    self.key = key
    self.nextTransactionId = nextTransactionId
    self.nextBookId = nextBookId
    self.nextCategoryId = nextCategoryId
    self.nextBudgetId = nextBudgetId
    self.updatedAt = updatedAt
  }
}

@Model
final class TransactionLedgerLinkRecord {
  @Attribute(.unique) var id: String
  var transactionId: Int
  var ledgerId: Int
  var sourceRaw: String
  var includeInStatistics: Bool
  var splitEnabled: Bool
  var payerParticipantId: String?
  var splitParticipantIdsData: Data
  var splitParticipantNamesData: Data
  var splitModeRaw: String
  var splitRatio: Double?
  var splitAmount: Double?
  var participantSnapshotData: Data
  var configVersion: Int
  var needsReview: Bool
  var isSplitCustomized: Bool

  init(id: String, transactionId: Int, ledgerId: Int, sourceRaw: String, includeInStatistics: Bool, splitEnabled: Bool, payerParticipantId: String?, splitParticipantIdsData: Data, splitParticipantNamesData: Data, splitModeRaw: String, splitRatio: Double?, splitAmount: Double?, participantSnapshotData: Data, configVersion: Int, needsReview: Bool, isSplitCustomized: Bool) {
    self.id = id
    self.transactionId = transactionId
    self.ledgerId = ledgerId
    self.sourceRaw = sourceRaw
    self.includeInStatistics = includeInStatistics
    self.splitEnabled = splitEnabled
    self.payerParticipantId = payerParticipantId
    self.splitParticipantIdsData = splitParticipantIdsData
    self.splitParticipantNamesData = splitParticipantNamesData
    self.splitModeRaw = splitModeRaw
    self.splitRatio = splitRatio
    self.splitAmount = splitAmount
    self.participantSnapshotData = participantSnapshotData
    self.configVersion = configVersion
    self.needsReview = needsReview
    self.isSplitCustomized = isSplitCustomized
  }
}

actor SwiftDataSnapshotStore {
  private let container: ModelContainer
  private static let storeName = "SmartLedgerLocal"

  init(inMemory: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil) {
    container = Self.makeContainer(inMemory: inMemory)
  }

  private static func makeContainer(inMemory: Bool) -> ModelContainer {
    let configuration = ModelConfiguration(
      storeName,
      isStoredInMemoryOnly: inMemory,
      cloudKitDatabase: .none
    )
    do {
      return try buildContainer(configuration: configuration)
    } catch {
      guard !inMemory else {
        fatalError("Failed to create in-memory SwiftData container: \(error)")
      }

      let removed = resetPersistentStoreFiles(named: storeName)
      do {
        return try buildContainer(configuration: configuration)
      } catch {
        fatalError("Failed to create SwiftData container after resetting local store. RemovedFiles=\(removed). Error=\(error)")
      }
    }
  }

  private static func buildContainer(configuration: ModelConfiguration) throws -> ModelContainer {
    try ModelContainer(
      for: LedgerCategoryRecord.self,
      LedgerBookRecord.self,
      LedgerTransactionRecord.self,
      LedgerBudgetRecord.self,
      LedgerMetaRecord.self,
      TransactionLedgerLinkRecord.self,
      configurations: configuration
    )
  }

  @discardableResult
  private static func resetPersistentStoreFiles(named storeName: String) -> [String] {
    guard let applicationSupportURL = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else {
      return []
    }

    let baseStoreURL = applicationSupportURL.appendingPathComponent("\(storeName).store")
    let candidateURLs: [URL] = [
      baseStoreURL,
      URL(fileURLWithPath: baseStoreURL.path + "-wal"),
      URL(fileURLWithPath: baseStoreURL.path + "-shm")
    ]

    var removed: [String] = []
    for url in candidateURLs where FileManager.default.fileExists(atPath: url.path) {
      do {
        try FileManager.default.removeItem(at: url)
        removed.append(url.lastPathComponent)
      } catch {
        #if DEBUG
        print("[SwiftDataSnapshotStore] Failed to remove incompatible store file: \(url.path), error: \(error)")
        #endif
      }
    }

    return removed
  }

  func load() throws -> PersistedLedgerSnapshot? {
    let context = ModelContext(container)
     let categories = try context.fetch(FetchDescriptor<LedgerCategoryRecord>())
    let books = try context.fetch(FetchDescriptor<LedgerBookRecord>()).sorted { $0.id < $1.id }
    let transactions = try context.fetch(FetchDescriptor<LedgerTransactionRecord>()).sorted { $0.date < $1.date }
    let budgets = try context.fetch(FetchDescriptor<LedgerBudgetRecord>()).sorted { $0.id < $1.id }
    let links = try context.fetch(FetchDescriptor<TransactionLedgerLinkRecord>()).sorted { $0.id < $1.id }
    let meta = try context.fetch(FetchDescriptor<LedgerMetaRecord>()).first

    guard meta != nil || !categories.isEmpty || !books.isEmpty || !transactions.isEmpty || !budgets.isEmpty || !links.isEmpty else {
      return nil
    }

    return PersistedLedgerSnapshot(
      schemaVersion: links.isEmpty ? 1 : 2,
      categories: buildCategoryTree(from: categories),
      books: books.map { $0.toModel() },
      transactions: transactions.map { $0.toModel() },
      budgets: budgets.map { $0.toModel() },
      transactionLedgerLinks: links.map { $0.toModel() },
      nextTransactionId: meta?.nextTransactionId ?? 1000,
      nextBookId: meta?.nextBookId ?? 100,
      nextCategoryId: meta?.nextCategoryId ?? 1000,
      nextBudgetId: meta?.nextBudgetId ?? 100,
      updatedAt: meta?.updatedAt ?? Date()
    )
  }

  func save(_ snapshot: PersistedLedgerSnapshot) throws {
    let context = ModelContext(container)

    // Update records in place instead of deleting and recreating the whole
    // store on every edit. This keeps stable SwiftData identities, greatly
    // reduces write amplification, and avoids UI stalls as the ledger grows.
    let categoryRecords = try context.fetch(FetchDescriptor<LedgerCategoryRecord>())
    let categoryByID = Dictionary(uniqueKeysWithValues: categoryRecords.map { ($0.id, $0) })
    let categories = snapshot.categories.flatMap { flattenCategories($0) }
    let categoryIDs = Set(categories.map(\.id))
    for record in categoryRecords where !categoryIDs.contains(record.id) { context.delete(record) }
    for category in categories {
      if let record = categoryByID[category.id] {
        record.update(from: category)
      } else {
        context.insert(LedgerCategoryRecord(from: category))
      }
    }

    let bookRecords = try context.fetch(FetchDescriptor<LedgerBookRecord>())
    let bookByID = Dictionary(uniqueKeysWithValues: bookRecords.map { ($0.id, $0) })
    let bookIDs = Set(snapshot.books.map(\.id))
    for record in bookRecords where !bookIDs.contains(record.id) { context.delete(record) }
    for book in snapshot.books {
      if let record = bookByID[book.id] {
        record.update(from: book)
      } else {
        context.insert(LedgerBookRecord(from: book))
      }
    }

    let transactionRecords = try context.fetch(FetchDescriptor<LedgerTransactionRecord>())
    let transactionByID = Dictionary(uniqueKeysWithValues: transactionRecords.map { ($0.id, $0) })
    let transactionIDs = Set(snapshot.transactions.map(\.id))
    for record in transactionRecords where !transactionIDs.contains(record.id) { context.delete(record) }
    for transaction in snapshot.transactions {
      if let record = transactionByID[transaction.id] {
        record.update(from: transaction)
      } else {
        context.insert(LedgerTransactionRecord(from: transaction))
      }
    }

    let budgetRecords = try context.fetch(FetchDescriptor<LedgerBudgetRecord>())
    let budgetByID = Dictionary(uniqueKeysWithValues: budgetRecords.map { ($0.id, $0) })
    let budgetIDs = Set(snapshot.budgets.map(\.id))
    for record in budgetRecords where !budgetIDs.contains(record.id) { context.delete(record) }
    for budget in snapshot.budgets {
      if let record = budgetByID[budget.id] {
        record.update(from: budget)
      } else {
        context.insert(LedgerBudgetRecord(from: budget))
      }
    }

    let linkRecords = try context.fetch(FetchDescriptor<TransactionLedgerLinkRecord>())
    let linkByID = Dictionary(uniqueKeysWithValues: linkRecords.map { ($0.id, $0) })
    let linkIDs = Set(snapshot.transactionLedgerLinks.map(\.id))
    for record in linkRecords where !linkIDs.contains(record.id) { context.delete(record) }
    for link in snapshot.transactionLedgerLinks {
      if let record = linkByID[link.id] {
        record.update(from: link)
      } else {
        context.insert(TransactionLedgerLinkRecord(from: link))
      }
    }

    if let meta = try context.fetch(FetchDescriptor<LedgerMetaRecord>()).first {
      meta.nextTransactionId = snapshot.nextTransactionId
      meta.nextBookId = snapshot.nextBookId
      meta.nextCategoryId = snapshot.nextCategoryId
      meta.nextBudgetId = snapshot.nextBudgetId
      meta.updatedAt = snapshot.updatedAt
    } else {
      context.insert(
        LedgerMetaRecord(
          nextTransactionId: snapshot.nextTransactionId,
          nextBookId: snapshot.nextBookId,
          nextCategoryId: snapshot.nextCategoryId,
          nextBudgetId: snapshot.nextBudgetId,
          updatedAt: snapshot.updatedAt
        )
      )
    }

    try context.save()
  }

  private func flattenCategories(_ category: LedgerCategory) -> [LedgerCategory] {
    [category] + category.children.flatMap { flattenCategories($0) }
  }

 private func buildCategoryTree(from records: [LedgerCategoryRecord]) -> [LedgerCategory] {
   let grouped = Dictionary(grouping: records, by: \.parentId)
   func makeNode(_ record: LedgerCategoryRecord) -> LedgerCategory {
     LedgerCategory(
       id: record.id,
       name: record.name,
       flowType: FlowType(rawValue: record.flowTypeRaw) ?? .expense,
       icon: record.icon,
       color: record.color,
       parentId: record.parentId,
       level: record.level,
       children: (grouped[record.id] ?? []).sorted { lhs, rhs in
         (lhs.sortOrder ?? Int.max, lhs.id) < (rhs.sortOrder ?? Int.max, rhs.id)
       }.map(makeNode)
      )
    }
    return (grouped[nil] ?? []).sorted { lhs, rhs in
      (lhs.sortOrder ?? Int.max, lhs.id) < (rhs.sortOrder ?? Int.max, rhs.id)
    }.map(makeNode)
 }
}

private extension LedgerCategoryRecord {
 convenience init(from category: LedgerCategory) {
   self.init(
     id: category.id,
     name: category.name,
     flowTypeRaw: category.flowType.rawValue,
     icon: category.icon,
     color: category.color,
       parentId: category.parentId,
       level: category.level,
       sortOrder: category.sortOrder
   )
 }

 func update(from category: LedgerCategory) {
   name = category.name
   flowTypeRaw = category.flowType.rawValue
   icon = category.icon
   color = category.color
   parentId = category.parentId
   level = category.level
   sortOrder = category.sortOrder
 }
}

private extension LedgerBookRecord {
 convenience init(from book: LedgerBook) {
   self.init(
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
     expenseAmount: book.expenseAmount,
     incomeAmount: book.incomeAmount,
     balance: book.balance,
     transactionCount: book.transactionCount,
     participantNamesData: (try? JSONEncoder().encode(book.participantNames)) ?? Data("[]".utf8),
     isPinned: book.isPinned,
     autoCollectCategoryIdsData: (try? JSONEncoder().encode(book.autoCollectCategoryIds)) ?? Data("[]".utf8)
   )
 }

 func update(from book: LedgerBook) {
   name = book.name
   icon = book.icon
   color = book.color
   note = book.note
   startDate = book.startDate
   endDate = book.endDate
   autoCollectEnabled = book.autoCollectEnabled
   budgetLimitAmount = book.budgetLimitAmount
   budgetStartDate = book.budgetStartDate
   budgetEndDate = book.budgetEndDate
   expenseAmount = book.expenseAmount
   incomeAmount = book.incomeAmount
   balance = book.balance
   transactionCount = book.transactionCount
   participantNamesData = (try? JSONEncoder().encode(book.participantNames)) ?? Data("[]".utf8)
   isPinned = book.isPinned
   autoCollectCategoryIdsData = (try? JSONEncoder().encode(book.autoCollectCategoryIds)) ?? Data("[]".utf8)
 }

 func toModel() -> LedgerBook {
   LedgerBook(
     id: id,
     name: name,
     icon: icon,
     color: color,
     note: note,
     startDate: startDate,
     endDate: endDate,
     budgetLimitAmount: budgetLimitAmount,
     budgetStartDate: budgetStartDate,
     budgetEndDate: budgetEndDate,
     autoCollectEnabled: autoCollectEnabled,
     expenseAmount: expenseAmount,
     incomeAmount: incomeAmount,
     balance: balance,
     transactionCount: transactionCount,
     participantNames: (try? JSONDecoder().decode([String].self, from: participantNamesData)) ?? [],
     isPinned: isPinned,
     autoCollectCategoryIds: (try? JSONDecoder().decode([Int].self, from: autoCollectCategoryIdsData)) ?? []
   )
 }
}

private extension LedgerTransactionRecord {
 convenience init(from transaction: LedgerTransaction) {
   self.init(
     id: transaction.id,
     title: transaction.title,
     amount: transaction.amount,
     kindRaw: transaction.kind.rawValue,
     date: transaction.happenedAt,
     note: transaction.note,
     merchant: transaction.merchant,
     paymentMethod: transaction.paymentMethod,
     source: transaction.source,
     currency: transaction.currency,
     categoryId: transaction.categoryId,
     categoryName: transaction.categoryName,
     bookId: transaction.bookId ?? 0,
     bookName: transaction.bookName,
     bookIdsData: (try? JSONEncoder().encode(transaction.bookIds)) ?? Data("[]".utf8),
     bookNamesData: (try? JSONEncoder().encode(transaction.bookNames)) ?? Data("[]".utf8),
     installmentGroupId: transaction.installmentGroupId,
     installmentIndex: transaction.installmentIndex,
     installmentMonths: transaction.installmentMonths,
     installmentOriginalTotal: transaction.installmentOriginalTotal,
     originalAmount: transaction.originalAmount,
     discountAmount: transaction.discountAmount,
     preAmount: transaction.premiumAmount,
     paidByParticipantId: transaction.paidByParticipantId,
     paidByParticipantName: transaction.paidByParticipantName,
     splitParticipantIdsData: (try? JSONEncoder().encode(transaction.splitParticipantIds)) ?? Data("[]".utf8),
     splitParticipantNamesData: (try? JSONEncoder().encode(transaction.splitParticipantNames)) ?? Data("[]".utf8)
   )
 }

 func update(from transaction: LedgerTransaction) {
   title = transaction.title
   amount = transaction.amount
   kindRaw = transaction.kind.rawValue
   date = transaction.happenedAt
   note = transaction.note
   merchant = transaction.merchant
   paymentMethod = transaction.paymentMethod
   source = transaction.source
   currency = transaction.currency
   categoryId = transaction.categoryId
   categoryName = transaction.categoryName
   bookId = transaction.bookId ?? 0
   bookName = transaction.bookName
   bookIdsData = (try? JSONEncoder().encode(transaction.bookIds)) ?? Data("[]".utf8)
   bookNamesData = (try? JSONEncoder().encode(transaction.bookNames)) ?? Data("[]".utf8)
   installmentGroupId = transaction.installmentGroupId
   installmentIndex = transaction.installmentIndex
   installmentMonths = transaction.installmentMonths
   installmentOriginalTotal = transaction.installmentOriginalTotal
   originalAmount = transaction.originalAmount
   discountAmount = transaction.discountAmount
   preAmount = transaction.premiumAmount
   paidByParticipantId = transaction.paidByParticipantId
   paidByParticipantName = transaction.paidByParticipantName
   splitParticipantIdsData = (try? JSONEncoder().encode(transaction.splitParticipantIds)) ?? Data("[]".utf8)
   splitParticipantNamesData = (try? JSONEncoder().encode(transaction.splitParticipantNames)) ?? Data("[]".utf8)
 }

 func toModel() -> LedgerTransaction {
   LedgerTransaction(
     id: id,
     title: title,
     amount: amount,
     kind: FlowType(rawValue: kindRaw) ?? .expense,
     happenedAt: date,
     note: note,
     merchant: merchant,
     paymentMethod: paymentMethod,
     source: source,
     currency: currency,
     categoryId: categoryId,
     categoryName: categoryName,
     bookId: bookId,
     bookName: bookName,
     bookIds: (try? JSONDecoder().decode([Int].self, from: bookIdsData)) ?? [],
     bookNames: (try? JSONDecoder().decode([String].self, from: bookNamesData)) ?? [],
     installmentGroupId: installmentGroupId,
     installmentIndex: installmentIndex,
     installmentMonths: installmentMonths,
     paidByParticipantId: paidByParticipantId,
     paidByParticipantName: paidByParticipantName,
     splitParticipantIds: (try? JSONDecoder().decode([String].self, from: splitParticipantIdsData ?? Data("[]".utf8))) ?? [],
     splitParticipantNames: (try? JSONDecoder().decode([String].self, from: splitParticipantNamesData ?? Data("[]".utf8))) ?? [],
     installmentOriginalTotal: installmentOriginalTotal,
     originalAmount: originalAmount,
     discountAmount: discountAmount,
     premiumAmount: preAmount
   )
 }
}

private extension LedgerBudgetRecord {
 convenience init(from budget: BudgetItem) {
   self.init(
     id: budget.id,
     name: budget.name,
     limitAmount: budget.limitAmount,
     periodType: budget.periodType,
     year: budget.year,
     month: budget.month,
     startDate: budget.startDate,
     endDate: budget.endDate,
     categoryId: budget.categoryId,
     categoryName: budget.categoryName,
     spentAmount: budget.spentAmount,
     usageRatio: budget.usageRatio,
     parentBudgetId: budget.parentBudgetId,
     categoryIds: budget.categoryIds,
     keyword: budget.keyword
   )
 }

 func update(from budget: BudgetItem) {
   name = budget.name
   limitAmount = budget.limitAmount
   periodType = budget.periodType
   year = budget.year
   month = budget.month
   startDate = budget.startDate
   endDate = budget.endDate
   categoryId = budget.categoryId
   categoryName = budget.categoryName
   parentBudgetId = budget.parentBudgetId
   categoryIdsData = budget.categoryIds.flatMap { try? JSONEncoder().encode($0) }
   keyword = budget.keyword
   spentAmount = budget.spentAmount
   usageRatio = budget.usageRatio
 }

 func toModel() -> BudgetItem {
   BudgetItem(
     id: id,
     name: name,
     limitAmount: limitAmount,
     periodType: periodType,
     year: year,
     month: month,
     startDate: startDate,
     endDate: endDate,
     categoryId: categoryId,
     categoryName: categoryName,
     spentAmount: spentAmount,
     usageRatio: usageRatio,
     parentBudgetId: parentBudgetId,
     categoryIds: categoryIdsData.flatMap { try? JSONDecoder().decode([Int].self, from: $0) },
     keyword: keyword
   )
 }
}

private extension TransactionLedgerLinkRecord {
 convenience init(from link: TransactionLedgerLink) {
   self.init(
     id: link.id,
     transactionId: link.transactionId,
     ledgerId: link.ledgerId,
     sourceRaw: link.source.rawValue,
     includeInStatistics: link.includeInStatistics,
     splitEnabled: link.splitEnabled,
     payerParticipantId: link.payerParticipantId,
     splitParticipantIdsData: (try? JSONEncoder().encode(link.splitParticipantIds)) ?? Data("[]".utf8),
     splitParticipantNamesData: (try? JSONEncoder().encode(link.splitParticipantNames)) ?? Data("[]".utf8),
     splitModeRaw: link.splitMode.rawValue,
     splitRatio: link.splitRatio,
     splitAmount: link.splitAmount,
     participantSnapshotData: (try? JSONEncoder().encode(link.participantSnapshot)) ?? Data("[]".utf8),
     configVersion: link.configVersion,
     needsReview: link.needsReview,
     isSplitCustomized: link.isSplitCustomized
   )
 }

 func update(from link: TransactionLedgerLink) {
   transactionId = link.transactionId
   ledgerId = link.ledgerId
   sourceRaw = link.source.rawValue
   includeInStatistics = link.includeInStatistics
   splitEnabled = link.splitEnabled
   payerParticipantId = link.payerParticipantId
   splitParticipantIdsData = (try? JSONEncoder().encode(link.splitParticipantIds)) ?? Data("[]".utf8)
   splitParticipantNamesData = (try? JSONEncoder().encode(link.splitParticipantNames)) ?? Data("[]".utf8)
   splitModeRaw = link.splitMode.rawValue
   splitRatio = link.splitRatio
   splitAmount = link.splitAmount
   participantSnapshotData = (try? JSONEncoder().encode(link.participantSnapshot)) ?? Data("[]".utf8)
   configVersion = link.configVersion
   needsReview = link.needsReview
   isSplitCustomized = link.isSplitCustomized
 }

 func toModel() -> TransactionLedgerLink {
   TransactionLedgerLink(
     id: id,
     transactionId: transactionId,
     ledgerId: ledgerId,
     source: TransactionLedgerLinkSource(rawValue: sourceRaw) ?? .manual,
     includeInStatistics: includeInStatistics,
     splitEnabled: splitEnabled,
     payerParticipantId: payerParticipantId,
     splitParticipantIds: (try? JSONDecoder().decode([String].self, from: splitParticipantIdsData)) ?? [],
     splitParticipantNames: (try? JSONDecoder().decode([String].self, from: splitParticipantNamesData)) ?? [],
     splitMode: TransactionSplitMode(rawValue: splitModeRaw) ?? .equal,
     splitRatio: splitRatio,
     splitAmount: splitAmount,
     participantSnapshot: (try? JSONDecoder().decode([LedgerParticipantSnapshot].self, from: participantSnapshotData)) ?? [],
     configVersion: configVersion,
     needsReview: needsReview,
     isSplitCustomized: isSplitCustomized
   )
 }
}
/* /* Legacy duplicate generated tail removed.
esData)) ?? [],
     splitMode: TransactionSplitMode(rawValue: splitModeRaw) ?? .equal,
     splitRatio: splitRatio,
     splitAmount: splitAmount,
     participantSnapshot: (try? JSONDecoder().decode([LedgerParticipantSnapshot].self, from: participantSnapshotData)) ?? [],
     configVersion: configVersion,
     needsReview: needsReview,
     isSplitCustomized: isSplitCustomized
   )
 }
}
*/
*/
