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

  init(id: Int, name: String, flowTypeRaw: String, icon: String?, color: String?, parentId: Int?, level: Int) {
    self.id = id
    self.name = name
    self.flowTypeRaw = flowTypeRaw
    self.icon = icon
    self.color = color
    self.parentId = parentId
    self.level = level
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
  var spentAmount: Double
  var usageRatio: Double

  init(id: Int, name: String, limitAmount: Double, periodType: String, year: Int, month: Int?, startDate: Date?, endDate: Date?, categoryId: Int?, categoryName: String?, spentAmount: Double, usageRatio: Double) {
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
    let categories = try context.fetch(FetchDescriptor<LedgerCategoryRecord>()).sorted { $0.id < $1.id }
    let books = try context.fetch(FetchDescriptor<LedgerBookRecord>()).sorted { $0.id < $1.id }
    let transactions = try context.fetch(FetchDescriptor<LedgerTransactionRecord>()).sorted { $0.date < $1.date }
    let budgets = try context.fetch(FetchDescriptor<LedgerBudgetRecord>()).sorted { $0.id < $1.id }
    let meta = try context.fetch(FetchDescriptor<LedgerMetaRecord>()).first

    guard meta != nil || !categories.isEmpty || !books.isEmpty || !transactions.isEmpty || !budgets.isEmpty else {
      return nil
    }

    return PersistedLedgerSnapshot(
      categories: buildCategoryTree(from: categories),
      books: books.map { $0.toModel() },
      transactions: transactions.map { $0.toModel() },
      budgets: budgets.map { $0.toModel() },
      nextTransactionId: meta?.nextTransactionId ?? 1000,
      nextBookId: meta?.nextBookId ?? 100,
      nextCategoryId: meta?.nextCategoryId ?? 1000,
      nextBudgetId: meta?.nextBudgetId ?? 100,
      updatedAt: meta?.updatedAt ?? Date()
    )
  }

  func save(_ snapshot: PersistedLedgerSnapshot) throws {
    let context = ModelContext(container)

    try deleteAll(LedgerCategoryRecord.self, in: context)
    try deleteAll(LedgerBookRecord.self, in: context)
    try deleteAll(LedgerTransactionRecord.self, in: context)
try deleteAll(LedgerBudgetRecord.self, in: context)
   try deleteAll(LedgerMetaRecord.self, in: context)

   for category in snapshot.categories {
     context.insert(LedgerCategoryRecord(from: category))
     for child in category.children {
       insert(category: child, into: context)
     }
   }

   for book in snapshot.books {
     context.insert(LedgerBookRecord(from: book))
   }

   for transaction in snapshot.transactions {
     context.insert(LedgerTransactionRecord(from: transaction))
   }

   for budget in snapshot.budgets {
     context.insert(LedgerBudgetRecord(from: budget))
   }

   context.insert(
     LedgerMetaRecord(
       nextTransactionId: snapshot.nextTransactionId,
       nextBookId: snapshot.nextBookId,
       nextCategoryId: snapshot.nextCategoryId,
       nextBudgetId: snapshot.nextBudgetId,
       updatedAt: snapshot.updatedAt
     )
   )

   try context.save()
 }

 private func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
   let items = try context.fetch(FetchDescriptor<T>())
   for item in items {
     context.delete(item)
   }
 }

 private func insert(category: LedgerCategory, into context: ModelContext) {
   context.insert(LedgerCategoryRecord(from: category))
   for child in category.children {
     insert(category: child, into: context)
   }
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
       children: (grouped[record.id] ?? []).sorted { $0.id < $1.id }.map(makeNode)
     )
   }
   return (grouped[nil] ?? []).sorted { $0.id < $1.id }.map(makeNode)
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
     level: category.level
   )
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
     usageRatio: budget.usageRatio
   )
 }

 func toModel() -> BudgetItem {
   BudgetItem(
     id: id,
     name: name,
     limitAmount: limitAmount,
     periodType: periodType,
     categoryId: categoryId,
     categoryName: categoryName,
     year: year,
     month: month,
     startDate: startDate,
     endDate: endDate,
     spentAmount: spentAmount,
     usageRatio: usageRatio
   )
 }
}
