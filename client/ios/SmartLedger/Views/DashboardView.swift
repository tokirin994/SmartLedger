import SwiftUI
import Charts

enum DashboardRange: String, CaseIterable, Identifiable { case week, month, year; var id: String { rawValue }; var title: String { ["week":"本周", "month":"本月", "year":"本年"][rawValue]! }
    func interval(_ date: Date = Date()) -> DateInterval { let c = Calendar.current; let component: Calendar.Component = self == .week ? .weekOfYear : (self == .month ? .month : .year); let start = c.dateInterval(of: component, for: date)!.start; return DateInterval(start: start, end: c.date(byAdding: component, value: 1, to: start)!) }
}
struct DashboardView: View {
    @EnvironmentObject private var store: LedgerStore; @State private var range: DashboardRange = .month; @State private var showCalendar = false; @State private var showBars = false
    private var interval: DateInterval { range.interval() }
    private var scoped: [LedgerTransaction] { store.transactions.filter { interval.contains($0.happenedAt) } }
    private var expense: Double { scoped.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount } }; private var income: Double { scoped.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount } }
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 20) {
        HStack { Text("概览").font(.largeTitle.bold()); Spacer(); Button { showCalendar = true } label: { Image(systemName: "calendar") }; Button { store.save() } label: { Image(systemName: "arrow.clockwise") } }.padding(.horizontal)
        VStack(alignment: .leading, spacing: 12) { Text("统计筛选").font(.headline); Text("\(interval.start.formatted(date: .numeric, time: .omitted)) ~ \(interval.end.addingTimeInterval(-1).formatted(date: .numeric, time: .omitted))").foregroundStyle(.secondary); HStack { ForEach(DashboardRange.allCases) { value in Button { range = value } label: { FilterChip(title: value.title, selected: range == value) } } } }.padding(.horizontal)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { DashboardMetricCard(title: "总支出", value: expense, color: .orange, icon: "arrow.up.right"); DashboardMetricCard(title: "总收入", value: income, color: .green, icon: "arrow.down.left"); DashboardMetricCard(title: "结余", value: income-expense, color: .blue, icon: "banknote"); DashboardMetricCard(title: "预算剩余", value: max(0, store.budgets.reduce(0) { $0 + $1.limitAmount } - expense), color: .purple, icon: "gauge") }.padding(.horizontal)
        GlassCard { VStack(alignment: .leading, spacing: 12) { HStack { Text("分类占比").font(.title3.bold()); Spacer(); Button(showBars ? "饼图" : "柱状图") { showBars.toggle() } }; CategoryChart(transactions: scoped, store: store, bars: showBars) } }.padding(.horizontal)
        GlassCard { VStack(alignment: .leading) { Text("收支趋势").font(.title3.bold()); TrendChart(transactions: scoped) } }.padding(.horizontal)
        GlassCard { VStack(alignment: .leading, spacing: 8) { Text("预算摘要").font(.title3.bold()); ForEach(store.budgets) { budget in BudgetSummaryRow(budget: budget, spent: store.expense(in: interval, categoryID: budget.categoryID)) } } }.padding(.horizontal)
    }.padding(.vertical) }.sheet(isPresented: $showCalendar) { FinanceCalendarSheet() }.navigationBarTitleDisplayMode(.inline) }
}
struct DashboardMetricCard: View { let title: String; let value: Double; let color: Color; let icon: String
    var body: some View { GlassCard { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).foregroundStyle(color).font(.subheadline); Text(value.currency).font(.title2.bold()).minimumScaleFactor(0.6) } } }
}
struct CategoryChart: View { let transactions: [LedgerTransaction]; let store: LedgerStore; let bars: Bool
    private var data: [(String, Double, Color)] { Dictionary(grouping: transactions.filter { $0.kind == .expense }, by: { store.category($0.categoryID)?.name ?? "未分类" }).map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }, store.category($0.value.first?.categoryID)?.color ?? .gray) }.sorted { $0.1 > $1.1 } }
    var body: some View { if data.isEmpty { Text("该时间段暂无支出").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180) } else { Chart(data, id: \.0) { item in if bars { BarMark(x: .value("分类", item.0), y: .value("金额", item.1)).foregroundStyle(item.2) } else { SectorMark(angle: .value("金额", item.1), innerRadius: .ratio(0.55)).foregroundStyle(item.2).annotation(position: .overlay) { Text(item.0).font(.caption2) } } }.frame(height: 220) } }
}
struct TrendChart: View { let transactions: [LedgerTransaction]
    var body: some View { let data = Dictionary(grouping: transactions, by: { Calendar.current.startOfDay(for: $0.happenedAt) }); Chart { ForEach(data.keys.sorted(), id: \.self) { day in let rows = data[day] ?? []; BarMark(x: .value("日期", day, unit: .day), y: .value("支出", rows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount })).foregroundStyle(.orange); LineMark(x: .value("日期", day, unit: .day), y: .value("收入", rows.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount })).foregroundStyle(.green) } }.frame(height: 200) }
}
struct BudgetSummaryRow: View { let budget: Budget; let spent: Double
    var body: some View { VStack(alignment: .leading) { HStack { Text(budget.name); Spacer(); Text("\(spent.currency) / \(budget.limitAmount.currency)").font(.caption).foregroundStyle(.secondary) }; ProgressView(value: min(spent/budget.limitAmount, 1)).tint(spent > budget.limitAmount ? .red : .blue) } }
}
