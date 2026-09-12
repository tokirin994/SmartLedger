import Foundation
import SwiftUI
import UIKit

struct DashboardPinnedRange: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var range: CustomDateRange

    enum CodingKeys: String, CodingKey {
        case id, title, start, end
    }

    init(id: UUID = UUID(), title: String, range: CustomDateRange) {
        self.id = id
        self.title = title
        self.range = range
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        let start = try container.decode(Date.self, forKey: .start)
        let end = try container.decode(Date.self, forKey: .end)
        range = CustomDateRange(start: start, end: end)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(range.start, forKey: .start)
        try container.encode(range.end, forKey: .end)
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "白天"
        case .dark: return "夜间"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var iCloudPreferred: Bool {
        didSet { UserDefaults.standard.set(iCloudPreferred, forKey: Self.iCloudPreferredKey) }
    }

    @Published var jianguoyunEndpoint: String {
        didSet { UserDefaults.standard.set(jianguoyunEndpoint, forKey: Self.jianguoyunEndpointKey) }
    }

    @Published var jianguoyunUsername: String {
        didSet { UserDefaults.standard.set(jianguoyunUsername, forKey: Self.jianguoyunUsernameKey) }
    }

    @Published var jianguoyunAppPassword: String {
        didSet { UserDefaults.standard.set(jianguoyunAppPassword, forKey: Self.jianguoyunPasswordKey) }
    }

    var jianguoyunConfigured: Bool {
        !jianguoyunEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !jianguoyunUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !jianguoyunAppPassword.isEmpty
    }

    @Published private(set) var paymentChannels: [String] {
        didSet { UserDefaults.standard.set(paymentChannels, forKey: Self.paymentChannelsKey) }
    }

    @Published var bookAssignmentPromptEnabled: Bool {
        didSet { UserDefaults.standard.set(bookAssignmentPromptEnabled, forKey: Self.bookAssignmentPromptEnabledKey) }
    }

    @Published var appearanceMode: AppAppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceModeKey) }
    }

    @Published private(set) var backgroundImageData: Data?

    @Published private(set) var pinnedDashboardRanges: [DashboardPinnedRange] = [] {
        didSet { persistPinnedDashboardRanges() }
    }

    var suggestedPaymentChannels: [String] {
        Self.defaultPaymentChannels
    }

    var preferredColorScheme: ColorScheme? {
        appearanceMode.colorScheme
    }

    var hasCustomBackgroundImage: Bool {
        backgroundImageData != nil
    }

    var backgroundPreviewImage: UIImage? {
        guard let backgroundImageData else { return nil }
        return UIImage(data: backgroundImageData)
    }

    private static let iCloudPreferredKey = "smartledgerlocal.icloudPreferred"
    private static let jianguoyunEndpointKey = "smartledger.jianguoyun.endpoint"
    private static let jianguoyunUsernameKey = "smartledger.jianguoyun.username"
    private static let jianguoyunPasswordKey = "smartledger.jianguoyun.password"
    private static let paymentChannelsKey = "smartledgerlocal.paymentChannels"
    private static let bookAssignmentPromptEnabledKey = "smartledgerlocal.bookAssignmentPromptEnabled"
    private static let appearanceModeKey = "smartledgerlocal.appearanceMode"
    private static let pinnedDashboardRangesKey = "smartledgerlocal.pinnedDashboardRanges"
    private static let backgroundImageFileName = "custom-background.jpg"

    private static let defaultPaymentChannels: [String] = [
        "微信",
        "微信零钱",
        "支付宝",
        "支付宝余额",
        "花呗",
        "云闪付",
        "信用卡",
        "储蓄卡",
        "现金"
    ]

    init() {
        self.iCloudPreferred = UserDefaults.standard.object(forKey: Self.iCloudPreferredKey) as? Bool ?? false
        self.jianguoyunEndpoint = UserDefaults.standard.string(forKey: Self.jianguoyunEndpointKey) ?? "https://dav.jianguoyun.com/dav/SmartLedger/ledger-snapshot.json"
        self.jianguoyunUsername = UserDefaults.standard.string(forKey: Self.jianguoyunUsernameKey) ?? ""
        self.jianguoyunAppPassword = UserDefaults.standard.string(forKey: Self.jianguoyunPasswordKey) ?? ""
        self.bookAssignmentPromptEnabled = UserDefaults.standard.object(forKey: Self.bookAssignmentPromptEnabledKey) as? Bool ?? true
        self.appearanceMode = AppAppearanceMode(rawValue: UserDefaults.standard.string(forKey: Self.appearanceModeKey) ?? "system") ?? .system

        let storedChannels = UserDefaults.standard.stringArray(forKey: Self.paymentChannelsKey) ?? []
        let merged = storedChannels.isEmpty ? Self.defaultPaymentChannels : storedChannels
        self.paymentChannels = Self.uniqueNormalized(from: merged)
        self.backgroundImageData = Self.loadBackgroundImageData()
        self.pinnedDashboardRanges = Self.loadPinnedDashboardRanges()
    }

    @discardableResult
    func registerPaymentChannel(_ name: String) -> String? {
        guard let normalized = Self.normalizedChannel(name) else { return nil }

        paymentChannels.removeAll { Self.isSameChannel($0, normalized) }
        paymentChannels.insert(normalized, at: 0)
        return normalized
    }

    func removePaymentChannel(_ name: String) {
        paymentChannels.removeAll { Self.isSameChannel($0, name) }
    }

    func setBackgroundImage(_ image: UIImage) {
        let prepared = Self.preparedBackgroundImage(from: image)
        guard let data = prepared.jpegData(compressionQuality: 0.82) else { return }
        do {
            try Self.ensureSupportDirectoryExists()
            try data.write(to: Self.backgroundImageURL(), options: .atomic)
            backgroundImageData = data
        } catch {
            #if DEBUG
            print("[AppSettings] Failed to persist background image: \(error)")
            #endif
        }
    }

    func clearBackgroundImage() {
        do {
            let url = Self.backgroundImageURL()
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            #if DEBUG
            print("[AppSettings] Failed to remove background image: \(error)")
            #endif
        }
        backgroundImageData = nil
    }

    func addPinnedDashboardRange(title: String, range: CustomDateRange) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmed.isEmpty ? Self.defaultPinnedTitle(for: range) : trimmed

        if let index = pinnedDashboardRanges.firstIndex(where: { $0.range == range }) {
            pinnedDashboardRanges[index].title = resolvedTitle
            return
        }

        pinnedDashboardRanges.insert(
            DashboardPinnedRange(title: resolvedTitle, range: range),
            at: 0
        )

        if pinnedDashboardRanges.count > 8 {
            pinnedDashboardRanges = Array(pinnedDashboardRanges.prefix(8))
        }
    }

    func removePinnedDashboardRange(_ item: DashboardPinnedRange) {
        pinnedDashboardRanges.removeAll { $0.id == item.id }
    }

    func renamePinnedDashboardRange(_ item: DashboardPinnedRange, title: String) {
        guard let index = pinnedDashboardRanges.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        pinnedDashboardRanges[index].title = trimmed.isEmpty ? Self.defaultPinnedTitle(for: item.range) : trimmed
    }

    private static func uniqueNormalized(from names: [String]) -> [String] {
        var result: [String] = []
        for name in names {
            guard let normalized = normalizedChannel(name), !result.contains(where: { isSameChannel($0, normalized) }) else {
                continue
            }
            result.append(normalized)
        }
        return result
    }

    private static func isSameChannel(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private static func normalizedChannel(_ name: String) -> String? {
        let trimmed = name
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func supportDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SmartLedgerLocal", isDirectory: true)
    }

    private static func backgroundImageURL() -> URL {
        supportDirectoryURL().appendingPathComponent(backgroundImageFileName)
    }

    private static func ensureSupportDirectoryExists() throws {
        try FileManager.default.createDirectory(at: supportDirectoryURL(), withIntermediateDirectories: true)
    }

    private static func loadBackgroundImageData() -> Data? {
        try? Data(contentsOf: backgroundImageURL())
    }

    private static func preparedBackgroundImage(from image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1600
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxDimension else { return image }

        let scale = maxDimension / longestEdge
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func persistPinnedDashboardRanges() {
        let data = try? JSONEncoder.iso8601.encode(pinnedDashboardRanges)
        UserDefaults.standard.set(data, forKey: Self.pinnedDashboardRangesKey)
    }

    private static func loadPinnedDashboardRanges() -> [DashboardPinnedRange] {
        guard let data = UserDefaults.standard.data(forKey: pinnedDashboardRangesKey),
			let decoded = try? JSONDecoder.iso8601.decode([DashboardPinnedRange].self, from: data)	 else {
            return []
        }
        return decoded
    }

    private static func defaultPinnedTitle(for range: CustomDateRange) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: range.start)) ~ \(formatter.string(from: range.end))"
    }
}

struct AppBackdrop: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    Color(.systemBackground).opacity(0.97)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if let image = settings.backgroundPreviewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.58)
                    }
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    func appBackground() -> some View {
        background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    func appBackdrop() -> some View {
        background(AppBackdrop())
    }

    func glassCard(cornerRadius: CGFloat = 22, strokeOpacity: Double = 0.26) -> some View {
        background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
        }
    }
}
