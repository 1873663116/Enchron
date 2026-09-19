import DesignSystem
import MediaLibrary
import MediaSource
import Playback
import SwiftUI
import UIKit

struct SettingsScreen: View {
    @Environment(DeveloperMetricsModel.self) private var developerMetrics
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackSessionModel.self) private var playbackSession
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    @Environment(SettingsViewModel.self) private var viewModel
    @Environment(AppModalPresentationCoordinator.self)
    private var modalPresentationCoordinator
    @State private var selectedCategoryID: String = Category.general.rawValue
    @State private var artworkUsageInBytes: Int64 = 0
    @State private var containerIndexUsageInBytes: Int64 = 0
    @State private var showsLicenses = false

    private enum Category: String, CaseIterable {
        case general, playback, storagePrivacy, developer, about

        var title: String {
            switch self {
            case .general: String(localized: "General")
            case .playback: String(localized: "Playback Behavior")
            case .storagePrivacy: String(localized: "Storage & Privacy")
            case .developer: String(localized: "Developer")
            case .about: String(localized: "About")
            }
        }

        /// A category whose rows already say what they do needs no subtitle.
        var summary: String? {
            switch self {
            case .general: String(localized: "Language and app-wide preferences")
            case .playback: nil
            case .storagePrivacy: String(localized: "Rebuildable cache, playback history, and data handling")
            case .developer: String(localized: "Performance readout in every window and space")
            case .about: String(localized: "Version, support, and feedback")
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape.fill"
            case .playback: "play.circle.fill"
            case .storagePrivacy: "internaldrive.fill"
            case .developer: "wrench.and.screwdriver.fill"
            case .about: "info.circle.fill"
            }
        }
    }

    private var selectedCategory: Category {
        Category(rawValue: selectedCategoryID) ?? .playback
    }

    /// Apple's supported way to switch an app's language is the system's
    /// per-app language setting, which relaunches the app in the new language.
    /// The app's job is the affordance that gets the wearer there.
    private var languageItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "app-language",
                title: String(localized: "Language"),
                systemName: "globe",
                supportingText: String(localized: "Choose Enchron's language in Settings."),
                accessory: .action(
                    title: String(localized: "Open Settings"),
                    feedback: nil,
                    systemName: nil,
                    role: .normal,
                    action: openLanguageSettings
                )
            )
        ]
    }

    private func openLanguageSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    var body: some View {
        HStack(spacing: 0) {
            CategorySidebar(
                items: Category.allCases.map { CategorySidebarItem(id: $0.rawValue, icon: $0.icon, title: $0.title) },
                selection: $selectedCategoryID,
                title: String(localized: "Settings"),
                containerIdentifier: "Settings-MainWindow-sidebar",
                identifierPrefix: "Settings"
            )

            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Settings-SettingsScreen")
        .task { await refreshCacheUsage() }
        .onChange(of: selectedCategoryID) { _, category in
#if DEBUG
            playbackSession.recordSurfaceInputProbe(
                "reachability settings delivered action=category.\(category)",
                retention: .evidence
            )
#endif
        }
        .sequencedSheet(
            isPresented: $showsLicenses,
            coordinator: modalPresentationCoordinator,
            id: .openSourceLicenses
        ) {
            OpenSourceLicensesView()
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text(selectedCategory.title)
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(.primary)
                    if let summary = selectedCategory.summary {
                        Text(summary)
                            .font(DesignTokens.Typography.metadata)
                            .foregroundStyle(DesignTokens.Surface.supportingText)
                    }
                }
                sections(for: selectedCategory)
            }
            .frame(maxWidth: DesignTokens.Layout.settingsReadingColumnWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, DesignTokens.Spacing.xxxl)
            .levelContent(id: selectedCategoryID)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.leading, DesignTokens.SourceSidebar.trailingContentGap)
        .padding(.trailing, DesignTokens.SourceSidebar.windowInset)
        .padding(.vertical, DesignTokens.SourceSidebar.windowInset)
        .accessibilityIdentifier("Settings-SettingsScreen-detail")
    }

    @ViewBuilder
    private func sections(for category: Category) -> some View {
        switch category {
        case .general:
            SettingListGroup(accessibilityIdentifier: "Settings-General-group", items: languageItems)
        case .playback:
            SettingListGroup(accessibilityIdentifier: "Settings-Playback-group", items: playbackItems)
        case .storagePrivacy:
            SettingListGroup(accessibilityIdentifier: "Settings-StoragePrivacy-group", items: storagePrivacyItems)
        case .developer:
            SettingListGroup(accessibilityIdentifier: "Settings-Developer-group", items: developerItems)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                Text("Video and display")
                    .font(DesignTokens.Typography.sectionHeader)
                Text("Video is the source frame rate. Requested is a preference submitted to the system, not confirmation of a mode switch. DisplayLink measures app display updates, not the physical panel refresh rate. Verify the panel’s current refresh rate using the Display timeline in Apple Instruments; DisplayLink alone does not confirm whether the requested display mode was applied.")
                Text("Playback")
                    .font(DesignTokens.Typography.sectionHeader)
                Text("Enqueued counts video samples sent to the renderer each second. Dropped is the current video renderer’s cumulative count; replacing the renderer can reset it. Buffer is queued source data.")
                Text("App performance")
                    .font(DesignTokens.Typography.sectionHeader)
                Text("Memory is the app footprint. Scene updates measures RealityKit updates. Main-thread stall is the longest delay in the sampling interval. Detailed metrics add memory categories and queued video frames.")
            }
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(DesignTokens.Surface.supportingText)
        case .about:
            SettingListGroup(accessibilityIdentifier: "Settings-About-group", items: aboutItems)
        }
    }

    private var developerItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "display-refresh-request",
                title: String(localized: "Request Video Refresh Rate"),
                systemName: "display",
                supportingText: String(localized: "Request a display mode matching the video. Disable to compare system defaults."),
                accessory: .boundToggle(
                    isOn: Binding(
                        get: { playbackRuntime.displayCriteria.isEnabled },
                        set: { playbackRuntime.displayCriteria.isEnabled = $0 }
                    ),
                    isEnabled: true, marker: nil
                )
            ),
            SettingListGroup.Item(
                id: "developer-details",
                title: String(localized: "Detailed Metrics"),
                systemName: "list.bullet",
                supportingText: String(localized: "Include memory categories and queued video frames."),
                accessory: .boundToggle(
                    isOn: Binding(
                        get: { developerMetrics.showsDetailedMetrics },
                        set: { developerMetrics.showsDetailedMetrics = $0 }
                    ),
                    isEnabled: true, marker: nil
                )
            ),
            SettingListGroup.Item(
                id: "developer-overlay",
                title: String(localized: "Performance Overlay"),
                systemName: "gauge.with.dots.needle.bottom.50percent",
                supportingText: String(localized: "Video and display, playback, and app performance in separate rows."),
                accessory: .boundToggle(
                    isOn: Binding(
                        get: { viewModel.preferences.developerModeEnabled },
                        set: { value in viewModel.update { $0.developerModeEnabled = value } }
                    ),
                    isEnabled: true,
                    marker: nil
                )
            )
        ]
    }

    private var playbackItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "resume-strategy",
                title: String(localized: "Resume Playback"),
                systemName: "play.circle",
                accessory: .menu(title: resumeTitle, options: [
                    SettingListGroup.MenuOption(String(localized: "Ask Every Time"), id: "askEveryTime") { setResume(.askEveryTime) },
                    SettingListGroup.MenuOption(String(localized: "Always Resume"), id: "alwaysResume") { setResume(.alwaysResume) },
                    SettingListGroup.MenuOption(String(localized: "Always Start Over"), id: "alwaysStartFromBeginning") { setResume(.alwaysStartFromBeginning) }
                ])
            ),
            SettingListGroup.Item(
                id: "end-behavior",
                title: String(localized: "When Playback Ends"),
                systemName: "flag.checkered",
                accessory: .menu(title: endBehaviorTitle, options: [
                    SettingListGroup.MenuOption(String(localized: "Replay"), id: "repeatOne") { setEnd(.repeatOne) },
                    SettingListGroup.MenuOption(String(localized: "Play Next"), id: "playNext") { setEnd(.playNext) }
                ])
            ),
            SettingListGroup.Item(
                id: "default-speed",
                title: String(localized: "Default Speed"),
                systemName: "speedometer",
                accessory: .menu(
                    title: speedTitle(viewModel.preferences.defaultPlaybackSpeed),
                    options: PlaybackModel.PlaybackSpeed.allCases.map { speed in
                        SettingListGroup.MenuOption(speedTitle(speed.value), id: "\(speed.value)") {
                            viewModel.update { $0.defaultPlaybackSpeed = speed.value }
                            recordMenuReachability("default-speed")
                        }
                    }
                )
            ),
            SettingListGroup.Item(
                id: "controls-auto-hide",
                title: String(localized: "Auto-Hide Playback Controls"),
                systemName: "timer",
                accessory: .menu(title: autoHideTitle, options: [
                    SettingListGroup.MenuOption(String(localized: "5 Seconds"), id: "5") { setAutoHide(5) },
                    SettingListGroup.MenuOption(String(localized: "8 Seconds"), id: "8") { setAutoHide(8) },
                    SettingListGroup.MenuOption(String(localized: "15 Seconds"), id: "15") { setAutoHide(15) },
                    SettingListGroup.MenuOption(String(localized: "Never"), id: "never") { setAutoHide(0) }
                ])
            ),
            SettingListGroup.Item(
                id: "surroundings-dimming",
                title: String(localized: "Lower Ambient Brightness"),
                systemName: "circle.lefthalf.filled",
                supportingText: String(localized: "Darken the room around the player window and around environments that request it, without touching the video."),
                accessory: .boundToggle(
                    isOn: Binding(
                        get: { viewModel.preferences.surroundingsDimmingEnabled },
                        set: { value in viewModel.update { $0.surroundingsDimmingEnabled = value } }
                    ),
                    isEnabled: true,
                    marker: nil
                )
            )
        ]
    }

    private var storagePrivacyItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "clear-artwork-cache",
                title: String(localized: "Artwork Cache"),
                systemName: "photo.stack",
                accessory: .valueAction(
                    value: ByteCountFormatter.string(fromByteCount: artworkUsageInBytes, countStyle: .file),
                    actionTitle: String(localized: "Clear"),
                    feedback: String(localized: "Cleared"),
                    action: clearArtworkCache
                )
            ),
            SettingListGroup.Item(
                id: "clear-container-index-cache",
                title: String(localized: "Container Index Cache"),
                systemName: "shippingbox",
                accessory: .valueAction(
                    value: ByteCountFormatter.string(
                        fromByteCount: containerIndexUsageInBytes,
                        countStyle: .file
                    ),
                    actionTitle: String(localized: "Clear"),
                    feedback: String(localized: "Cleared"),
                    action: clearContainerIndexCache
                )
            ),
            SettingListGroup.Item(
                id: "clear-progress",
                title: String(localized: "Playback Progress"),
                systemName: "clock.arrow.circlepath",
                accessory: .action(
                    title: String(localized: "Clear All"),
                    feedback: String(localized: "Cleared"),
                    systemName: nil,
                    role: .destructive,
                    action: clearProgress
                )
            ),
            SettingListGroup.Item(
                id: "privacy-notice",
                title: String(localized: "Privacy Notice"),
                systemName: "hand.raised",
                keyValueDetail: [
                    .init(key: "Local Files", value: "Read on device"),
                    .init(key: "Remote Credentials", value: "Stored in Keychain"),
                    .init(key: "Diagnostics", value: "No analytics or tracking")
                ]
            )
        ]
    }

    private var aboutItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "version-build",
                title: String(localized: "Version & Build"),
                systemName: "info.circle",
                accessory: .valueAction(value: appVersion, actionTitle: String(localized: "Copy"), feedback: String(localized: "Copied"), action: { copy(appVersion) })
            ),
            SettingListGroup.Item(
                id: "support-feedback",
                title: String(localized: "Support & Feedback"),
                systemName: "questionmark.circle",
                accessory: .valueAction(value: feedbackEmail, actionTitle: String(localized: "Copy"), feedback: String(localized: "Copied"), action: { copy(feedbackEmail) })
            ),
            SettingListGroup.Item(
                id: "licenses",
                title: String(localized: "Open-source Licenses"),
                systemName: "doc.text",
                accessory: .action(
                    title: String(localized: "View"),
                    feedback: nil,
                    systemName: nil,
                    role: .normal,
                    action: {
                        recordActionReachability("licenses")
                        showsLicenses = true
                    }
                )
            )
        ]
    }

    private func setResume(_ value: ResumePolicy) {
        viewModel.update { $0.resumePolicy = value }
        recordMenuReachability("resume-strategy")
    }

    private func setEnd(_ value: PlaybackEndBehavior) {
        viewModel.update { $0.playbackEndBehavior = value }
        recordMenuReachability("end-behavior")
    }

    private func setAutoHide(_ seconds: Int) {
        viewModel.update { $0.controlsAutoHideSeconds = seconds }
        playbackSession.controlsAutoHideSeconds = seconds
        recordMenuReachability("controls-auto-hide")
    }

    private func recordMenuReachability(_ family: String) {
#if DEBUG
        playbackSession.recordSurfaceInputProbe(
            "reachability settings delivered action=menu.\(family)",
            retention: .evidence
        )
#endif
    }

    private func recordActionReachability(_ id: String) {
#if DEBUG
        playbackSession.recordSurfaceInputProbe(
            "reachability settings delivered action=action.\(id)",
            retention: .evidence
        )
#endif
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
        case .repeatOne: "Replay"
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

    private let feedbackEmail = "xzp1873663116@icloud.com"
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    private func copy(_ string: String) {
        UIPasteboard.general.string = string
    }

    private func refreshCacheUsage() async {
        async let artwork = ArtworkStore.shared.diskUsageInBytes()
        async let containerIndex = ContainerIndexCache.shared.diskUsageInBytes()
        artworkUsageInBytes = await artwork
        containerIndexUsageInBytes = await containerIndex
    }

    private func clearArtworkCache() {
        Task {
            await ArtworkStore.shared.clear()
            viewModel.onArtworkCacheCleared?()
            await refreshCacheUsage()
        }
    }

    private func clearContainerIndexCache() {
        recordActionReachability("container-index-cache")
        Task {
            await ContainerIndexCache.shared.clear()
            await refreshCacheUsage()
        }
    }

    private func clearProgress() {
        recordActionReachability("clear-progress")
        playbackLauncher.clearViewingStates()
    }
}
