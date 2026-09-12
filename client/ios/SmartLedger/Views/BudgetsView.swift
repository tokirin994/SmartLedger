import SwiftUI

struct BudgetView: View {
  @EnvironmentObject private var store: LedgerStore
  @State private var showCreateSheet = false

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        budgetSummary
        budgetCardsSection
      }
      .padding()
    }
    .navigationTitle("预算")

.toolbar {
     ToolbarItem(placement: .topBarTrailing) {
       Button {
         showCreateSheet = true
       } label: {
         Image(systemName: "plus")
       }
     }
   }
   .sheet(isPresented: $showCreateSheet) {
     CreateBudgetView()
       .environmentObject(store)
   }
   .task {
     if store.overview == nil {
       await store.bootstrapIfNeeded()
     }
   }
   .refreshable {
     await store.refreshDashboard(range: store.activeRangePreset, granularity: store.activeGranularity)
   }
 }

 private var budgetSummary: some View {
   HStack(spacing: 32) {
     budgetStatCard(title: "预算数", value: "\(store.budgets.count)", subtitle: "已创建预算", color: .blue)
     budgetStatCard(title: "剩余额度", value: totalRemaining.cnText, subtitle: usageSummary, color: totalRemaining >= 0 ? .green : .red)
   }
 }

 private func budgetStatCard(title: String, value: String, subtitle: String, color: Color) -> some View {
   VStack(alignment: .leading, spacing: 8) {
     Text(title)
       .font(.caption)
       .foregroundStyle(.secondary)
     Text(value)
       .font(.headline.weight(.bold))
       .foregroundStyle(color)
     Text(subtitle)
       .font(.caption)
       .foregroundStyle(.secondary)
   }
   .frame(maxWidth: .infinity, alignment: .leading)
   .padding(.vertical, 6)
   .glassCard(cornerRadius: 20, strokeOpacity: 0.22)
 }

 @ViewBuilder
 private var budgetCardsSection: some View {
   if store.budgets.isEmpty {
     ContentUnavailableView("暂无预算", systemImage: "wallet.pass")
   } else {
     VStack(spacing: 14) {
       ForEach(store.budgets) { item in
         BudgetStatCard(item: item)
       }
     }
   }
 }

 private var totalRemaining: Double {
   store.budgets.reduce(0) { $0 + max($1.limitAmount - $1.spentAmount, 0) }
 }

 private var usageSummary: String {
   let totalLimit = store.budgets.reduce(0.0) { $0 + $1.limitAmount }
   let totalSpent = store.budgets.reduce(0.0) { $0 + $1.spentAmount }
   guard totalLimit > 0 else { return "等待创建预算" }
   return "已用 \((totalSpent / totalLimit * 100).formatted(.number.precision(.fractionLength(1))))%"
 }
}

struct BudgetStatCard: View {
 var item: BudgetItem

 var body: some View {
   VStack(alignment: .leading, spacing: 12) {
     HStack(alignment: .top) {
       VStack(alignment: .leading, spacing: 4) {
         Text(item.name)
           .font(.headline)
         Text(item.categoryName ?? "总预算")
           .font(.caption)
           .foregroundStyle(.secondary)
       }

       Spacer()

       Text(item.periodType == "range" ? "自定义预算" : "月度预算")
         .font(.caption.weight(.semibold))
         .padding(.horizontal, 10)
         .padding(.vertical, 6)
         .background(Color.blue.opacity(0.08), in: Capsule())
     }

     HStack(spacing: 12) {
       metric(title: "预算金额", value: item.limitAmount.cnText, tint: .blue)
       metric(title: "已用金额", value: item.spentAmount.cnText, tint: .orange)
       metric(title: "剩余额度", value: remaining.cnText, tint: remaining >= 0 ? .green : .red)
     }

     ProgressView(value: min(item.usageRatio, 1.0))
       .tint(progressColor)

     HStack {
       Label("已用 \((item.usageRatio * 100).formatted(.number.precision(.fractionLength(1))))%", systemImage: "chart.pie.fill")
         .font(.caption)
         .foregroundStyle(.secondary)

       Spacer()

       Text(periodText)
         .font(.caption)
         .foregroundStyle(.secondary)
     }
   }
   .padding(16)
   .glassCard(cornerRadius: 20, strokeOpacity: 0.20)
 }

 private func metric(title: String, value: String, tint: Color) -> some View {
   VStack(alignment: .leading, spacing: 4) {
     Text(title)
       .font(.caption)
       .foregroundStyle(.secondary)
     Text(value)
       .font(.subheadline.weight(.bold))
       .foregroundStyle(tint)
   }
   .frame(maxWidth: .infinity, alignment: .leading)
 }

 private var remaining: Double {
   item.limitAmount - item.spentAmount
 }

 private var progressColor: Color {
   if item.usageRatio >= 1 { return .red }
   if item.usageRatio >= 0.85 { return .orange }
   return .blue
 }

 private var periodText: String {
   if item.periodType == "range" {
     let startText = item.startDate?.formatted(date: .abbreviated, time: .omitted) ?? "-"
     let endText = item.endDate?.formatted(date: .abbreviated, time: .omitted) ?? "无截止"
     return "\(startText) ~ \(endText)"
   }
   if let month = item.month {
     return "\(item.year)年\(month)月"
   }
   return "长期按月"
 }
}

private struct CreateBudgetView: View {
 @EnvironmentObject private var store: LedgerStore
 @Environment(\.dismiss) private var dismiss

 @State private var name = ""
 @State private var amount = ""
 @State private var budgetMode: BudgetMode = .monthlyUnlimited
 @State private var categoryId: Int?
 @State private var targetMonth = Date()
 @State private var startDate = Date()
 @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
 @State private var hasEndDate = false

 var body: some View {
   NavigationStack {
     Form {
       Section("基础信息") {
         TextField("预算名称", text: $name)
         TextField("金额", text: $amount)
           .keyboardType(.decimalPad)
       }

       Section("预算模式") {
         Picker("模式", selection: $budgetMode) {
           ForEach(BudgetMode.allCases) { mode in
             Text(mode.title).tag(mode)
           }
         }
         .pickerStyle(.segmented)

         DatePicker(budgetMode == .monthlyUnlimited ? "开始月份" : "开始时间", selection: $startDate, displayedComponents: .date)
         Toggle("设置结束时间", isOn: $hasEndDate)
         if hasEndDate {
           DatePicker("结束时间", selection: $endDate, in: startDate..., displayedComponents: .date)
         }
         if budgetMode == .monthlyUnlimited {
           Text("系统会把这条预算作为按月滚动模板，仅展示当前月；到下月自动按相同额度进入下一周期。")
             .font(.footnote).foregroundStyle(.secondary)
         }
       }

       Section("分类") {
         Picker("分类 (可选)", selection: $categoryId) {
           Text("总预算").tag(nil as Int?)
           ForEach(topLevelExpenseCategories) { category in
             Text(category.name).tag(Int?(category.id))
           }
         }
       }
     }
     .navigationTitle("新建预算")
     .toolbar {
       ToolbarItem(placement: .topBarLeading) {
         Button("取消") { dismiss() }
       }
       ToolbarItem(placement: .topBarTrailing) {
         Button("保存") {
           createBudget()
         }
         .disabled(Double(amount) == nil)
       }
     }
   }
 }

 private var topLevelExpenseCategories: [LedgerCategory] {
   store.flattenedCategories.filter { $0.level == 1 && $0.flowType == .expense }
 }

 private var categoryName: String? {
   store.flattenedCategories.first(where: { $0.id == categoryId })?.name
 }

 private func createBudget() {
   guard let limit = Double(amount) else { return }
   let monthComponents = Calendar.current.dateComponents([.year, .month], from: targetMonth)
   let draft = BudgetDraft(
     name: name.isEmpty ? "新增预算" : name,
     limitAmount: limit,
     periodType: budgetMode.periodType,
     year: monthComponents.year ?? Calendar.current.component(.year, from: Date()),
     month: nil,
     startDate: startDate,
     endDate: hasEndDate ? endDate : nil,
     categoryId: categoryId
   )

   Task {
     await store.createBudget(draft)
     dismiss()
   }
 }
}

enum BudgetMode: String, CaseIterable, Identifiable {
 case monthlyUnlimited
 case range

 var id: String { rawValue }

 var title: String {
   switch self {
   case .monthlyUnlimited: return "按月"
   case .range: return "起止时间"
   }
 }

 var periodType: String {
   switch self {
   case .monthlyUnlimited: return "monthly"
   case .range: return "range"
   }
 }
}
