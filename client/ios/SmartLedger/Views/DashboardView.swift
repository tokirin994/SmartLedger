import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var settings: AppSettings
@Environment(\.colorScheme) private var colorScheme
@State private var preset: OverviewPreset = .month
@State private var showCalendarSheet = false
@State private var showRangeSheet = false
@State private var distributionMode: DistributionChartMode = .pie
@State private var selectedDistributionRootId: Int?

var body: some View {
    NavigationStack {
        ScrollView {
            VStack(spacing: 16) {
                filterSection
                summaryGrid
                distributionSection
                trendSection
                budgetsSection
            }
        }
        .padding()
        .appBackground()
        .navigationTitle("概览")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showCalendarSheet = true
                } label: {
                    Image(systemName: "calendar")
                }

                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $showCalendarSheet) {
            FinanceCalendarSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showRangeSheet) {
            DashboardRangePickerSheet(
                selectedPreset: $preset,
                onSelectPreset: { selected in
                    preset = selected
                    Task { await reload() }
                },
                onSelectPinnedRange: { range in
                    Task {
                        await store.refreshDashboard(customRange: range, granularity: granularity(for: range))
                        await reload()
                    }
                }
            )
            .environmentObject(store)
            .environmentObject(settings)
        }
        .task {
            if store.overview == nil {
                store.activeRangePreset = preset.dateRangePreset
                store.activeGranularity = preset.defaultGranularity
                await store.bootstrapIfNeeded()
            }
        }
        .refreshable {
            await reload()
            await store.loadTransactions()
        }
        .alert("提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { _ in store.errorMessage = nil
        })) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private var filterSection: some View {
    SectionCard(title: "统计筛选", subtitle: "首页仅保留周 / 月 / 年切换，右上角日历可查看每天收支") {
        VStack(alignment: .leading, spacing: 12) {
            if let overview = store.overview {
                HStack(spacing: 8) {
                    Button {
                        showRangeSheet = true
                    } label: {
                        Label("\(overview.start) ~ \(overview.end)", systemImage: "calendar.badge.clock")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Label(preset.defaultGranularity.title + "维度", systemImage: "chart.bar.xaxis")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.08), in: Capsule())

                    Spacer(minLength: 0)

                    Text(store.transactions.count.formatted() + " 笔")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.08), in: Capsule())
                }

                HStack(spacing: 8) {
                    ForEach(OverviewPreset.allCases) { item in
                        Button {
                            preset = item
                            Task { await reload() }
                        } label: {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(preset == item ? selectedPresetForeground : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    preset == item ? selectedPresetBackground : unselectedPresetBackground,
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(preset == item ? selectedPresetStroke : unselectedPresetStroke,
                                        lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

private var summaryGrid: some View {
    let overview = store.overview
    return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        MetricCard(
            title: "总支出",
            value: (overview?.totalExpense ?? 0).cnyText,
            subtitle: "当前区间支出总额",
            color: .orange,
            systemImage: "arrow.up.right.circle.fill"
        )
        MetricCard(
            title: "总收入",
            value: (overview?.totalIncome ?? 0).cnyText,
            subtitle: "当前区间收入总额",
            color: .green,
            systemImage: "arrow.down.left.circle.fill"
        )
        MetricCard(
            title: "结余",
            value: (overview?.balance ?? 0).cnyText,
            subtitle: "收入减去支出",
            color: .blue,
            systemImage: "banknote.fill"
        )
        MetricCard(
            title: "预算剩余",
            value: remainingBudget.cnyText,
            subtitle: "根据预算自动计算",
                color: .purple,
                systemImage: "gauge.with.needle.fill"
            )
        }
    }

    private var trendSection: some View {
        SectionCard(title: "收支趋势", subtitle: trendSubtitle) {
            if let trend = store.overview?.trend, !trend.isEmpty {
                CompactLegendView(items: trendLegendItems)

                FixedYAxisScrollableChart(
                    itemCount: trend.count,
                    minimumSlotWidth: 58,
                    height: 260,
                    yDomain: trendYDomain,
                    yTicks: trendYTicks,
                    axisStyle: .compact
                ) {
                    Chart {
                        ForEach(trendYTicks) { tick in
                            RuleMark(y: .value("刻度", tick.value))
                                .foregroundStyle(Color.secondary.opacity(0.16))
                                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                        }

                        ForEach(trend) { item in
                            BarMark(
                                x: .value("时间", item.label),
                                y: .value("支出", item.expense)
                            )
                            .foregroundStyle(Color.orange.gradient)

                            LineMark(
                                x: .value("时间", item.label),
                                y: .value("收入", item.income)
                            )
                            .foregroundStyle(Color.green)
                            .symbol(Circle())

                            LineMark(
                                x: .value("时间", item.label),
                                y: .value("结余", item.balance)
                            )
                            .foregroundStyle(Color.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        }
                    }
                    .chartLegend(.hidden)
                    .chartYScale(domain: trendYDomain)
                    .chartYAxis(.hidden)
                }
            } else {
                ContentUnavailableView("暂无趋势数据", systemImage: "chart.bar")
            }
        }
    }

    private var categoryTrendSection: some View {
        SectionCard(title: "分类变化趋势", subtitle: "查看不同类别在多个时间段的消费变化") {
            if store.categoryTrendPoints.isEmpty {
                ContentUnavailableView("暂无分类趋势", systemImage: "chart.line.uptrend.xyaxis")
            } else {
                CompactLegendView(items: categoryTrendLegendItems)

                FixedYAxisScrollableChart(
                    itemCount: store.categoryTrend?.labels.count ?? 0,
                    minimumSlotWidth: 64,
                    height: 280,
                    yDomain: categoryTrendYDomain,
                    yTicks: categoryTrendYTicks,
                    axisStyle: .compact
                ) {
                    Chart {
                        ForEach(categoryTrendYTicks) { tick in
                            RuleMark(y: .value("刻度", tick.value))
                                .foregroundStyle(Color.secondary.opacity(0.16))
                                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                        }

                        ForEach(store.categoryTrendPoints) { point in
                            LineMark(
                                x: .value("时间", point.label),
                                y: .value("金额", point.value),
                                series: .value("分类", point.category)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(categoryTrendColor(for: point.category))

                            PointMark(
                                x: .value("时间", point.label),
                                y: .value("金额", point.value)
                            )
                            .foregroundStyle(categoryTrendColor(for: point.category))
                        }
                    }
                    .chartLegend(.hidden)
                    .chartYScale(domain: categoryTrendYDomain)
                    .chartYAxis(.hidden)
                }
            }
        }
    }

    private var distributionSection: some View {
        SectionCard(title: "分类占比", subtitle: distributionSubtitle, headerTrailing: {
            HStack(spacing: 8) {
                Menu {
                    Button("全部大类") {
                        selectedDistributionRootId = nil
                    }

                    Divider()

                    ForEach(rootExpenseCategories) { category in
                        Button(category.name) {
                            selectedDistributionRootId = category.id
                        }
                    }
                } label: {
                    Label(distributionSelectionTitle, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(filterChipBackground, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(filterChipStroke, lineWidth: 1)
                        }
                }
            }
        }) {
            VStack(spacing: 16) {
                if !distributionData.isEmpty {
                    Group {
                        if distributionMode == .pie {
                            DistributionDonutCalloutView(items: distributionData)
                        } else {
                            ScrollableDistributionBarChart(
                                items: distributionData,
                                yDomain: distributionYDomain,
                                yTicks: distributionYTicks
                            )
                        }
                    }
                    .frame(height: distributionChartHeight)
                    .onTapGesture {
                        withAnimation(.smooth(duration: 0.22)) {
                            distributionMode = distributionMode == .pie ? .bar : .pie
                        }
                    }

                    distributionLegend

                } else {
                    ContentUnavailableView(
                        selectedDistributionRootId == nil ? "暂无分类占比" : "当前大类下暂无可展示的子分类占比",
                        systemImage: "chart.pie"
                    )
                }
            }
        }
    }

    private var distributionData: [DistributionPoint] {
        LocalAnalytics.makeDistribution(
            transactions: currentWindowTransactions,
            categories: store.flattenedCategories,
            selectedRootCategoryId: selectedDistributionRootId
        )
    }

    private var distributionSubtitle: String {
        if let selectedRootId = selectedDistributionRootId,
           let category = rootExpenseCategories.first(where: { $0.id == selectedRootId }) {
            return "当前查看「\(category.name)」下各子类支出占比"
        }
        return "默认按大类统计本区间支出占比，点击图表可切换柱状图"
    }

    private var trendSubtitle: String {
        "当前「\(preset.title)」按\(preset.defaultGranularity.title)维度展示: 本年看月，本月看周，本周看日"
    }

    private var distributionSelectionTitle: String {
        if let selectedRootId = selectedDistributionRootId,
           let category = rootExpenseCategories.first(where: { $0.id == selectedRootId }) {
            return category.name
        }
        return "全部大类"
    }

    private var distributionChartHeight: CGFloat {
        switch distributionMode {
        case .bar:
            return 260
        case .pie:
            let dynamicHeight = 220 + CGFloat(max(distributionData.count - 6, 0)) * 18
            return max(260, min(dynamicHeight, 420))
        }
    }

    private var rootExpenseCategories: [LedgerCategory] {
        store.flattenedCategories
            .filter { $0.level == 1 && $0.flowType == .expense }
            .sorted { $0.id < $1.id }
    }

    private var currentWindowTransactions: [LedgerTransaction] {
        let window: DateWindow
        if store.activeRangePreset == preset.dateRangePreset {
            window = preset.dateRangePreset.resolve()
        } else {
            window = store.activeCustomRange.resolvedWindow
        }
        return store.transactions.filter { $0.happenedAt >= window.start && $0.happenedAt < window.end }
    }

    private var trendLegendItems: [LegendDisplayItem] {
        [
            LegendDisplayItem(title: "支出", color: .orange),
            LegendDisplayItem(title: "收入", color: .green),
            LegendDisplayItem(title: "结余", color: .blue)
        ]
    }

    private var categoryTrendLegendItems: [LegendDisplayItem] {
        (store.categoryTrend?.series ?? []).map {
            LegendDisplayItem(title: $0.category, color: categoryTrendColor(for: $0.category))
        }
    }

    private var trendYDomain: ClosedRange<Double> {
        let values = (store.overview?.trend ?? []).flatMap { [$0.expense, $0.income, $0.balance] }
        return paddedDomain(for: values)
    }

    private var trendYTicks: [YAxisTickItem] {
        makeYAxisTicks(domain: trendYDomain)
    }

    private var categoryTrendYDomain: ClosedRange<Double> {
        let values = (store.categoryTrend?.series ?? []).flatMap(\.values)
        return positivePaddedDomain(for: values)
    }

    private var categoryTrendYTicks: [YAxisTickItem] {
        makeYAxisTicks(domain: categoryTrendYDomain)
    }

    private var distributionYDomain: ClosedRange<Double> {
        positivePaddedDomain(for: distributionData.map(\.amount))
    }

    private var distributionYTicks: [YAxisTickItem] {
        makeYAxisTicks(domain: distributionYDomain)
    }

    private func categoryTrendColor(for category: String) -> Color {
        let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .red, .indigo]
        let labels = (store.categoryTrend?.series.map(\.category) ?? []).sorted()
        guard let index = labels.firstIndex(of: category) else { return .accentColor }
        return palette[index % palette.count]
    }

    private func paddedDomain(for values: [Double]) -> ClosedRange<Double> {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...100
        }
        if minValue == maxValue {
            let padding = max(abs(minValue) * 0.15, 10)
            return (minValue - padding)...(maxValue + padding)
        }

        let range = maxValue - minValue
        let padding = max(range * 0.12, 8)
        return (minValue - padding)...(maxValue + padding)
    }

    private func positivePaddedDomain(for values: [Double]) -> ClosedRange<Double> {
        guard let maxValue = values.max(), maxValue > 0 else {
            return 0...100
        }

        let padding = max(maxValue * 0.18, 12)
        return 0...(maxValue + padding)
    }

    private func makeYAxisTicks(domain: ClosedRange<Double>, count: Int = 4) -> [YAxisTickItem] {
        guard count > 1 else {
            return [YAxisTickItem(value: domain.upperBound, label: domain.upperBound.cnyAxisText)]
        }

        let step = (domain.upperBound - domain.lowerBound) / Double(count - 1)
        return (0..<count).map { index in
            let value = domain.lowerBound + Double(index) * step
            return YAxisTickItem(value: value, label: value.cnyAxisText)
        }
    }

    private var distributionLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(distributionData) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(item.displayColor)
                            .frame(width: 8, height: 8)

                        Text(item.category)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var budgetsSection: some View {
        SectionCard(title: "预算跟踪", subtitle: "显示预算结余与占比卡片") {
            if store.budgets.isEmpty {
                ContentUnavailableView("暂无预算", systemImage: "wallet.pass")
            } else {
                VStack(spacing: 14) {
                    ForEach(store.budgets) { budget in
                        BudgetStatusCard(item: budget)
                    }
                }
            }
        }
    }

    private var recentTransactionsSection: some View {
        SectionCard(title: "最近流水", subtitle: "包含分期拆分后的每月流水") {
            if store.transactions.isEmpty {
                ContentUnavailableView("暂无流水", systemImage: "list.bullet.rectangle")
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(store.transactions.prefix(8)), id: \.id) { tx in
                        transactionRow(tx)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func transactionRow(_ tx: LedgerTransaction) -> some View {
        let iconName = tx.kind == .expense ? "minus.circle.fill" : "plus.circle.fill"
        let iconColor: Color = tx.kind == .expense ? .orange : .green
        let amountText = (tx.kind == .expense ? -tx.amount : tx.amount).cnyText
        let amountColor: Color = tx.kind == .expense ? .primary : .green

        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(tx.title)
                    .font(.subheadline.weight(.medium))

                Text(tx.categoryName ?? "未分类")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let merchant = tx.merchant {
                    Text(merchant)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(amountText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(amountColor)

                Text(tx.happenedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var remainingBudget: Double {
        guard !store.budgets.isEmpty else { return 0 }
        return store.budgets.reduce(0) { $0 + max($1.limitAmount - $1.spentAmount, 0) }
    }

    private func reload() async {
        await store.refreshDashboard(range: preset.dateRangePreset, granularity: preset.defaultGranularity)
    }

    private var filterChipBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.34)
    }

    private var filterChipStroke: Color {
        Color.white.opacity(colorScheme == .dark ? 0.14 : 0.28)
    }

    private var selectedPresetForeground: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : Color.black.opacity(0.82)
    }

    private var selectedPresetBackground: Color {
        colorScheme == .dark ? Color.blue.opacity(0.30) : Color.blue.opacity(0.18)
    }

    private var unselectedPresetBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.26)
    }

    private var selectedPresetStroke: Color {
        colorScheme == .dark ? Color.blue.opacity(0.34) : Color.blue.opacity(0.24)
    }

    private var unselectedPresetStroke: Color {
        Color.white.opacity(colorScheme == .dark ? 0.12 : 0.24)
    }

    private func granularity(for range: CustomDateRange) -> Granularity {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: range.start)
        let end = calendar.startOfDay(for: range.end)
        let days = max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0) + 1

        if days <= 10 { return .day }
        if days <= 92 { return .week }
        return .month
    }

    private func percentText(for item: DistributionPoint) -> String {
        String(format: "%.1f%%", item.ratio * 100)
    }
}

private enum DistributionChartMode: CaseIterable {
    case pie
    case bar
}

private struct DistributionDonutCalloutView: View {
    let items: [DistributionPoint]

    private let preferredLabelSpacing: CGFloat = 18
    private let minimumLabelSpacing: CGFloat = 6
    private let labelWidth: CGFloat = 52

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let outerRadius = size * 0.34
            let innerRadius = outerRadius * 0.56
            let callouts = calloutLayouts(size: geometry.size, center: center, outerRadius: outerRadius)

            ZStack {
                ForEach(Array(segments.enumerated()), id: \.element.item.id) { _, segment in
                    DonutSliceShape(
                        startAngle: segment.startAngle,
                        endAngle: segment.endAngle,
                        innerRadiusRatio: innerRadius / outerRadius
                    )
                    .fill(segment.item.displayColor)
                    .frame(width: outerRadius * 2, height: outerRadius * 2)
                    .position(center)
                }

                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: innerRadius * 2, height: innerRadius * 2)
                    .position(center)

                ForEach(callouts) { callout in
                    Path { path in
                        path.move(to: callout.start)
                        path.addLine(to: callout.mid)
                        path.addLine(to: callout.end)
                    }
                    .stroke(Color.secondary.opacity(0.6), lineWidth: 1)

                    Text(percentText(for: callout.item))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
         .frame(width: labelWidth, alignment: callout.isRightSide ? .leading : .trailing)
         .position(x: callout.labelCenter.x, y: callout.labelCenter.y)
     }
   }
   .frame(maxWidth: .infinity, maxHeight: .infinity)
 }
}

  private var segments: [DistributionSegment] {
   var current = -90.0
   return items.map { item in
     let delta = item.ratio * 360
     let segment = DistributionSegment(item: item, startAngle: .degrees(current), endAngle: .degrees(current + delta))
     current += delta
     return segment
   }
 }
 
 private func calloutLayouts(size: CGSize, center: CGPoint, outerRadius: CGFloat) -> [DonutCalloutLayout] {
   let raw = segments.map { segment -> RawCallout in
     let points = rawCalloutPoints(for: segment, center: center, outerRadius: outerRadius)
     return RawCallout(
       item: segment.item,
       start: points.start,
       mid: points.mid,
       preferredY: points.preferredY,
       isRightSide: points.isRightSide
     )
   }
 
   let verticalPadding: CGFloat = 10
   let bounds = verticalPadding...(size.height - verticalPadding)
 
   let left = resolveCallouts(raw.filter { !$0.isRightSide }, endX: center.x - (outerRadius + 34), bounds: bounds)
   let right = resolveCallouts(raw.filter { $0.isRightSide }, endX: center.x + (outerRadius + 34), bounds: bounds)
   return (left + right).sorted { $0.item.amount > $1.item.amount }
 }
 
 private func resolveCallouts(_ items: [RawCallout], endX: CGFloat, bounds: ClosedRange<CGFloat>) -> [DonutCalloutLayout] {
   guard !items.isEmpty else { return [] }
 
   let sorted = items.sorted { $0.preferredY < $1.preferredY }
   let availableHeight = bounds.upperBound - bounds.lowerBound
   let spacing: CGFloat = {
     guard sorted.count > 1 else { return preferredLabelSpacing }
     let maxFitSpacing = availableHeight / CGFloat(sorted.count - 1)
     return max(minimumLabelSpacing, min(preferredLabelSpacing, maxFitSpacing))
   }()
 
   var ys = sorted.map { min(max($0.preferredY, bounds.lowerBound), bounds.upperBound) }
   for index in 1..<ys.count {
     ys[index] = max(ys[index], ys[index - 1] + spacing)
   }
 
   if let last = ys.last, last > bounds.upperBound {
     ys[ys.count - 1] = bounds.upperBound
     if ys.count > 1 {
       for index in stride(from: ys.count - 2, through: 0, by: -1) {
         ys[index] = min(ys[index], ys[index + 1] - spacing)
       }
     }
   }
   if let first = ys.first, first < bounds.lowerBound {
     ys[0] = bounds.lowerBound
     if ys.count > 1 {
       for index in 1..<ys.count {
         ys[index] = max(ys[index], ys[index - 1] + spacing)
       }
     }
   }
 
   return zip(sorted, ys).map { raw, resolvedY in
     let end = CGPoint(x: endX, y: resolvedY)
     let labelCenter = CGPoint(x: endX + (raw.isRightSide ? (labelWidth / 2 + 6) : -(labelWidth / 2 + 6)), y: resolvedY)
     return DonutCalloutLayout(
       item: raw.item,
       start: raw.start,
       mid: raw.mid,
       end: end,
       labelCenter: labelCenter,
       isRightSide: raw.isRightSide
     )
   }
 }
 
 private func rawCalloutPoints(for segment: DistributionSegment, center: CGPoint, outerRadius: CGFloat) -> (start: CGPoint, mid: CGPoint, preferredY: CGFloat, isRightSide: Bool) {
   let midAngle = (segment.startAngle.degrees + segment.endAngle.degrees) / 2
   let radians = CGFloat(midAngle) * .pi / 180
 
   let start = CGPoint(
     x: center.x + cos(radians) * (outerRadius + 6),
     y: center.y + sin(radians) * (outerRadius + 6)
   )
   let mid = CGPoint(
     x: center.x + cos(radians) * (outerRadius + 18),
     y: center.y + sin(radians) * (outerRadius + 18)
   )
 
   let isRightSide = cos(radians) >= 0
   return (start, mid, mid.y, isRightSide)
 }
 
  private func percentText(for item: DistributionPoint) -> String {
    String(format: "%.1f%%", item.ratio * 100)
  }
}

private struct ScrollableDistributionBarChart: View {
   let items: [DistributionPoint]
   let yDomain: ClosedRange<Double>
   let yTicks: [YAxisTickItem]
 
   var body: some View {
     FixedYAxisScrollableChart(
       itemCount: items.count,
       minimumSlotWidth: 80,
       height: 260,
       yDomain: yDomain,
       yTicks: yTicks,
       axisStyle: .compact
     ) {
       Chart {
         ForEach(yTicks) { tick in
           RuleMark(y: .value("刻度", tick.value))
             .foregroundStyle(Color.secondary.opacity(0.16))
             .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
         }
 
         ForEach(items) { item in
           BarMark(
             x: .value("分类", item.category),
             y: .value("金额", item.amount)
           )
           .foregroundStyle(item.displayColor)
           .annotation(position: .top, spacing: 6) {
             Text(item.amount.cnyShortText)
               .font(.caption2.weight(.semibold))
           }
         }
       }
       .chartLegend(.hidden)
       .chartYScale(domain: yDomain)
       .chartYAxis(.hidden)
     }
   }
 }
 
private struct FixedYAxisScrollableChart<Content: View>: View {
   let itemCount: Int
   let minimumSlotWidth: CGFloat
   let height: CGFloat
   let yDomain: ClosedRange<Double>
   let yTicks: [YAxisTickItem]
   let axisStyle: FixedYAxisStyle
   @ViewBuilder let content: () -> Content
 
   init(
     itemCount: Int,
     minimumSlotWidth: CGFloat,
     height: CGFloat,
     yDomain: ClosedRange<Double>,
     yTicks: [YAxisTickItem],
     axisStyle: FixedYAxisStyle = .compact,
     @ViewBuilder content: @escaping () -> Content
   ) {
     self.itemCount = itemCount
     self.minimumSlotWidth = minimumSlotWidth
     self.height = height
     self.yDomain = yDomain
     self.yTicks = yTicks
     self.axisStyle = axisStyle
     self.content = content
   }
 
   var body: some View {
     GeometryReader { geometry in
       let plotWidth = max(geometry.size.width - axisWidth - spacing, 120)
       let contentWidth = max(plotWidth, CGFloat(max(itemCount, 1)) * minimumSlotWidth)
 
       HStack(alignment: .top, spacing: spacing) {
         FixedYAxisLabelsView(domain: yDomain, ticks: yTicks, style: axisStyle)
           .frame(width: axisWidth, height: height)
 
         ScrollView(.horizontal, showsIndicators: false) {
           content()
             .frame(width: contentWidth, height: height)
             .padding(.trailing, 10)
         }
         .frame(width: plotWidth, height: height)
       }
       .frame(height: height)
     }
   }
 
   private var axisWidth: CGFloat {
     let longest = yTicks.map { $0.label.count }.max() ?? 4
     let estimated = CGFloat(longest) * 6.2 + 10
     switch axisStyle {
     case .compact:
       return min(max(estimated, 42), 52)
     case .regular:
       return min(max(estimated, 48), 60)
     }
   }
 
   private var spacing: CGFloat {
     switch axisStyle {
     case .compact: return 6
     case .regular: return 8
     }
   }
 }
private enum FixedYAxisStyle {
   case compact
   case regular
}
 
private struct YAxisTickItem: Identifiable {
   let value: Double
   let label: String
 
   var id: String { label + value.formatted(.number.precision(.fractionLength(2))) }
 }
 
private struct FixedYAxisLabelsView: View {
   let domain: ClosedRange<Double>
   let ticks: [YAxisTickItem]
   let style: FixedYAxisStyle
 
   var body: some View {
     GeometryReader { geometry in
       let plotHeight = max(geometry.size.height - topInset - bottomInset, 1)
 
       ZStack(alignment: .topTrailing) {
         Rectangle()
           .fill(Color.clear)
 
         ForEach(ticks) { tick in
           let ratio = normalizedRatio(for: tick.value)
           let rawY = topInset + (1 - ratio) * plotHeight
           let clampedY = min(max(rawY, labelHeight / 2), geometry.size.height - bottomInset)
 
           HStack(spacing: 4) {
             Text(tick.label)
               .font(.caption2)
               .foregroundStyle(.secondary)
               .lineLimit(1)
               .minimumScaleFactor(0.72)
 
             Rectangle()
               .fill(Color.secondary.opacity(0.25))
               .frame(width: stubWidth, height: 1)
           }
           .position(x: geometry.size.width / 2, y: clampedY)
         }
       }
     }
   }
 
   private var topInset: CGFloat {
     switch style {
     case .compact: return 14
     case .regular: return 16
     }
   }
 
   private var bottomInset: CGFloat {
     switch style {
     case .compact: return 22
     case .regular: return 24
     }
   }
 
   private var labelHeight: CGFloat {
     switch style {
     case .compact: return 14
     case .regular: return 16
     }
   }
 
   private var stubWidth: CGFloat {
     switch style {
     case .compact: return 3
     case .regular: return 4
     }
   }
 
   private func normalizedRatio(for value: Double) -> CGFloat {
     let lower = domain.lowerBound
     let upper = domain.upperBound
     guard upper > lower else { return 0.5 }
     return CGFloat((value - lower) / (upper - lower))
   }
 }
 
private struct LegendDisplayItem: Identifiable {
   let title: String
   let color: Color
 
   var id: String { title }
 }
 
private struct CompactLegendView: View {
   let items: [LegendDisplayItem]
 
   var body: some View {
     if !items.isEmpty {
       VStack(alignment: .leading, spacing: 6) {
         HStack(spacing: 12) {
           ForEach(firstRowItems) { item in
             legendItem(item)
           }
         }
 
         if !secondRowItems.isEmpty {
           HStack(spacing: 12) {
             ForEach(secondRowItems) { item in
               legendItem(item)
             }
           }
         }
       }
     }
   }
 
   private var firstRowItems: [LegendDisplayItem] {
     guard items.count > 4 else { return items }
     return Array(items.prefix((items.count + 1) / 2))
   }
 
   private var secondRowItems: [LegendDisplayItem] {
     guard items.count > 4 else { return [] }
     return Array(items.dropFirst((items.count + 1) / 2))
   }
 
   private func legendItem(_ item: LegendDisplayItem) -> some View {
     HStack(spacing: 6) {
       Circle()
         .fill(item.color)
         .frame(width: 8, height: 8)
 
       Text(item.title)
         .font(.caption)
         .foregroundStyle(.secondary)
         .lineLimit(1)
     }
   }
 }
 
private struct DistributionSegment {
   let item: DistributionPoint
   let startAngle: Angle
   let endAngle: Angle
}
 
private struct RawCallout {
   let item: DistributionPoint
   let start: CGPoint
   let mid: CGPoint
   let preferredY: CGFloat
   let isRightSide: Bool
}
 
private struct DonutCalloutLayout: Identifiable {
   let item: DistributionPoint
   let start: CGPoint
   let mid: CGPoint
   let end: CGPoint
   let labelCenter: CGPoint
   let isRightSide: Bool
 
   var id: String { item.id }
}
 
private struct DonutSliceShape: Shape {
   let startAngle: Angle
   let endAngle: Angle
   let innerRadiusRatio: CGFloat
 
   func path(in rect: CGRect) -> Path {
     let center = CGPoint(x: rect.midX, y: rect.midY)
     let radius = min(rect.width, rect.height) / 2
     let innerRadius = radius * innerRadiusRatio
 
     var path = Path()
     path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
     path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
     path.closeSubpath()
     return path
   }
 }
 
private extension Double {
   var cnyShortText: String {
     let sign = self < 0 ? "-" : ""
     let value = abs(self)
     if value >= 1_000_000 {
       return sign + String(format: "¥%.1fM", value / 1_000_000)
     }
     if value >= 1_000 {
       return sign + String(format: "¥%.1fk", value / 1_000)
     }
     return sign + String(format: "¥%.0f", value)
   }
 
   var cnyAxisText: String {
     let sign = self < 0 ? "-" : ""
     let value = abs(self)
     if value >= 1_000_000 {
       return sign + String(format: "¥%.1fM", value / 1_000_000)
     }
     if value >= 1000 {
       return sign + String(format: "¥%.1fk", value / 1000)
     }
     return sign + String(format: "¥%.0f", value)
   }
 }
 
private extension DistributionPoint {
   var displayColor: Color {
     if let color {
       return Color(hex: color)
     }
     return .accentColor
   }
 }
 
 
private enum OverviewPreset: String, CaseIterable, Identifiable {
   case week
   case month
   case year
 
   var id: String { rawValue }
 
   var title: String {
     switch self {
     case .week: return "本周"
     case .month: return "本月"
     case .year: return "本年"
     }
   }
 
   var dateRangePreset: DateRangePreset {
     switch self {
     case .week: return .currentWeek
     case .month: return .currentMonth
     case .year: return .currentYear
     }
   }
 
   var defaultGranularity: Granularity {
     switch self {
     case .week: return .day
     case .month: return .week
     case .year: return .month
     }
   }
 }
 
 private struct DashboardRangePickerSheet: View {
   @EnvironmentObject private var settings: AppSettings
   @EnvironmentObject private var store: LedgerStore
   @Environment(\.dismiss) private var dismiss
@Binding var selectedPreset: OverviewPreset
let onSelectPreset: (OverviewPreset) -> Void
let onSelectPinnedRange: (CustomDateRange) -> Void

@State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
@State private var customEndDate: Date = Date()
@State private var pinTitle: String = ""
@State private var showPinComposer = false

var body: some View {
    NavigationStack {
        Form {
            Section("常用范围") {
                ForEach(OverviewPreset.allCases) { item in
                    Button {
                        onSelectPreset(item)
                        dismiss()
                    } label: {
                        HStack {
                            Text(item.title)
                            Spacer()
                            if store.activeRangePreset == item.dateRangePreset {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if !settings.pinnedDashboardRanges.isEmpty {
                Section("已置顶时间范围") {
                    ForEach(settings.pinnedDashboardRanges) { item in
                        Button {
                            onSelectPinnedRange(item.range)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if item.range == store.activeCustomRange {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Text(rangeText(item.range))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                settings.removePinnedDashboardRange(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("自定义范围") {
                DatePicker("开始", selection: $customStartDate, displayedComponents: .date)
                DatePicker("结束", selection: $customEndDate, in: customStartDate..., displayedComponents: .date)
                
                Button {
                    onSelectPinnedRange(currentCustomRange)
                    dismiss()
                } label: {
                    HStack {
                        Text("应用这个范围")
                        Spacer()
                        Text(rangeText(currentCustomRange))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if showPinComposer {
                    TextField("置顶名称", text: $pinTitle)
                    Button {
                        settings.addPinnedDashboardRange(title: pinTitle, range: currentCustomRange)
                        pinTitle = ""
                        showPinComposer = false
                    } label: {
                        Label("保存到置顶时间范围", systemImage: "pin.fill")
                    }
                } else {
                    Button {
                        pinTitle = defaultTitle(for: currentCustomRange)
                        showPinComposer = true
                    } label: {
                        Label("置顶这个时间范围", systemImage: "pin")
                    }
                }
            }
        }
        .navigationTitle("时间范围")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .onAppear {
            customStartDate = store.activeCustomRange.start
            customEndDate = store.activeCustomRange.end
        }
    }
}

private var currentCustomRange: CustomDateRange {
    CustomDateRange(start: customStartDate, end: customEndDate)
}

private func defaultTitle(for range: CustomDateRange) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy‑MM‑dd"
    return "\(formatter.string(from: range.start)) ~ \(formatter.string(from: range.end))"
}

private func rangeText(_ range: CustomDateRange) -> String {
    defaultTitle(for: range)
}

}

private struct FinanceCalendarSheet: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var displayedMonth: Date = Self.startOfMonth(Date())
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var monthTransactions: [LedgerTransaction] = []
    @State private var dailySummaries: [Date: DailyFinanceSummary] = [:]
    @State private var isLoading = false
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthNavigator
                    weekdayHeader
                    calendarGrid
                    selectedDaySummary
                    selectedTransactions
                }
                .padding()
            }
            .navigationTitle("收支日历")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("今天") {
                        updateMonth(Date())
                    }
                }
            }
            .task {
                await loadMonth()
            }
            .onChange(of: displayedMonth) { _, _ in
                Task { await loadMonth() }
            }
        }
    }
    
    private var monthNavigator: some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }
            
            Spacer()
            
            VStack(spacing: 6) {
                Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.headline)
                
                DatePicker(
                    "跳转月份",
                    selection: Binding(
                        get: { displayedMonth },
                        set: { newValue in updateMonth(newValue) }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }
            
            Spacer()
            
            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(monthCells) { cell in
                if let date = cell.date {
                    dayCell(date)
                } else {
                    Color.clear
                        .frame(height: 74)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -40 {
                        moveMonth(by: 1)
                    } else if value.translation.width > 40 {
                        moveMonth(by: -1)
                    }
                }
        )
    }
    
    private func dayCell(_ date: Date) -> some View {
        let day = calendar.component(.day, from: date)
        let summary = dailySummaries[calendar.startOfDay(for: date)]
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        
        return Button {
            selectedDate = calendar.startOfDay(for: date)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(day)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                Spacer(minLength: 0)
                if let summary {
                    VStack(alignment: .leading, spacing: 2) {
                        if summary.income > 0 {
                            Text("+\(summary.income.compactMoney)")
                                .font(.caption2)
                                .foregroundStyle(isSelected ? .white : .green)
                        }
                        if summary.expense > 0 {
                            Text("‑\(summary.expense.compactMoney)")
                                .font(.caption2)
                                .foregroundStyle(isSelected ? .white : .orange)
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background(cellBackground(summary: summary, isSelected: isSelected))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func cellBackground(summary: DailyFinanceSummary?, isSelected: Bool) -> some View {
        let maxIntensity = max((dailySummaries.values.map(\.intensity).max()) ?? 1, 1)
        
        if isSelected {
            return AnyView(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.blue)
            )
        }
        
        guard let summary else {
            return AnyView(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        
        let ratio = min(summary.intensity / maxIntensity, 1)
        let baseColor: Color = summary.expense >= summary.income ? .orange : .green
        
        return AnyView(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(baseColor.opacity(0.10 + ratio * 0.24))
        )
    }
    
    private var selectedDaySummary: some View {
        let summary = dailySummaries[selectedDate] ?? DailyFinanceSummary(income: 0, expense: 0)
        
        return SectionCard(
            title: selectedDate.formatted(date: .complete, time: .omitted),
            subtitle: "查看当天收入、支出和结余"
        ) {
            HStack(spacing: 12) {
                dayMetric(title: "收入", value: summary.income.cnyText, tint: .green)
                dayMetric(title: "支出", value: summary.expense.cnyText, tint: .orange)
                dayMetric(title: "结余", value: summary.balance.cnyText, tint: summary.balance >= 0 ? .blue : .red)
            }
        }
    }
    
    private func dayMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    private var selectedTransactions: some View {
        SectionCard(title: "当天流水", subtitle: "点按日期查看当天记录") {
            if selectedDayTransactions.isEmpty {
                ContentUnavailableView("当天暂无流水", systemImage: "tray")
            } else {
                VStack(spacing: 10) {
                    ForEach(selectedDayTransactions) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tx.title)
                                    .font(.subheadline.weight(.medium))
                                Text(tx.categoryName ?? "未分类")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((tx.kind == .expense ? -tx.amount : tx.amount).cnyText)
                                .foregroundStyle(tx.kind == .income ? .green : .primary)
                        }
                        .padding(12)
                        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }
    
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
    
    private var monthCells: [CalendarCell] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let monthStart = interval.start
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        
        var cells: [CalendarCell] = Array(repeating: CalendarCell(date: nil), count: leading)
        for day in 0..<dayCount {
            if let date = calendar.date(byAdding: .day, value: day, to: monthStart) {
                cells.append(CalendarCell(date: date))
            }
        }
        return cells
    }
    
    private var selectedDayTransactions: [LedgerTransaction] {
        monthTransactions.filter { calendar.isDate($0.happenedAt, inSameDayAs: selectedDate) }
            .sorted { $0.happenedAt > $1.happenedAt }
    }
    
    private func moveMonth(by offset: Int) {
        let newValue = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
        updateMonth(newValue)
    }
    
    private func updateMonth(_ newValue: Date) {
        displayedMonth = Self.startOfMonth(newValue)
        let today = calendar.startOfDay(for: Date())
        if calendar.isDate(today, equalTo: displayedMonth, toGranularity: .month) {
            selectedDate = today
        } else {
            selectedDate = displayedMonth
        }
    }
    
    private func loadMonth() async {
        isLoading = true
        defer { isLoading = false }
        
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return }
        let window = DateWindow(start: interval.start, end: interval.end)
        
        do {
            let transactions = try await store.loadTransactions(in: window)
            monthTransactions = transactions
            dailySummaries = store.dailySummaries(for: displayedMonth, from: transactions)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
    
    private static func startOfMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
    
    private struct CalendarCell: Identifiable {
        let id = UUID()
        let date: Date?
    }
}

private extension Double {
    var compactMoney: String {
        if self >= 10000 {
            return String(format: "%.1fw", self / 10000)
        }
        if self >= 1000 {
            return String(format: "%.1fk", self / 1000)
        }
        return String(format: "%.0f", self)
    }
}


struct BudgetStatusCard: View {
    let item: BudgetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.name)
                    .font(.headline)
                Spacer()
                Text("\(item.spentAmount.cnyText) / \(item.limitAmount.cnyText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(item.usageRatio, 0), 1))
            HStack {
                Text(item.categoryName ?? "全部消费")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("已用 \((item.usageRatio * 100).formatted(.number.precision(.fractionLength(0))))%")
                    .font(.caption)
                    .foregroundStyle(item.usageRatio >= 1 ? .red : .secondary)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16, strokeOpacity: 0.22)
    }
}
