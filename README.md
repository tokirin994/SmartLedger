# SmartLedgerLocal

基于规格书和现有截图重建的 iOS 17+ SwiftUI 本地优先记账 App 源码。

## 已实现源码

- 五栏主导航：概览、账本、流水、记账、更多。
- 本地 JSON 快照持久化、默认分类树、模拟数据。
- 流水新增、编辑、删除、筛选、按日期分组；支持多账本、分期拆分、付款人字段。
- 账本、分类、预算的基础管理和统计。
- 概览指标、分类饼/柱图、收支趋势图、预算摘要和财务日历。
- PhotosUI + Vision OCR 选图识别，解析候选后由用户确认入账。
- 主题模式、账本归属推荐开关和支付渠道预设。

## 在 macOS / Xcode 中接入

1. 新建一个 iOS App（SwiftUI，最低 iOS 17）。
2. 把 `client/ios/SmartLedger` 内的全部 `.swift` 文件加入同一个 Target。
3. 在 Target 的 Signing & Capabilities 中按需添加 `iCloud / CloudKit`、`Sign in with Apple`。
4. 选择真机或模拟器编译运行。

工程配置文件、签名、App 图标资产和 CloudKit 容器均依赖 Xcode 与 Apple Developer 配置，未在当前 Windows 环境生成。

## 仓库目录

Swift 源码现已按职责迁移至 `client/ios/SmartLedger/{Components,Core,Models,Services,Views}`，规格书与对齐清单位于 `client/ios/docs/`。
