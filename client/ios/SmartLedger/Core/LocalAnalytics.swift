import Foundation

enum LocalAnalytics {
  static func computeBudgetProgress(transactions: [LedgerTransaction], categories: [LedgerCategory], budgets: [BudgetItem]) -> [BudgetItem] {
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
        matchBudgetCategory(tx: tx, budget: budget, categories: categories)
      }.reduce(0.0) { $0 + $1.amount } : 0

      let ratio = budget.limitAmount > 0 ? spent / budget.limitAmount : 0
      return BudgetItem(
        id: budget.id,
        name: budget.name,
        limitAmount: budget.limitAmount,
        periodType: budget.periodType,
        categoryId: budget.categoryId,
        categoryName: budget.categoryName,
        year: budget.year,
        month: budget.month,
        startDate: budget.startDate,
        endDate: budget.endDate,
        spentAmount: (spent * 100).rounded() / 100.0,
        usageRatio: ratio
      )
    }
  }

  static func makeOverview(transactions: [LedgerTransaction], categories: [LedgerCategory], budgets: [BudgetItem], start: Date, end: Date, granularity: Granularity) -> AnalyticsOverview {
    let totalIncome = transactions.filter { $0.kind == .income }.reduce(0.0) { $0 + $1.amount }
    let totalExpense = transactions.filter { $0.kind == .expense }.reduce(0.0) { $0 + $1.amount }
    let trend = makeTrend(transactions: transactions, granularity: granularity)
    let distribution = makeDistribution(transactions: transactions, categories: categories)
    return AnalyticsOverview(
      start: start.apiDateString,
      end: end.apiDateString,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      balance: totalIncome - totalExpense,
      distribution: distribution,
      trend: trend,
      budgets: computeBudgetProgress(transactions: transactions, categories: categories, budgets: budgets)
    )
  }

  static func makeCategoryTrend(transactions: [LedgerTransaction], categories: [LedgerCategory], start: Date, end: Date, granularity: Granularity, flowType: FlowType) -> CategoryTrendResponse {
    let filtered = transactions.filter { $0.kind == flowType }
    let labels = Array(Set(filtered.map { granularityLabel(for: $0.happenedAt, granularity: granularity) })).sorted()
    var bucket: [String: [String: Double]] = [:]
    var totals: [String: Double] = [:]
    for tx in filtered {
      let label = granularityLabel(for: tx.happenedAt, granularity: granularity)
      let categoryName = rootCategoryName(for: tx, categories: categories)
      bucket[categoryName, default: [:]][label, default: 0] += tx.amount
      totals[categoryName, default: 0] += tx.amount
    }
    let top = totals.sorted { $0.value > $1.value }.prefix(8).map { $0.key }
    let series = top.map { name in
      CategoryTrendSeries(category: name, labels: labels, values: labels.map { bucket[name]?[$0] ?? 0 })
    }
    return CategoryTrendResponse(category: flowType.title, labels: labels, series: series)
  }

  private static func makeTrend(transactions: [LedgerTransaction], granularity: Granularity) -> [TrendPoint] {
    var bucket: [String: (income: Double, expense: Double)] = [:]
    for tx in transactions {
      let label = granularityLabel(for: tx.happenedAt, granularity: granularity)
      var current = bucket[label] ?? (0, 0)
      if tx.kind == .income { current.income += tx.amount } else { current.expense += tx.amount }
      bucket[label] = current
    }
    return bucket.keys.sorted().map { label in
      let item = bucket[label] ?? (0, 0)
      return TrendPoint(label: label, income: item.income, expense: item.expense, balance: item.income - item.expense)
    }
  }

  static func makeDistribution(transactions: [LedgerTransaction], categories: [LedgerCategory], selectedRootCategoryId: Int? = nil) -> [DistributionPoint] {
    let expenseTransactions = transactions.filter { $0.kind == .expense }
    guard !expenseTransactions.isEmpty else { return [] }

    if let selectedRootCategoryId = selectedRootCategoryId {
      return makeChildDistribution(transactions: expenseTransactions, categories: categories, rootCategoryId: selectedRootCategoryId)
    }

    let totalExpense = expenseTransactions.reduce(0.0) { $0 + $1.amount }
    return makeRootDistribution(transactions: expenseTransactions, categories: categories, totalExpense: totalExpense)
  }

  private static func makeRootDistribution(transactions: [LedgerTransaction], categories: [LedgerCategory], totalExpense: Double) -> [DistributionPoint] {
    guard totalExpense > 0 else { return [] }
    var bucket: [String: (amount: Double, color: String?)] = [:]
    for tx in transactions {
      let name = rootCategoryName(for: tx, categories: categories)
      let color = rootCategoryColor(for: tx, categories: categories)
      let current = bucket[name] ?? (0, color)
      bucket[name] = (current.amount + tx.amount, color)
    }
    return bucket.map { key, value in
      DistributionPoint(category: key, amount: value.amount, ratio: value.amount / totalExpense, color: value.color)
    }.sorted { $0.amount > $1.amount }
  }

  private static func makeChildDistribution(transactions: [LedgerTransaction], categories: [LedgerCategory], rootCategoryId: Int) -> [DistributionPoint] {
    guard let rootCategory = categories.first(where: { $0.id == rootCategoryId && $0.level == 1 }) else { return [] }
    let hasChildren = categories.contains { $0.parentId == rootCategoryId }

    var bucket: [String: (amount: Double, color: String?)] = [:]
    for tx in transactions {
      guard let categoryId = tx.categoryId else { continue }
      let category = categories.first(where: { $0.id == categoryId }) ?? rootCategory

      let path = category.pathComponents
      guard path.count >= 2 else { continue }

      let childName = path.count == 2 ? path[1] : (hasChildren ? "未分类" : rootCategory.name)
      // A selected primary category is intentionally rendered as one hue
      // family, so the detailed donut/bar chart remains visually connected to
      // the same primary category used elsewhere on the dashboard.
      let childColor = rootCategory.color

      let current = bucket[childName] ?? (0, childColor)
      bucket[childName] = (current.amount + tx.amount, childColor)
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

  private static func matchBudgetCategory(tx: LedgerTransaction, budget: BudgetItem, categories: [LedgerCategory]) -> Bool {
    guard let categoryId = budget.categoryId else { return true }
    guard let txCategoryId = tx.categoryId else { return false }
    if txCategoryId == categoryId { return true }
    let rootId = rootCategoryId(for: txCategoryId, categories: categories)
    return rootId == categoryId
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
    return all.first(where: { $0.level == 1 && $0.name == rootName }) ?? current
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
