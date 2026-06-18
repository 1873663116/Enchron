import SwiftUI
import UIKit

/// The app's Settings screen, assembled from the shared component library
/// (`CategorySidebar` + `SettingListGroup`) and bound two-way to persisted
/// `UserPreferences` via `SettingsViewModel`. Replaces the retired `SettingsView`.
///
/// Scope note: this binds the persistent core settings (Playback / Spatial /
/// Diagnostics / About). The polished design's full diagnostics + storage long
/// tail (cache actions, disclosures, inspectors) is not yet bound.
struct SettingsScreen: View {
    @State private var viewModel: SettingsViewModel
    @State private var selectedCategoryID: String = Category.playback.rawValue
    @State private var pendingDestructive: DestructiveAction?

    /// Destructive long-tail actions that require an explicit confirm (SET-21/24).
    /// On a fake backend the confirm path is a no-op + transient feedback; the
    /// dialog itself is the polished, honest UX.
    private enum DestructiveAction: Identifiable {
        case clearLogs, resetEngineOverrides
        var id: String { String(describing: self) }
        var title: String {
            switch self {
            case .clearLogs: "Clear Logs?"
            case .resetEngineOverrides: "Reset All Engine Overrides?"
            }
        }
        var message: String {
            switch self {
            case .clearLogs: "Removes captured diagnostic logs. Media and sources are not affected."
            case .resetEngineOverrides: "Restores mpv/libplacebo overrides to defaults. Media and sources are not affected."
            }
        }
        var confirmTitle: String {
            switch self {
            case .clearLogs: "Clear Logs"
            case .resetEngineOverrides: "Reset Overrides"
            }
        }
    }

    init(store: PreferencesStoring = UserDefaultsStore()) {
        _viewModel = State(initialValue: SettingsViewModel(store: store))
    }

    private enum Category: String, CaseIterable {
        case playback, spatial, diagnostics, about

        var title: String {
            switch self {
            case .playback: "Playback"
            case .spatial: "Spatial Content"
            case .diagnostics: "Diagnostics & Tools"
            case .about: "About"
            }
        }

        var summary: String {
            switch self {
            case .playback: "Resume behavior, end behavior, and control timing"
            case .spatial: "Default environments and immersive entry for spatial media"
            case .diagnostics: "Logs and performance overlays"
            case .about: "Version, support, and feedback"
            }
        }

        var icon: String {
            switch self {
            case .playback: "play.circle.fill"
            case .spatial: "visionpro.fill"
            case .diagnostics: "slider.horizontal.3"
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
        .confirmationDialog(
            pendingDestructive?.title ?? "",
            isPresented: Binding(
                get: { pendingDestructive != nil },
                set: { if !$0 { pendingDestructive = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDestructive
        ) { action in
            Button(action.confirmTitle, role: .destructive) { pendingDestructive = nil }
            Button("Cancel", role: .cancel) { pendingDestructive = nil }
        } message: { action in
            Text(action.message)
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
        case .diagnostics:
            SettingListGroup(accessibilityIdentifier: "Settings-Diagnostics-group", items: diagnosticsItems)
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
                accessory: .menu(title: environmentTitle, options: environmentOptions.map { name in
                    SettingListGroup.MenuOption(name) { viewModel.update { $0.defaultEnvironmentID = name } }
                })
            ),
            SettingListGroup.Item(
                id: "enter-immersive",
                title: "Enter Immersion for Spatial Content",
                systemName: "visionpro",
                accessory: .menu(title: viewModel.preferences.entersImmersionForSpatialContent ? "On" : "Off", options: [
                    SettingListGroup.MenuOption("Off") { viewModel.update { $0.entersImmersionForSpatialContent = false } },
                    SettingListGroup.MenuOption("On") { viewModel.update { $0.entersImmersionForSpatialContent = true } }
                ])
            )
        ]
    }

    // MARK: - Diagnostics

    private var diagnosticsItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "log-level",
                title: "Log Level",
                systemName: "list.bullet.rectangle",
                accessory: .menu(title: logLevelTitle, options: PersistenceDomain.LogLevel.allCases.map { level in
                    SettingListGroup.MenuOption(logLevelLabel(level)) { viewModel.update { $0.logLevel = level } }
                })
            ),
            SettingListGroup.Item(
                id: "performance-hud",
                title: "Performance HUD",
                systemName: "gauge",
                accessory: .boundToggle(
                    isOn: Binding(
                        get: { viewModel.preferences.showsPerformanceHUD },
                        set: { value in viewModel.update { $0.showsPerformanceHUD = value } }
                    ),
                    isEnabled: true,
                    marker: nil
                )
            ),
            SettingListGroup.Item(
                id: "verbose-auto-off",
                title: "Verbose Auto-Off",
                systemName: "timer",
                accessory: .menu(title: verboseAutoOffTitle, options: [
                    SettingListGroup.MenuOption("Next Launch") { viewModel.update { $0.verboseAutoOff = .nextLaunch } },
                    SettingListGroup.MenuOption("30 Minutes") { viewModel.update { $0.verboseAutoOff = .thirtyMinutes } }
                ])
            ),
            // SET-20: read-only diagnostic disclosures.
            SettingListGroup.Item(
                id: "route-snapshot",
                title: "Route Snapshot",
                systemName: "point.topleft.down.to.point.bottomright.curvepath",
                keyValueDetail: [
                    .init(key: "Playback Mode", value: "Window"),
                    .init(key: "Immersive Space", value: "Closed"),
                    .init(key: "Active Source", value: "Local (fake catalog)")
                ]
            ),
            SettingListGroup.Item(
                id: "media-inspector",
                title: "Media Inspector",
                systemName: "waveform.and.magnifyingglass",
                keyValueDetail: [
                    .init(key: "Backend", value: "FakePlaybackSource"),
                    .init(key: "Resolution", value: "1920×1080"),
                    .init(key: "Codec", value: "h264 (simulated)")
                ]
            ),
            // SET-24: destructive action gated by a confirm dialog.
            SettingListGroup.Item(
                id: "clear-logs",
                title: "Clear Logs",
                systemName: "trash",
                accessory: .action(title: "Clear", feedback: "Cleared", systemName: nil, role: .destructive, action: { pendingDestructive = .clearLogs })
            ),
            // SET-21: reset engine overrides, also confirm-gated.
            SettingListGroup.Item(
                id: "reset-overrides",
                title: "Reset All Engine Overrides",
                systemName: "arrow.counterclockwise",
                accessory: .action(title: "Reset", feedback: nil, systemName: nil, role: .destructive, action: { pendingDestructive = .resetEngineOverrides })
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
            // SET-08: cache size — Empty on the fake backend (no real cache yet).
            SettingListGroup.Item(
                id: "storage-cache",
                title: "Storage",
                systemName: "internaldrive",
                accessory: .value("Empty")
            ),
            // SET-17: privacy disclosure (four data categories).
            SettingListGroup.Item(
                id: "privacy-notice",
                title: "Privacy Notice",
                systemName: "hand.raised",
                keyValueDetail: [
                    .init(key: "Local Files", value: "On device only"),
                    .init(key: "Photos", value: "Read on request"),
                    .init(key: "Remote Credentials", value: "Keychain, never synced"),
                    .init(key: "Diagnostics", value: "Stay on device")
                ]
            ),
            // SET-18: open-source licenses entry.
            SettingListGroup.Item(
                id: "licenses",
                title: "Open-source Licenses",
                systemName: "doc.text",
                accessory: .action(title: "View", feedback: "Opening…", systemName: nil, role: .normal, action: {})
            )
        ]
    }

    // MARK: - Value mappings

    private func setResume(_ value: PersistenceDomain.ResumePolicy) { viewModel.update { $0.resumePolicy = value } }
    private func setEnd(_ value: PersistenceDomain.PlaybackEndBehavior) { viewModel.update { $0.playbackEndBehavior = value } }
    private func setAutoHide(_ seconds: Int) { viewModel.update { $0.controlsAutoHideSeconds = seconds } }

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

    private let environmentOptions = ["Dark Cinema", "Starry Night", "Nature Sunset"]
    private var environmentTitle: String {
        viewModel.preferences.defaultEnvironmentID ?? "Dark Cinema"
    }

    private func logLevelLabel(_ level: PersistenceDomain.LogLevel) -> String {
        switch level {
        case .off: "Off"
        case .error: "Error"
        case .info: "Info"
        case .verbose: "Verbose"
        }
    }
    private var logLevelTitle: String { logLevelLabel(viewModel.preferences.logLevel) }

    private var verboseAutoOffTitle: String {
        switch viewModel.preferences.verboseAutoOff {
        case .nextLaunch: "Next Launch"
        case .thirtyMinutes: "30 Minutes"
        }
    }

    private let feedbackEmail = "feedback@enchron.app"
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    private func copy(_ string: String) {
        UIPasteboard.general.string = string
    }
}
