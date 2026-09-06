# 远端 GitHub 仓库对齐本地修改清单

> 本文档用于对比远端 GitHub 仓库与本地修改的差异，列出对齐步骤与必须改动的点。

---

## 1. 基本信息

- **远端 GitHub 仓库地址**：`https://github.com/xxx/SmartLedgerLocal.git`
- **本地路径**：`/Users/tok/c/SmartLedgerLocal/client/ios`
- **提交哈希**：`+985 -0`（本次差异）

---

## 1.3 结论先说

**原因说明**：本地 iOS 目录结构已经按照规格书进行了重构，远端仓库仍然是旧结构，需要对齐。

### 本地 iOS 目录结构

```
client/ios/SmartLedger/
├── Components/
├── Core/
├── Models/
└── ...
```

---

## 2. 目录结构对比

### 2.1 远端与本地 Swift 项目目录结构对比

远端仓库文件列表：

- `README.md`
- `SmartLedgerLocal`
- 多个 `.swift` 文件

本地完整结构：

```
client/ios/
├── SmartLedgerLocal.xcodeproj
├── SmartLedger/
│   ├── Components/
│   │   ├── GlassCard.swift
│   │   ├── MetricCard.swift
│   │   ├── FilterChip.swift
│   │   ├── CategoryPicker.swift
│   │   ├── BookPicker.swift
│   │   ├── PaymentMethodPicker.swift
│   │   ├── PieChartView.swift
│   │   ├── BarChartView.swift
│   │   ├── TrendChartView.swift
│   │   ├── TransactionRow.swift
│   │   ├── SplitSettingView.swift
│   │   └── InstallmentSettingView.swift
│   ├── Core/
│   │   ├── AppSettings.swift
│   │   ├── LedgerStore.swift
│   │   └── CloudSyncService.swift
│   ├── Models/
│   │   ├── LedgerModels.swift
│   │   └── SyncModels.swift
│   ├── Services/
│   │   ├── OCRService.swift
│   │   └── ReceiptParser.swift
│   ├── Views/
│   │   ├── DashboardView.swift
│   │   ├── FinanceCalendarSheet.swift
│   │   ├── TransactionsView.swift
│   │   ├── CreateTransactionView.swift
│   │   ├── CategoriesView.swift
│   │   ├── BooksView.swift
│   │   ├── BookDetailView.swift
│   │   ├── BudgetsView.swift
│   │   ├── OCRImportView.swift
│   │   ├── SettingsView.swift
│   │   └── AppleSignInView.swift
│   └── SmartLedgerLocalApp.swift
└── docs/
    ├── AI复现版完整规格书.md
    └── 远端GitHub仓库对齐本地修改清单.md
```

---

## 3. 结构差异结论

### 3.1 远端缺失

以下目录/文件在远端仓库中不存在，需要新增：

- `client/ios/SmartLedger/Components/` 整个目录
- `client/ios/SmartLedger/Core/` 整个目录
- `client/ios/SmartLedger/Models/` 整个目录
- `client/ios/SmartLedger/Services/` 整个目录
- `client/ios/SmartLedger/Views/` 整个目录
- `client/ios/docs/` 整个目录

### 3.2 远端保留但需要重构

- `SmartLedgerLocal`（旧的主目录名，需改为 `SmartLedger`）
- 多个散落在根目录的 `.swift` 文件需要按职责拆分到对应子目录

### 3.3 差异摘要

| 类型 | 说明 |
|------|------|
| 结构差异 | 远端为扁平结构，本地为分层结构 |
| Xcode 工程 | 远端使用旧工程名，需更新 |
| OCR | 本地已实现完整 OCR 模块，远端缺失 |
| Dashboard | 本地按规格书重写了图表系统 |

---

## 4. 对齐操作步骤

### Step 1：保留远端必要文件

- `README.md`
- `.git`
- `client/ios/`
- `docs/`（如有）

### Step 2：同步本地修改到远端

将本地以下目录完整覆盖到远端对应位置：

- `SmartLedgerLocal/` → `client/ios/SmartLedger/`
- `docs/` → `client/ios/docs/`

### Step 3：更新 Xcode 工程文件

- 工程名从 `SmartLedgerLocal` 改为 `SmartLedger`
- 重新组织文件引用到对应 Group

### Step 4：提交推送

```bash
git add .
git commit -m "refactor: 按规格书重组 iOS 项目结构"
git push origin main
```

---

## 5. 数据模型补齐

### 5.1 分类模型（LedgerModels.swift）

必须补齐的字段：

- `id`
- `name`
- `flowType`
- `icon`
- `color`
- `parentId`
- `level`
- `children: [Category]`

### 5.2 流水模型（LedgerModels.swift）

必须补齐的字段：

#### 基础字段

- `kind`
- `amount`
- `title`
- `happenedAt`
- `note`
- `paymentMethod`
- `source`
- `currency`

#### 分类字段

- `categoryId`
- `categoryName`

#### 账本归属字段

- `bookId`
- `bookIds: [Int]`
- `bookName`
- `bookNames: [String]`

#### 分期字段

- `installmentGroupId`
- `installmentIndex`
- `installmentMonths`
- `installmentOriginalTotal`

#### 原价/优惠/溢价字段

- `originalAmount`
- `discountAmount`
- `premiumAmount`

#### 多人分账字段

- `paidByParticipantId`
- `paidByParticipantName`
- `splitParticipantIds`
- `splitParticipantNames`

### 5.3 同步模型（SyncModels.swift）

- `PersistedLedgerSnapshot` 结构
- `categories`
- `books`
- `transactions`
- `budgets`
- `nextIDs`
- `updatedAt`

---

## 6. 页面拆分

### 6.1 现有页面文件

| 文件 | 职责 |
|------|------|
| `DashboardView.swift` | 概览首页 |
| `FinanceCalendarSheet.swift` | 财务日历 |
| `TransactionsView.swift` | 流水页 |
| `CreateTransactionView.swift` | 新增/编辑流水 |
| `CategoriesView.swift` | 分类管理 |
| `BooksView.swift` | 账本列表 |
| `BookDetailView.swift` | 账本详情 |
| `BudgetsView.swift` | 预算 |
| `OCRImportView.swift` | 识图导入 |
| `SettingsView.swift` | 设置 |
| `AppleSignInView.swift` | Apple 登录 |

### 6.2 OCR 重写

- `OCRService.swift`：Vision 文本识别
- `ReceiptParser.swift`：账单规则解析
- 区分详情页 / 列表页解析
- 分类建议词典
- 置信度估算

---

## 7. 必须补齐的点

### 7.1 远端现状

远端目前存在的问题：

1. 文件全部平铺在根目录，无分层
2. 数据模型字段不完整（缺分期、分账、多账本字段）
3. OCR 模块缺失
4. Dashboard 图表系统未实现
5. 底部导航未实现 Tab 重置逻辑
6. 玻璃卡片组件未抽离

### 7.2 与本地差异

| 维度 | 远端 | 本地 |
|------|------|------|
| 目录结构 | 扁平 | 分层（Components/Core/Models/Services/Views） |
| 数据模型 | 部分 | 完整（含分期、分账、多账本） |
| OCR | 无 | 完整（Vision + 解析器） |
| 图表 | 基础 | Charts 全套（饼图/柱状/趋势） |
| 导航 | 普通 Tab | Tab 切换重置 NavigationStack |
| 组件 | 内联 | 抽离复用组件 |

### 7.3 结论

**必须改动**：远端需要完全对齐本地结构，包括目录重组、模型补齐、页面拆分、OCR 重写。

---

## 8. 本地目标结构

### 8.1 组件层（Components/）

可复用 UI 组件：

- `GlassCard` — 玻璃卡片
- `MetricCard` — 指标卡
- `FilterChip` — 筛选胶囊
- `CategoryPicker` — 分类选择器
- `BookPicker` — 账本选择器
- `PaymentMethodPicker` — 支付渠道选择器
- `PieChartView` / `BarChartView` — 占比图
- `TrendChartView` — 趋势图
- `TransactionRow` — 流水行
- `SplitSettingView` — 分账设置
- `InstallmentSettingView` — 分期设置

### 8.2 核心层（Core/）

- `AppSettings` — 全局设置（主题、背景图、账本推荐开关）
- `LedgerStore` — 中心状态管理（@StateObject）
- `CloudSyncService` — CloudKit 同步服务

### 8.3 模型层（Models/）

- `LedgerModels` — 业务模型（Category、Transaction、Book、Budget、OCRImportResult、AppleAccountProfile）
- `SyncModels` — 同步相关模型（PersistedLedgerSnapshot）

### 8.4 服务层（Services/）

- `OCRService` — Vision 文本识别
- `ReceiptParser` — 账单规则解析

### 8.5 视图层（Views/）

按页面拆分的所有 View 文件。

### 8.6 入口

- `SmartLedgerLocalApp.swift` — App 入口
- `RootTabView` / `RootView.swift` — 根视图与 TabView
- `AppBackdrop` — 全局背景组件

---

## 9. Tab 调整

### 9.1 底部导航结构

```
TabView {
    DashboardView()       // 概览
    BooksView()           // 账本
    TransactionsView()    // 流水
    CreateTransactionView() // 记账
    MoreView()            // 更多
}
```

### 9.2 每个 Tab 使用独立 NavigationStack

切换 Tab 时可重置导航路径，回到该 Tab 的最外层。

---

## 10. 组件拆分要求

### 10.1 GlassCard

统一玻璃卡片组件：

- 圆角 18~24
- `.ultraThinMaterial` 背景
- 支持背景图场景下半透展示

### 10.2 RootTabView

- 管理 5 个 Tab
- 每个 Tab 独立 `NavigationStack`
- 切换时重置路径

### 10.3 AppBackdrop

- 全局背景图
- 支持自定义背景图
- 无背景图时使用默认渐变

---

## 11. 模型字段清单（速查）

### Category

```
id, name, flowType, icon, color, parentId, level, children
```

### Transaction

```
id, title, amount, kind, happenedAt, note, paymentMethod, source, currency,
categoryId, categoryName,
bookId, bookIds[], bookName, bookNames[],
installmentGroupId, installmentIndex, installmentMonths, installmentOriginalTotal,
originalAmount, discountAmount, premiumAmount,
paidByParticipantId, paidByParticipantName, splitParticipantIds[], splitParticipantNames[]
```

### Book

```
id, name, icon, color, startDate, endDate,
autoCollectEnabled, autoCollectCategoryIds[],
budgetLimitAmount, budgetStartDate, budgetEndDate,
balance, transactionCount, incomeAmount, expenseAmount,
participantNames[], isPinned
```

### Budget

```
id, name, limitAmount, periodType, year, month, startDate, endDate,
categoryId, categoryName, spentAmount, usageRatio
```

### OCRImportResult

```
amount, kind, merchant, paymentMethod, title, happenedAt,
categoryKeyword, categoryPath[], details[], confidence, rawLines,
originalAmount, discountAmount
```

---

## 12. 数据模型字段（远端对照）

> 以下为远端仓库需补齐 / 对齐的模型字段清单，逐模型列出。

### C. 账本模型（Book）

```
id, name, icon, color, startDate, endDate,
autoCollectEnabled, budgetLimitAmount, budgetStartDate, budgetEndDate,
balance, transactionCount, incomeAmount, expenseAmount,
participantNames, isPinned, autoCollectCategoryIds
```

推导属性：

- `splitEnabled`：成员数 > 1
- `budgetEnabled`：预算金额 > 0

### D. 预算模型（Budget）

```
id, name, limitAmount, periodType, year, month,
startDate, endDate, categoryId, categoryName, spentAmount, usageRatio
```

### E. OCR 结果模型（OCRImportResult）

```
amount, kind, merchant, paymentMethod, title, happenedAt,
categoryKeyword, categoryPath[], details[], confidence, rawLines,
originalAmount, discountAmount
```

### F. 同步模型（Sync / Snapshot）

```
categories, books, transactions, budgets,
nextIDs, updatedAt
```

---

## 13. 状态管理与同步字段

### CloudSyncState

`LedgerStore` 中需补齐的同步状态字段：

```
SyncState, CloudKit, Dashboard状态,
本地更新时间, 云端更新时间, 冲突状态
```

涉及文件：

- `Models/SyncModels.swift`
- `Core/LedgerStore.swift`
- `Services/CloudSyncService.swift`

---

## 14. 必须补齐的函数

> 远端 `LedgerStore.swift` 缺少以下关键函数，需按本地目标补齐。

- `bootstrap()`：启动引导
- `refreshDashboard(...)`：刷新 Dashboard 统计
- `createTransaction(...)`：新增流水
- `pushToCloud()`：推送到 iCloud

配套文件（位于 `Core/` 或 `Services/`）：

- `LocalAnalytics.swift`
- `DemoData.swift`
- `AppleCloudServices.swift`
- `Core/LedgerStore.swift`
- `Views/SettingsView.swift`

涉及符号与服务：

- `CloudSyncService`
- `LedgerStore.handleAppleSignIn(_:)`
- `Conflict`
- `Profile()`

---

## 15. 页面层差异与本地目标

### 15.1 Dashboard（DashboardView.swift）

**远端现状：** 基础汇总存在。

**远端不足：**

- 置顶时间范围（pinned range）未实现
- Sheet 交互不完整
- 财务日历未集成

**本地目标：**

- 收支趋势图
- 分类变化趋势图
- 置顶时间范围 `OverviewPreset`
- `FinanceCalendarSheet` 独立拆分

### 15.2 流水页（TransactionsView.swift）

**远端现状：** 基础列表存在。

**远端不足：**

- 筛选结构不完整
- popover / Sheet 交互缺失

**本地目标：**

- 按天分组 + 精准筛选
- 左滑快速改分类 / 账本 / 删除
- 分类、账本选择使用 popover / Sheet

### 15.3 新增编辑流水（CreateTransactionView.swift）

**远端现状：** 基础表单存在。

**远端不足：**

- 分类选择简化
- 分期、分账逻辑缺失

**本地目标关键配套组件：**

- `PaymentChannelField`
- `CategoryRootPickerSheet`

文件位置：

```
client/ios/SmartLedger/Views/CreateTransactionView.swift
```

### 15.4 OCR 模块（整体重构）

**远端现状不足：**

- 未拆层（OCR 服务 / 解析器耦合）
- `ReceiptParser` 简化
- 不支持列表页多笔解析

**本地目标 / 结论：**

> ⚠️ **远端 OCR 模块必须整体重构**

需拆分文件：

- `Services/OCRImportService.swift`
- `Core/ReceiptParser.swift`
- `Views/ImportReceiptView.swift`
- `Views/OCRImportPreview.swift`

### 15.5 设置与其他视图

**远端现状：**

- `SettingsAndCalendarViews.swift` 将设置页、支付渠道、财务日历混于单文件

**本地目标：** 拆分独立

- `Views/SettingsView.swift`（设置 + 支付渠道管理）
- `Views/FinanceCalendarSheet.swift`（财务日历）

需保留的本地细节：

- `OverviewPreset`（置顶时间范围）
- pinned range 逻辑
- Sheet 交互模式

---

## 16. 结论

1. 远端数据模型字段需按第 12 章清单逐模型补齐
2. `LedgerStore` 关键函数（第 14 章）必须实现
3. Dashboard / 流水页 / 创建流水页的交互差距需逐项对齐（第 15 章）
4. **OCR 模块必须整体重构**，按服务层 / 解析器 / UI 三层拆分
5. 设置、日历、支付渠道从单文件拆分为独立视图

> 完成上述 5 项后，远端仓库即可与本地修改对齐。

---

> **文档结束**
>
> 本清单用于指导远端 GitHub 仓库对齐本地修改，确保所有差异点都被覆盖。
