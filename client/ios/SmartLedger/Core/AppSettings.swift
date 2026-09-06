import Foundation

/// 全局设置统一由 LedgerStore 持有；本类型提供持久化 key，避免散落的字符串常量。
enum AppSettings {
    static let appearanceKey = "smartLedger.appearance"
    static let recommendBooksKey = "smartLedger.recommendBooks"
    static let backgroundKey = "smartLedger.background"
    static let cloudEnabledKey = "smartLedger.cloudEnabled"
    static let appleProfileKey = "smartLedger.appleProfile"
}
