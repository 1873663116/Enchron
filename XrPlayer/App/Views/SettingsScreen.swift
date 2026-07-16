import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SettingsScreen: View {
    @Environment(AppModel.self) private var appModel
    @State private var viewModel: SettingsViewModel
    @State private var selectedCategoryID: String = Category.playback.rawValue
    @State private var cacheUsageInBytes: Int64 = 0
    @State private var showsLicenses = false

    init(store: PreferencesStoring = UserDefaultsStore()) {
        _viewModel = State(initialValue: SettingsViewModel(store: store))
    }

    private enum Category: String, CaseIterable {
        case playback, spatial, storagePrivacy, about

        var title: String {
            switch self {
            case .playback: "Playback"
            case .spatial: "Spatial Content"
            case .storagePrivacy: "Storage & Privacy"
            case .about: "About"
            }
        }

        var summary: String {
            switch self {
            case .playback: "Resume behavior, end behavior, and control timing"
            case .spatial: "Default environments and immersive entry for spatial media"
            case .storagePrivacy: "Rebuildable cache, playback history, and data handling"
            case .about: "Version, support, and feedback"
            }
        }

        var icon: String {
            switch self {
            case .playback: "play.circle.fill"
            case .spatial: "visionpro.fill"
            case .storagePrivacy: "internaldrive.fill"
            case .about: "info.circle.fill"
            }
        }
    }

    private var selectedCategory: Category {
        Category(rawValue: selectedCategoryID) ?? .playback
    }

    var body: some View {
        HStack(spacing: 0) {
            CategorySidebar(
                items: Category.allCases.map { CategorySidebarItem(id: $0.rawValue, icon: $0.icon, title: $0.title) },
                selection: $selectedCategoryID,
                title: "Settings",
                containerIdentifier: "Settings-MainWindow-sidebar",
                identifierPrefix: "Settings"
            )
            .padding(.leading, DesignTokens.SourceSidebar.windowInset)
            .padding(.vertical, DesignTokens.SourceSidebar.windowInset)

            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBackgroundEffect(.plate, in: DesignTokens.ShapeToken.panel, displayMode: .always)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Settings-SettingsScreen")
        .task { await refreshCacheUsage() }
        .sheet(isPresented: $showsLicenses) {
            OpenSourceLicensesView()
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text(selectedCategory.title)
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(.white)
                    Text(selectedCategory.summary)
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                }
                sections(for: selectedCategory)
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, DesignTokens.Spacing.xxxl)
            .id(selectedCategoryID)
            .transition(.opacity)
        }
        .scrollIndicators(.hidden)
        .animation(DesignTokens.AnimationToken.fadeIn, value: selectedCategoryID)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.leading, DesignTokens.SourceSidebar.trailingContentGap)
        .padding(.trailing, DesignTokens.SourceSidebar.windowInset)
        .padding(.vertical, DesignTokens.SourceSidebar.windowInset)
        .accessibilityIdentifier("Settings-SettingsScreen-detail")
    }

    @ViewBuilder
    private func sections(for category: Category) -> some View {
        switch category {
        case .playback:
            SettingListGroup(accessibilityIdentifier: "Settings-Playback-group", items: playbackItems)
        case .spatial:
            SettingListGroup(accessibilityIdentifier: "Settings-SpatialContent-picker-environment", items: spatialItems)
        case .storagePrivacy:
            SettingListGroup(accessibilityIdentifier: "Settings-StoragePrivacy-group", items: storagePrivacyItems)
        case .about:
            SettingListGroup(accessibilityIdentifier: "Settings-About-group", items: aboutItems)
        }
    }

    // MARK: - Playback

    private var playbackItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "resume-strategy",
                title: "Resume Playback",
                systemName: "play.circle",
                accessory: .menu(title: resumeTitle, options: [
                    SettingListGroup.MenuOption("Ask Every Time") { setResume(.askEveryTime) },
                    SettingListGroup.MenuOption("Always Resume") { setResume(.alwaysResume) },
                    SettingListGroup.MenuOption("Always Start Over") { setResume(.alwaysStartFromBeginning) }
                ])
            ),
            SettingListGroup.Item(
                id: "end-behavior",
                title: "End of Playback",
                systemName: "flag.checkered",
                accessory: .menu(title: endBehaviorTitle, options: [
                    SettingListGroup.MenuOption("Stop") { setEnd(.stop) },
                    SettingListGroup.MenuOption("Loop Single Episode") { setEnd(.repeatOne) },
                    SettingListGroup.MenuOption("Play Next") { setEnd(.playNext) }
                ])
            ),
            SettingListGroup.Item(
                id: "default-speed",
                title: "Default Speed",
                systemName: "speedometer",
                accessory: .menu(
                    title: speedTitle(viewModel.preferences.defaultPlaybackSpeed),
                    options: PlaybackModel.PlaybackSpeed.allCases.map { speed in
                        SettingListGroup.MenuOption(speedTitle(speed.value)) {
                            viewModel.update { $0.defaultPlaybackSpeed = speed.value }
                        }
                    }
                )
            ),
            SettingListGroup.Item(
                id: "controls-auto-hide",
                title: "Controls Auto-Hide",
                systemName: "timer",
                accessory: .menu(title: autoHideTitle, options: [
                    SettingListGroup.MenuOption("5 Seconds") { setAutoHide(5) },
                    SettingListGroup.MenuOption("8 Seconds") { setAutoHide(8) },
                    SettingListGroup.MenuOption("15 Seconds") { setAutoHide(15) },
                    SettingListGroup.MenuOption("Never") { setAutoHide(0) }
                ])
            )
        ]
    }

    // MARK: - Spatial Content

    private var spatialItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "default-environment",
                title: "Default Environment",
                systemName: "mountain.2",
                accessory: .menu(title: environmentTitle, options: SpatialSceneDomain.CinemaEnvironment.allCases.map { environment in
                    SettingListGroup.MenuOption(environment.displayName) {
                        viewModel.update { $0.defaultEnvironmentID = environment.rawValue }
                        appModel.currentCinemaEnvironment = environment
                    }
                })
            )
        ]
    }

    // MARK: - Storage & Privacy

    private var storagePrivacyItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "clear-cache",
                title: "Thumbnail Cache",
                systemName: "photo.stack",
                accessory: .valueAction(
                    value: ByteCountFormatter.string(fromByteCount: cacheUsageInBytes, countStyle: .file),
                    actionTitle: "Clear",
                    feedback: "Cleared",
                    action: clearCache
                )
            ),
            SettingListGroup.Item(
                id: "clear-progress",
                title: "Playback Progress",
                systemName: "clock.arrow.circlepath",
                accessory: .action(
                    title: "Clear All",
                    feedback: "Cleared",
                    systemName: nil,
                    role: .destructive,
                    action: clearProgress
                )
            ),
            SettingListGroup.Item(
                id: "privacy-notice",
                title: "Privacy Notice",
                systemName: "hand.raised",
                keyValueDetail: [
                    .init(key: "Local Files", value: "Read on device"),
                    .init(key: "Photos", value: "Read only after permission"),
                    .init(key: "Remote Credentials", value: "Stored in Keychain"),
                    .init(key: "Diagnostics", value: "Remain on device")
                ]
            )
        ]
    }

    // MARK: - About

    private var aboutItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "version-build",
                title: "Version & Build",
                systemName: "info.circle",
                accessory: .valueAction(value: appVersion, actionTitle: "Copy", feedback: "Copied", action: { copy(appVersion) })
            ),
            SettingListGroup.Item(
                id: "support-feedback",
                title: "Support & Feedback",
                systemName: "questionmark.circle",
                accessory: .valueAction(value: feedbackEmail, actionTitle: "Copy", feedback: "Copied", action: { copy(feedbackEmail) })
            ),
            SettingListGroup.Item(
                id: "licenses",
                title: "Open-source Licenses",
                systemName: "doc.text",
                accessory: .action(
                    title: "View",
                    feedback: nil,
                    systemName: nil,
                    role: .normal,
                    action: { showsLicenses = true }
                )
            )
        ]
    }

    // MARK: - Value mappings

    private func setResume(_ value: PersistenceDomain.ResumePolicy) { viewModel.update { $0.resumePolicy = value } }
    private func setEnd(_ value: PersistenceDomain.PlaybackEndBehavior) { viewModel.update { $0.playbackEndBehavior = value } }
    private func setAutoHide(_ seconds: Int) {
        viewModel.update { $0.controlsAutoHideSeconds = seconds }
        appModel.controlsAutoHideSeconds = seconds
    }

    private var resumeTitle: String {
        switch viewModel.preferences.resumePolicy {
        case .askEveryTime: "Ask Every Time"
        case .alwaysResume: "Always Resume"
        case .alwaysStartFromBeginning: "Always Start Over"
        }
    }

    private var endBehaviorTitle: String {
        switch viewModel.preferences.playbackEndBehavior {
        case .stop: "Stop"
        case .repeatOne: "Loop Single Episode"
        case .playNext: "Play Next"
        }
    }

    private var autoHideTitle: String {
        switch viewModel.preferences.controlsAutoHideSeconds {
        case 0: "Never"
        case let seconds: "\(seconds) Seconds"
        }
    }

    private func speedTitle(_ speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))×" : "\(String(format: "%g", speed))×"
    }

    private var environmentTitle: String {
        SpatialSceneDomain.CinemaEnvironment(
            preferenceValue: viewModel.preferences.defaultEnvironmentID
        )?.displayName ?? SpatialSceneDomain.CinemaEnvironment.darkTheatre.displayName
    }

    private let feedbackEmail = "feedback@enchron.app"
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    private func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    private func refreshCacheUsage() async {
        cacheUsageInBytes = await ThumbnailService.shared.cacheUsageInBytes()
    }

    private func clearCache() {
        Task {
            await ThumbnailService.shared.clearCache()
            await refreshCacheUsage()
        }
    }

    private func clearProgress() {
        Task { await SwiftDataStore().clearAllProgress() }
    }
}

private struct OpenSourceLicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Text("PlaybackCore — MIT")
                Text("AMSMB2 — MIT")
                Text("RealityKitScripting — Apple sample code license")
            }
            .navigationTitle("Open-source Licenses")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
