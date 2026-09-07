//  BudgetsView.swift
//  SmartLedger
//
//  m09_add_02 — 预算模块（图283-289）
//  迁移自 m09_01 BooksAndMoreViews.swift 中删除的 BudgetsView / BudgetEditor。
//
//  ⚠️ 函数体一律 "// 以原图为准"；具体布局细节以截图为准。

import SwiftUI

// MARK: - BudgetsView（图283-284）

struct BudgetsView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var showingCreate = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                budgetStatCard              // 图284
                budgetCardsSection          // 图284
                usageSummary                // 图284
            }
            .padding()
        }
        .navigationTitle("预算")            // 图283
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCreate = true } label: {   // 图283
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreate) {              // 图283
            CreateBudgetView()
        }
    }

    // MARK: - 统计卡片（图284）
    private var budgetStatCard: some View {
        // 以原图为准：HStack + VStack + Text("总预算"/"月预算") + .glassCard
        EmptyView()
    }

    // MARK: - 预算卡片列表（图284）
    private var budgetCardsSection: some View {
        // 以原图为准：ForEach(store.budgets) { BudgetStatusCard(budget:) }
        EmptyView()
    }

    // MARK: - 汇总（图284）
    private var usageSummary: some View {
        // 以原图为准：totalRemaining / 各类预算进度
        EmptyView()
    }

    // MARK: - 计算属性（图284）
    private var totalRemaining: Decimal { 0 }   // 以原图为准
}

// MARK: - BudgetStatusCard（图285-286）

struct BudgetStatusCard: View {
    let budget: Budget

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(budget.name)
                Spacer()
                Text(periodText)                // 图286
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)       // 图285
            HStack {
                Text(remainingText)            // 图286 "remaining"
                    .foregroundStyle(progressColor)   // 图286
                Spacer()
                Text(totalText)
            }
            .font(.footnote)
        }
        .padding()
        .glassCard()                            // 图285
    }

    // MARK: - 辅助（图286）
    private var remaining: Decimal { 0 }        // 以原图为准
    private var progress: Double { 0 }          // 以原图为准

    private var progressColor: Color {          // 图286
        // 以原图为准：根据 progress 返回 .green / .orange / .red
        .primary
    }

    private var periodText: String {            // 图286
        // 以原图为准：Date 格式化 → "yyyy.MM.dd – ..."
        ""
    }

    private var remainingText: String { "" }    // 以原图为准
    private var totalText: String { "" }        // 以原图为准
}

// MARK: - CreateBudgetView（图287-289）

struct CreateBudgetView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var amount = ""
    @State private var mode: BudgetMode = .monthly
    @State private var categoryID: CategoryID?
    @State private var startDate = Date()
    @State private var endDate: Date?
    @State private var unlimited = false        // monthlyUnlimited 相关（图288）

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {           // 图287
                    TextField("名称", text: $name)
                    TextField("金额", text: $amount)
                        .keyboardType(.decimalPad)
                }
                Section("预算模式") {           // 图287
                    Picker("模式", selection: $mode) {
                        ForEach(BudgetMode.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    Toggle("不限期", isOn: $unlimited)   // 图288 monthlyUnlimited
                }
                Section("分类") {               // 图287
                    Picker("分类", selection: $categoryID) {
                        Text("不限").tag(CategoryID?.none)
                        ForEach(store.categories) { cat in
                            Text(cat.name).tag(CategoryID?.some(cat.id))
                        }
                    }
                }
                Section("起止时间") {           // 图288 "起止时间"
                    DatePicker("开始", selection: $startDate, displayedComponents: .date)
                    if !unlimited {
                        DatePicker("结束", selection: Binding(   // 图288
                            get: { endDate ?? Date() },
                            set: { endDate = $0 }
                        ), displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("新建预算")        // 图287
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }     // 图287
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { createBudget() }   // 图287, 289
                        .disabled(name.isEmpty || amount.isEmpty)
                }
            }
        }
    }

    // MARK: - 动作（图289）
    private func createBudget() {
        // 以原图为准：
        // Task {
        //     await store.createBudget(...)
        //     dismiss()
        // }
    }

    // MARK: - 计算属性（图289）
    private var categoryName: String {          // 以原图为准
        store.categories.first { $0.id == categoryID }?.name ?? "不限"
    }
}

// MARK: - BudgetMode（图288-289）

enum BudgetMode: CaseIterable, Identifiable {   // 图288 "BudgetMode 枚举"
    case monthly
    case range
    case monthlyUnlimited                        // 图288, 289

    var id: Self { self }

    var title: String {                         // 图289 返回 "按月"/"起止时间"...
        switch self {
        case .monthly:          return "按月"     // 图288
        case .range:            return "起止时间" // 图288, 289
        case .monthlyUnlimited: return "按月（不限期）"  // 图289
        }
    }
}

// MARK: - Preview（补充，可删除）

#if DEBUG
struct BudgetsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BudgetsView()
                .environmentObject(LedgerStore.preview)
        }
    }
}
#endif
