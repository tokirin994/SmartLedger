import SwiftUI

private enum BudgetEditorSheet: Identifiable {
  case create
  case edit(BudgetItem)
  case child(BudgetItem)

  var id: String {
    switch self {
    case .create: return "create"
    case .edit(let item): return "edit-\(item.id)"
    case .child(let item): return "child-\(item.id)"
    }
  }
}

struct BudgetView: View {
  @EnvironmentObject private var store: LedgerStore
  @State private var activeSheet: BudgetEditorSheet?
  @State private var deletingBudget: BudgetItem?

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        budgetSummary
        budgetCardsSection
      }
      .padding()
    }
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle("预算")
    .dismissKeyboardWhenTappedOutside()

.toolbar {
     ToolbarItem(placement: .topBarTrailing) {
       Button {
         activeSheet = .create
       } label: {
         Image(systemName: "plus")
       }
     }
   }
   .sheet(item: $activeSheet) { sheet in
     switch sheet {
     case .create:
       CreateBudgetView().environmentObject(store)
     case .edit(let item):
       CreateBudgetView(existingBudget: item, parentBudget: parentBudget(for: item)).environmentObject(store)
     case .child(let parent):
       CreateBudgetView(parentBudget: parent).environmentObject(store)
     }
   }
   .confirmationDialog("删除预算规则？", isPresented: Binding(get: { deletingBudget != nil }, set: { if !$0 { deletingBudget = nil } }), titleVisibility: .visible) {
     Button("删除规则及子预算", role: .destructive) {
       if let item = deletingBudget { Task { await store.deleteBudget(id: item.id) } }
     }
   } message: {
     Text("删除“\(deletingBudget?.name ?? "预算")”会同时删除其下的子预算规则。历史流水不会受影响。")
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

 private func parentBudget(for item: BudgetItem) -> BudgetItem? {
   guard let parentId = item.parentBudgetId else { return nil }
   return store.budgets.first { $0.id == parentId }
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
   .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
   .padding(.horizontal, 14)
   .padding(.vertical, 12)
   .glassCard(cornerRadius: 20, strokeOpacity: 0.22)
 }

 @ViewBuilder
 private var budgetCardsSection: some View {
   if store.budgets.isEmpty {
     ContentUnavailableView("暂无预算", systemImage: "wallet.pass")
   } else {
     VStack(spacing: 14) {
       ForEach(store.budgets.filter { $0.parentBudgetId == nil }) { item in
         budgetRuleCard(item)
         ForEach(store.budgets.filter { $0.parentBudgetId == item.id }) { child in
           budgetRuleCard(child, isChild: true)
         }
       }
     }
   }
 }

 @ViewBuilder
 private func budgetRuleCard(_ item: BudgetItem, isChild: Bool = false) -> some View {
   VStack(alignment: .trailing, spacing: 6) {
     HStack {
       if isChild { Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary) }
       BudgetStatCard(item: item)
       Menu {
         Button("编辑规则", systemImage: "pencil") { activeSheet = .edit(item) }
         if !isChild {
           Button("添加子预算", systemImage: "plus") { activeSheet = .child(item) }
         }
         Button("删除", systemImage: "trash", role: .destructive) { deletingBudget = item }
       } label: {
         Image(systemName: "ellipsis.circle.fill")
           .font(.title3)
           .foregroundStyle(.secondary)
           .padding(.leading, 4)
       }
     }
     .padding(.leading, isChild ? 18 : 0)
   }
 }

 private var totalRemaining: Double {
   store.budgets.filter { $0.parentBudgetId == nil }.reduce(0) { $0 + max($1.limitAmount - $1.spentAmount, 0) }
 }

 private var usageSummary: String {
   let roots = store.budgets.filter { $0.parentBudgetId == nil }
   let totalLimit = roots.reduce(0.0) { $0 + $1.limitAmount }
   let totalSpent = roots.reduce(0.0) { $0 + $1.spentAmount }
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
         Text(item.categoryName ?? (item.keyword.map { "关键词：\($0)" } ?? (item.parentBudgetId == nil ? "总预算" : "继承主预算范围")))
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
   .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
   .padding(10)
   .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
 private let existingBudget: BudgetItem?
 private let parentBudget: BudgetItem?

 @State private var name: String
 @State private var amount: String
 @State private var budgetMode: BudgetMode
 @State private var categoryId: Int?
 @State private var selectedCategoryIds: Set<Int>
 @State private var keyword: String
 @State private var startDate: Date
 @State private var endDate: Date
 @State private var hasEndDate: Bool

 init(existingBudget: BudgetItem? = nil, parentBudget: BudgetItem? = nil) {
   self.existingBudget = existingBudget
   self.parentBudget = parentBudget
   _name = State(initialValue: existingBudget?.name ?? "")
   _amount = State(initialValue: existingBudget.map { String($0.limitAmount) } ?? "")
   _budgetMode = State(initialValue: (existingBudget?.periodType ?? parentBudget?.periodType) == "range" ? .range : .monthlyUnlimited)
   _categoryId = State(initialValue: existingBudget?.categoryId)
   _selectedCategoryIds = State(initialValue: Set(existingBudget?.categoryIds ?? []))
   _keyword = State(initialValue: existingBudget?.keyword ?? "")
   _startDate = State(initialValue: existingBudget?.startDate ?? parentBudget?.startDate ?? Date())
   _endDate = State(initialValue: existingBudget?.endDate ?? parentBudget?.endDate ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
   _hasEndDate = State(initialValue: existingBudget?.endDate != nil || parentBudget?.endDate != nil)
 }

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
           Text("按月规则会自动生成月度统计；年度视图会展开为各月预算进度。")
             .font(.footnote).foregroundStyle(.secondary)
         }
       }

        if let parentBudget {
          Section("子预算范围") {
            Text("归属主预算：\(parentBudget.name)")
              .foregroundStyle(.secondary)
            Text("选择一个或多个分类；每个分类会包含其下级分类。子预算只用于细分跟踪，不重复计入总预算剩余额度。")
              .font(.footnote).foregroundStyle(.secondary)
            TextField("可选：标题/商户/备注关键词", text: $keyword)
            Text("填写关键词后，只统计标题、商户、备注或支付渠道中包含该词的流水；分类与关键词可组合。")
              .font(.footnote).foregroundStyle(.secondary)
            ForEach(store.flattenedCategories.filter { $0.flowType == .expense }) { category in
              Button {
                if selectedCategoryIds.contains(category.id) { selectedCategoryIds.remove(category.id) }
                else { selectedCategoryIds.insert(category.id) }
              } label: {
                HStack(spacing: 10) {
                  Text(String(repeating: "　", count: max(category.level - 1, 0)))
                  Text(category.name)
                  Spacer()
                  if selectedCategoryIds.contains(category.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
            if selectedCategoryIds.isEmpty {
              Text("未选择分类时，该子预算按主预算范围全部支出计算。")
                .font(.footnote).foregroundStyle(.orange)
            }
          }
        } else {
         Section("分类") {
          HierarchicalCategoryPicker(
            title: "预算分类",
            categories: store.categories.filter { $0.flowType == .expense },
            placeholder: "总预算",
            helperText: "不选择分类时按全部支出计算。",
            selectedCategoryId: $categoryId,
            flowType: .expense,
            onCreateCategory: nil
          )
         }
        }
     }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(existingBudget == nil ? (parentBudget == nil ? "新建预算" : "添加子预算") : "编辑预算规则")
      .dismissKeyboardWhenTappedOutside()
      .task { if store.categories.isEmpty { await store.loadCategories() } }
      .toolbar {
       ToolbarItem(placement: .topBarLeading) {
         Button("取消") { dismiss() }
       }
       ToolbarItem(placement: .topBarTrailing) {
         Button("保存") {
           saveBudget()
         }
         .disabled(Double(amount) == nil)
       }
     }
   }
 }

 private func saveBudget() {
   guard let limit = Double(amount) else { return }
   let monthComponents = Calendar.current.dateComponents([.year, .month], from: startDate)
   let normalizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
   let draft = BudgetDraft(
     name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新增预算" : name.trimmingCharacters(in: .whitespacesAndNewlines),
     limitAmount: limit,
     periodType: existingBudget?.periodType ?? parentBudget?.periodType ?? budgetMode.periodType,
     year: monthComponents.year ?? Calendar.current.component(.year, from: Date()),
     month: nil,
     startDate: startDate,
     endDate: hasEndDate ? endDate : nil,
     categoryId: parentBudget == nil ? categoryId : nil,
     parentBudgetId: parentBudget?.id,
     categoryIds: parentBudget == nil ? nil : Array(selectedCategoryIds).sorted(),
     keyword: parentBudget == nil || normalizedKeyword.isEmpty ? nil : normalizedKeyword
   )

   Task {
     if let existingBudget {
       await store.updateBudget(id: existingBudget.id, draft: draft)
     } else {
       await store.createBudget(draft)
     }
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
/* Removed invalid pre-existing trailing fragment. */

/*
ange: return "range"
   }
 }
}

}
*/
/*
 }
}

}
*/
