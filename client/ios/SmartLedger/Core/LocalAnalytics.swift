import Foundation

enum LocalAnalytics {
  static func dateWindowsOverlap(_ lhs: DateWindow, _ rhs: DateWindow) -> Bool {
    // Date windows are half-open [start, end), so touching at a boundary is not overlap.
    lhs.start < rhs.end && rhs.start < lhs.end
  }

  static func computeBudgetProgress(transactions: [LedgerTransaction], categories: [LedgerCategory], budgets: [BudgetItem], links: [TransactionLedgerLink] = []) -> [BudgetItem] {
    budgets.map { budget in
      let periodStart: Date
      let periodEnd: Date
      if budget.periodType == "range" {
        periodStart = budget.startDate ?? .distantPast
        periodEnd = budget.endDate ?? .distantFuture
      } else if let month = budget.month {
        var components = DateComponents()
        components.year = budget.year
        components.month = month
        components.day = 1
        let start = Calendar.current.date(from: components) ?? Date()
        periodStart = start
        periodEnd = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? .distantFuture
      } else {
        let interval = Calendar.current.dateInterval(of: .month, for: Date()) ?? DateInterval(start: .now, duration: 30 * 24 * 3600)
        periodStart = interval.start
        periodEnd = interval.end
      }

      let isWithinConfiguredRange = (budget.startDate.map { periodEnd > $0 } ?? true) && (budget.endDate.map { periodStart <= $0 } ?? true)
      let spent = isWithinConfiguredRange ? transactions.filter { tx in
        tx.kind == .expense && tx.happenedAt >= periodStart && tx.happenedAt < periodEnd &&
        matchBudgetCategory(tx: tx, budget: budget, budgets: budgets, categories: categories)
      }.reduce(0.0) { $0 + selfShareAmount(for: $1, links: links) } : 0

      let ratio = budget.limitAmount > 0 ? spent / budget.limitAmount : 0
      return BudgetItem(
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
        spentAmount: (spent * 100).rounded() / 100.0,
        usageRatio: ratio,
        parentBudgetId: budget.parentBudgetId,
        categoryIds: budget.categoryIds,
        keyword: budget.keyword,
      )
    }
  }

  /// Expands recurring monthly templates into read-only month instances for a selected year.
  /// Persisted rules remain templates; these derived instances are only used by analytics/UI.
  static func monthlyBudgetPeriods(budgets: [BudgetItem], transactions: [LedgerTransaction], categories: [LedgerCategory], year: Int, links: [TransactionLedgerLink] = [], now: Date = .now) -> [BudgetItem] {
    let calendar = Calendar.current
    return budgets.flatMap { rule -> [BudgetItem] in
      guard rule.periodType == "monthly", rule.month == nil else { return [rule] }
      let firstMonth = calendar.dateComponents([.year, .month], from: rule.startDate ?? calendar.date(from: DateComponents(year: rule.year, month: 1, day: 1)) ?? now)
      let lowerBound = firstMonth.year == year ? max(firstMonth.month ?? 1, 1) : 1
      let currentYear = calendar.component(.year, from: now)
      let upperBound = year < currentYear ? 12 : (year > currentYear ? 0 : calendar.component(.month, from: now))
      guard lowerBound <= upperBound else { return [] }
      return (lowerBound...upperBound).compactMap { month in
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return nil }
        let effectiveStart = max(monthStart, rule.startDate ?? monthStart)
        let effectiveEnd = min(nextMonth, rule.endDate.map { calendar.date(byAdding: .day, value: 1, to: $0) ?? $0 } ?? nextMonth)
        guard effectiveStart < effectiveEnd else { return nil }
        let spent = transactions.filter { tx in
          tx.kind == .expense && tx.happenedAt >= effectiveStart && tx.happenedAt < effectiveEnd && matchBudgetCategory(tx: tx, budget: rule, budgets: budgets, categories: categories)
        }.reduce(0.0) { $0 + selfShareAmount(for: $1, links: links) }
        let periodKey = year * 12 + month
        let syntheticId = -(abs(rule.id) * 10_000 + periodKey)
        return BudgetItem(id: syntheticId, name: rule.name, limitAmount: rule.limitAmount, periodType: rule.periodType, year: year, month: month, startDate: effectiveStart, endDate: effectiveEnd, categoryId: rule.categoryId, categoryName: rule.categoryName, spentAmount: (spent * 100).rounded() / 100, usageRatio: rule.limitAmount > 0 ? spent / rule.limitAmount : 0, parentBudgetId: rule.parentBudgetId, categoryIds: rule.categoryIds, keyword: rule.keyword)
      }
    }
  }

  static func makeOverview(transactions: [LedgerTransaction], categories: [LedgerCategory], budgets: [BudgetItem], start: Date, end: Date, granularity: Granularity, links: [TransactionLedgerLink] = []) -> AnalyticsOverview {
    let totalIncome = transactions.filter { $0.kind == .income }.reduce(0.0) { $0 + selfShareAmount(for: $1, links: links) }
    let totalExpense = transactions.filter { $0.kind == .expense }.reduce(0.0) { $0 + selfShareAmount(for: $1, links: links) }
    let trend = makeTrend(transactions: transactions, granularity: granularity, links: links)
    let distribution = makeDistribution(transactions: transactions, categories: categories, links: links)
    return AnalyticsOverview(
      start: start.apiDateString,
      end: end.apiDateString,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      balance: totalIncome - totalExpense,
      distribution: distribution,
      trend: trend,
      budgets: computeBudgetProgress(transactions: transactions, categories: categories, budgets: budgets, links: links)
    )
  }

  static func makeCategoryTrend(transactions: [LedgerTransaction], categories: [LedgerCategory], start: Date, end: Date, granularity: Granularity, flowType: FlowType, links: [TransactionLedgerLink] = []) -> CategoryTrendResponse {
    let filtered = transactions.filter { $0.kind == flowType }
    let labels = Array(Set(filtered.map { granularityLabel(for: $0.happenedAt, granularity: granularity) })).sorted()
    var bucket: [String: [String: Double]] = [:]
    var totals: [String: Double] = [:]
    for tx in filtered {
      let label = granularityLabel(for: tx.happenedAt, granularity: granularity)
      let categoryName = rootCategoryName(for: tx, categories: categories)
      let share = selfShareAmount(for: tx, links: links)
      bucket[categoryName, default: [:]][label, default: 0] += share
      totals[categoryName, default: 0] += share
    }
    let top = totals.sorted { $0.value > $1.value }.prefix(8).map { $0.key }
    let series = top.map { name in
      CategoryTrendSeries(category: name, labels: labels, values: labels.map { bucket[name]?[$0] ?? 0 })
    }
    return CategoryTrendResponse(category: flowType.title, labels: labels, series: series)
  }

  private static func makeTrend(transactions: [LedgerTransaction], granularity: Granularity, links: [TransactionLedgerLink]) -> [TrendPoint] {
    var bucket: [String: (income: Double, expense: Double)] = [:]
    for tx in transactions {
      let label = granularityLabel(for: tx.happenedAt, granularity: granularity)
      var current = bucket[label] ?? (0, 0)
      let share = selfShareAmount(for: tx, links: links)
      if tx.kind == .income { current.income += share } else { current.expense += share }
      bucket[label] = current
    }
    return bucket.keys.sorted().map { label in
      let item = bucket[label] ?? (0, 0)
      return TrendPoint(label: label, income: item.income, expense: item.expense, balance: item.income - item.expense)
    }
  }

  static func makeDistribution(transactions: [LedgerTransaction], categories: [LedgerCategory], selectedRootCategoryId: Int? = nil, links: [TransactionLedgerLink] = []) -> [DistributionPoint] {
    let expenseTransactions = transactions.filter { $0.kind == .expense }
    guard !expenseTransactions.isEmpty else { return [] }

    if let selectedRootCategoryId = selectedRootCategoryId {
      return makeChildDistribution(transactions: expenseTransactions, categories: categories, rootCategoryId: selectedRootCategoryId, links: links)
    }

    let totalExpense = expenseTransactions.reduce(0.0) { $0 + selfShareAmount(for: $1, links: links) }
    return makeRootDistribution(transactions: expenseTransactions, categories: categories, totalExpense: totalExpense, links: links)
  }

  private static func makeRootDistribution(transactions: [LedgerTransaction], categories: [LedgerCategory], totalExpense: Double, links: [TransactionLedgerLink]) -> [DistributionPoint] {
    guard totalExpense > 0 else { return [] }
    var bucket: [String: (amount: Double, color: String?)] = [:]
    for tx in transactions {
      let name = rootCategoryName(for: tx, categories: categories)
      let color = rootCategoryColor(for: tx, categories: categories)
      let current = bucket[name] ?? (0, color)
      bucket[name] = (current.amount + selfShareAmount(for: tx, links: links), color)
    }
    return bucket.map { key, value in
      DistributionPoint(category: key, amount: value.amount, ratio: value.amount / totalExpense, color: value.color)
    }.sorted { $0.amount > $1.amount }
  }

  private static func makeChildDistribution(transactions: [LedgerTransaction], categories: [LedgerCategory], rootCategoryId: Int, links: [TransactionLedgerLink]) -> [DistributionPoint] {
    guard let rootCategory = categories.first(where: { $0.id == rootCategoryId && $0.parentId == nil }) else { return [] }
    let hasChildren = categories.contains { $0.parentId == rootCategoryId }

    var bucket: [String: (amount: Double, color: String?)] = [:]
    for tx in transactions {
      guard let categoryId = tx.categoryId else { continue }
      let category = categories.first(where: { $0.id == categoryId }) ?? rootCategory

      let path = category.pathComponents
      // `categories` is a flattened tree. Restrict the detailed chart to the
      // selected root; otherwise every category's second path component (for
      // example another root's “零食”) is accidentally rendered here.
      guard path.first == rootCategory.name else { continue }
      // A first-level leaf has no child rows, but it is still a valid
      // selector item. Render its own transactions as one distribution item.
      guard path.count >= 2 || !hasChildren else { continue }

      let childName = path.count >= 2 ? path[1] : rootCategory.name
      // A selected primary category is intentionally rendered as one hue
      // family, so the detailed donut/bar chart remains visually connected to
      // the same primary category used elsewhere on the dashboard.
      let childColor = rootCategory.color

      let current = bucket[childName] ?? (0, childColor)
      bucket[childName] = (current.amount + selfShareAmount(for: tx, links: links), childColor)
    }

    let totalExpense = bucket.values.reduce(0.0) { $0 + $1.amount }
    guard totalExpense > 0 else { return [] }

    return bucket.map { key, value in
      DistributionPoint(category: key, amount: value.amount, ratio: value.amount / totalExpense, color: value.color)
    }
    .sorted { $0.amount > $1.amount }
    .enumerated()
    .map { index, item in
      DistributionPoint(
        category: item.category,
        amount: item.amount,
        ratio: item.ratio,
        color: colorVariant(of: rootCategory.color, index: index)
      )
    }
  }

  private static func matchBudgetCategory(tx: LedgerTransaction, budget: BudgetItem, budgets: [BudgetItem], categories: [LedgerCategory]) -> Bool {
    if let parentId = budget.parentBudgetId, let parent = budgets.first(where: { $0.id == parentId }) {
      guard matchesCategoryScope(tx: tx, selectedIds: parent.categoryIds, categoryId: parent.categoryId, categories: categories),
            matchesKeyword(tx: tx, keyword: parent.keyword) else { return false }
    }
    guard matchesCategoryScope(tx: tx, selectedIds: budget.categoryIds, categoryId: budget.categoryId, categories: categories) else { return false }
    return matchesKeyword(tx: tx, keyword: budget.keyword)
  }

  private static func matchesKeyword(tx: LedgerTransaction, keyword: String?) -> Bool {
    guard let keyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !keyword.isEmpty else { return true }
    let fields = [tx.title, tx.merchant ?? "", tx.note ?? "", tx.paymentMethod ?? ""]
    return fields.contains { $0.localizedCaseInsensitiveContains(keyword) }
  }

  private static func matchesCategoryScope(tx: LedgerTransaction, selectedIds: [Int]?, categoryId: Int?, categories: [LedgerCategory]) -> Bool {
    let selectedIds = selectedIds ?? categoryId.map { [$0] }
    guard let selectedIds, !selectedIds.isEmpty else { return true }
    guard let txCategoryId = tx.categoryId else { return false }
    return selectedIds.contains { categoryId in
      if txCategoryId == categoryId { return true }
      // Selecting a category includes its descendants.
      guard let selected = categories.first(where: { $0.id == categoryId }),
            let transactionCategory = categories.first(where: { $0.id == txCategoryId }) else { return false }
      return transactionCategory.pathComponents.starts(with: selected.pathComponents)
    }
  }

  private static func rootCategoryName(for tx: LedgerTransaction, categories: [LedgerCategory]) -> String {
    guard let categoryId = tx.categoryId else { return "未分类" }
    return flattenedRoot(for: categoryId, categories: categories)?.name ?? tx.categoryName ?? "未分类"
  }

  private static func rootCategoryColor(for tx: LedgerTransaction, categories: [LedgerCategory]) -> String? {
    guard let categoryId = tx.categoryId else { return "#94A3B8" }
    return flattenedRoot(for: categoryId, categories: categories)?.color ?? "#94A3B8"
  }

  private static func rootCategoryId(for categoryId: Int, categories: [LedgerCategory]) -> Int? {
    flattenedRoot(for: categoryId, categories: categories)?.id
  }

  private static func colorVariant(of hex: String?, index: Int) -> String? {
    guard let hex else { return nil }
    let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard normalized.count == 6, let value = Int(normalized, radix: 16) else { return hex }
    let red = Double((value >> 16) & 0xFF)
    let green = Double((value >> 8) & 0xFF)
    let blue = Double(value & 0xFF)
    // Alternate subtly darker and lighter variants while retaining the hue.
    let mixWithWhite = [0.0, 0.20, -0.16, 0.36, -0.28][index % 5]
    func adjusted(_ component: Double) -> Int {
      let result = mixWithWhite >= 0
        ? component + (255 - component) * mixWithWhite
        : component * (1 + mixWithWhite)
      return min(max(Int(result.rounded()), 0), 255)
    }
    return String(format: "#%02X%02X%02X", adjusted(red), adjusted(green), adjusted(blue))
  }

  private static func flattenedRoot(for categoryId: Int, categories: [LedgerCategory]) -> LedgerCategory? {
    let all = categories
    guard let current = all.first(where: { $0.id == categoryId }) else { return nil }
    let path = current.name.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
    guard let rootName = path.first else { return current }
    return all.first(where: { $0.parentId == nil && $0.name == rootName }) ?? current
  }

  private static func selfShareAmount(for transaction: LedgerTransaction, links: [TransactionLedgerLink]) -> Double {
    guard !links.isEmpty else { return transaction.selfShareAmount }
    let candidates = links.filter { $0.transactionId == transaction.id }.sorted { $0.ledgerId < $1.ledgerId }
    guard let link = candidates.first else {
      // Unbound transactions continue to use the legacy split fields.
      return transaction.selfShareAmount
    }
    guard link.includeInStatistics else { return 0 }
    guard link.splitEnabled, !link.splitParticipantIds.isEmpty else { return transaction.amount }
    return link.selfShareAmount(for: transaction.amount) ?? transaction.selfShareAmount
  }

  private static func granularityLabel(for date: Date, granularity: Granularity) -> String {
    switch granularity {
    case .day:
      return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
    case .week:
      let iso = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
      return "\(iso.yearForWeekOfYear ?? 0)-W\(String(format: "%02d", iso.weekOfYear ?? 0))"
    case .month:
      return date.formatted(.dateTime.year().month(.twoDigits))
    case .year:
      return date.formatted(.dateTime.year())
    }
  }
}

private extension Int {}
