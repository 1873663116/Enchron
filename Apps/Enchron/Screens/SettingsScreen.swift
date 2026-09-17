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
    @State private var selectedCategoryID: String = Category.playback.rawValue
    @State private var artworkUsageInBytes: Int64 = 0
    @State private var containerIndexUsageInBytes: Int64 = 0
    @State private var showsLicenses = false

    private enum Category: String, CaseIterable {
        case playback, storagePrivacy, developer, about

        var title: String {
            switch self {
            case .playback: "Playback"
            case .storagePrivacy: "Storage & Privacy"
            case .developer: "Developer"
            case .about: "About"
            }
        }

        var summary: String {
            switch self {
            case .playback: "Resume behavior, default environment, and control timing"
            case .storagePrivacy: "Rebuildable cache, playback history, and data handling"
            case .developer: "Performance readout in every window and space"
            case .about: "Version, support, and feedback"
            }
        }

        var icon: String {
            switch self {
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

    var body: some View {
        HStack(spacing: 0) {
            CategorySidebar(
                items: Category.allCases.map { CategorySidebarItem(id: $0.rawValue, icon: $0.icon, title: $0.title) },
                selection: $selectedCategoryID,
                title: "Settings",
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
                    Text(selectedCategory.summary)
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
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
        case .playback:
            SettingListGroup(accessibilityIdentifier: "Settings-Playback-group", items: playbackItems)
        case .storagePrivacy:
            SettingListGroup(accessibilityIdentifier: "Settings-StoragePrivacy-group", items: storagePrivacyItems)
        case .developer:
            SettingListGroup(accessibilityIdentifier: "Settings-Developer-group", items: developerItems)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                Text("Video and display")
                    .font(DesignTokens.Typography.sectionHeader)
                Text("Video is the source frame rate. Requested is a preference submitted to the system, "
                    + "not confirmation of a mode switch. DisplayLink measures app display updates, "
                    + "not the physical panel refresh rate. Verify the panel’s current refresh rate "
                    + "using the Display timeline in Apple Instruments; DisplayLink alone does not "
                    + "confirm whether the requested display mode was applied.")
                Text("Playback")
                    .font(DesignTokens.Typography.sectionHeader)
                Text("Enqueued counts video samples sent to the renderer each second. Dropped is the current video renderer’s cumulative count; replacing the renderer can reset it. Buffer is queued source data.")
                Text("App performance")
                    .font(DesignTokens.Typography.sectionHeader)
                Text("Memory is the app footprint. Scene updates measures RealityKit updates. "
                    + "Main-thread stall is the longest delay in the sampling interval. "
                    + "Detailed metrics add memory categories and queued video frames.")
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
                title: "Request Video Refresh Rate",
                systemName: "display",
                supportingText: "Request a display mode matching the video. Disable to compare system defaults.",
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
                title: "Detailed Metrics",
                systemName: "list.bullet",
                supportingText: "Include memory categories and queued video frames.",
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
                title: "Performance Overlay",
                systemName: "gauge.with.dots.needle.bottom.50percent",
                supportingText: "Video and display, playback, and app performance in separate rows.",
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
                title: "Resume Playback",
                systemName: "play.circle",
                accessory: .menu(title: resumeTitle, options: [
                    SettingListGroup.MenuOption("Ask Every Time", id: "askEveryTime") { setResume(.askEveryTime) },
                    SettingListGroup.MenuOption("Always Resume", id: "alwaysResume") { setResume(.alwaysResume) },
                    SettingListGroup.MenuOption("Always Start Over", id: "alwaysStartFromBeginning") { setResume(.alwaysStartFromBeginning) }
                ])
            ),
            SettingListGroup.Item(
                id: "end-behavior",
                title: "End of Playback",
                systemName: "flag.checkered",
                accessory: .menu(title: endBehaviorTitle, options: [
                    SettingListGroup.MenuOption("Replay", id: "repeatOne") { setEnd(.repeatOne) },
                    SettingListGroup.MenuOption("Play Next", id: "playNext") { setEnd(.playNext) }
                ])
            ),
            SettingListGroup.Item(
                id: "default-speed",
                title: "Default Speed",
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
                title: "Controls Auto-Hide",
                systemName: "timer",
                accessory: .menu(title: autoHideTitle, options: [
                    SettingListGroup.MenuOption("5 Seconds", id: "5") { setAutoHide(5) },
                    SettingListGroup.MenuOption("8 Seconds", id: "8") { setAutoHide(8) },
                    SettingListGroup.MenuOption("15 Seconds", id: "15") { setAutoHide(15) },
                    SettingListGroup.MenuOption("Never", id: "never") { setAutoHide(0) }
                ])
            ),
            SettingListGroup.Item(
                id: "surroundings-dimming",
                title: "Dim Surroundings",
                systemName: "circle.lefthalf.filled",
                supportingText: "Darken the room around the player window and around"
                    + " environments that request it, without touching the video.",
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
                title: "Artwork Cache",
                systemName: "photo.stack",
                accessory: .valueAction(
                    value: ByteCountFormatter.string(fromByteCount: artworkUsageInBytes, countStyle: .file),
                    actionTitle: "Clear",
                    feedback: "Cleared",
                    action: clearArtworkCache
                )
            ),
            SettingListGroup.Item(
                id: "clear-container-index-cache",
                title: "Container Index Cache",
                systemName: "shippingbox",
                accessory: .valueAction(
                    value: ByteCountFormatter.string(
                        fromByteCount: containerIndexUsageInBytes,
                        countStyle: .file
                    ),
                    actionTitle: "Clear",
                    feedback: "Cleared",
                    action: clearContainerIndexCache
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
        playbackLauncher.refreshEndedContinuation()
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
