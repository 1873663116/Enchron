import SwiftUI

struct SettingsPage: View {
    var body: some View {
        MainWindowPage(selectedTab: .settings)
            .accessibilityIdentifier("DesignComps-SettingsPage")
            .accessibilityLabel("Settings page")
    }
}

struct SettingsDetailSectionView: View {
    let section: SettingsSection
    /// Confirmation is owned by the page-level container (see
    /// `SettingsDetailContentView`) and presented from a single root `.alert`,
    /// mirroring `SettingListGroupPreview` in ContentView. A section only
    /// *requests* a confirmation; it never hosts the alert itself, so toggling
    /// presentation no longer rebuilds this section's `SettingListGroup`.
    let onRequestConfirmation: (_ title: String, _ message: String, _ actionTitle: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(section.title)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(.primary)

            SettingListGroup(
                accessibilityIdentifier: "DesignComps-SettingsSection-\(section.id)",
                items: section.items.map(listItem(for:))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Maps a comps `SettingsItem` onto the shared `SettingListGroup` component.
    /// Options and their semantics are preserved; only presentation changes.
    private func listItem(for item: SettingsItem) -> SettingListGroup.Item {
        switch item.control {
        case .selection(let config):
            return SettingListGroup.Item(
                id: item.id,
                title: item.title,
                systemName: item.systemName,
                accessory: .menu(
                    title: config.value,
                    options: config.options.map { SettingListGroup.MenuOption($0) }
                )
            )

        case .toggle(let config):
            return SettingListGroup.Item(
                id: item.id,
                title: item.title,
                systemName: item.systemName,
                accessory: .toggle(isOn: config.isOn)
            )

        case .action(let config):
            return SettingListGroup.Item(
                id: item.id,
                title: item.title,
                systemName: item.systemName,
                accessory: .action(
                    title: config.title,
                    feedback: config.feedback,
                    systemName: nil,
                    role: .normal,
                    action: {}
                )
            )

        case .destructive(let config):
            return SettingListGroup.Item(
                id: item.id,
                title: item.title,
                systemName: item.systemName,
                accessory: .action(
                    title: config.actionTitle,
                    feedback: nil,
                    systemName: nil,
                    role: .destructive,
                    action: {
                        requestConfirmation(
                            title: config.confirmationTitle,
                            message: config.confirmationMessage,
                            actionTitle: config.actionTitle
                        )
                    }
                )
            )

        case .destructiveOptions(let config):
            return SettingListGroup.Item(
                id: item.id,
                title: item.title,
                systemName: item.systemName,
                accessory: .menu(
                    title: config.value,
                    options: config.options.map { option in
                        SettingListGroup.MenuOption(option, role: .destructive) {
                            requestConfirmation(
                                title: "\(option)?",
                                message: config.confirmationMessage,
                                actionTitle: option
                            )
                        }
                    },
                    role: .destructive
                )
            )

        case .readOnly(let config):
            if let actionTitle = config.actionTitle {
                return SettingListGroup.Item(
                    id: item.id,
                    title: item.title,
                    systemName: item.systemName,
                    accessory: .valueAction(
                        value: config.value,
                        actionTitle: actionTitle,
                        feedback: config.feedback,
                        action: {}
                    )
                )
            } else {
                return SettingListGroup.Item(
                    id: item.id,
                    title: item.title,
                    systemName: item.systemName,
                    accessory: .value(config.value)
                )
            }

        case .disclosure(let rows):
            return SettingListGroup.Item(
                id: item.id,
                title: item.title,
                systemName: item.systemName,
                keyValueDetail: rows.map { SettingListGroup.KeyValue(key: $0.key, value: $0.value) },
                accessory: .automatic
            )
        }
    }

    private func requestConfirmation(title: String, message: String, actionTitle: String) {
        onRequestConfirmation(title, message, actionTitle)
    }
}

/// Owns the single confirmation state for a settings category and presents it
/// from one root `.alert`, then fans the requester out to every section. This
/// matches ContentView's `SettingListGroupPreview`, which hosts a single
/// `showClearCacheConfirm` at the page root rather than per-row state.
struct SettingsDetailContentView: View {
    let category: SettingsCategory

    @State private var pendingConfirmation = SettingsPendingConfirmation.empty
    @State private var showsConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(category.title)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.white)

                Text(category.summary)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                ForEach(category.sections) { section in
                    SettingsDetailSectionView(
                        section: section,
                        onRequestConfirmation: requestConfirmation
                    )
                }
            }
        }
        .enchronDestructiveConfirmation(
            pendingConfirmation.title,
            message: pendingConfirmation.message,
            confirmTitle: pendingConfirmation.actionTitle,
            isPresented: $showsConfirmation,
            onConfirm: {}
        )
    }

    private func requestConfirmation(title: String, message: String, actionTitle: String) {
        pendingConfirmation = SettingsPendingConfirmation(
            title: title,
            message: message,
            actionTitle: actionTitle
        )
        showsConfirmation = true
    }
}

private struct SettingsPendingConfirmation {
    let title: String
    let message: String
    let actionTitle: String

    static let empty = SettingsPendingConfirmation(title: "", message: "", actionTitle: "")
}

struct SettingsSection: Identifiable {
    let id: String
    let title: String
    let items: [SettingsItem]
}

struct SettingsItem: Identifiable {
    let id: String
    let title: String
    let systemName: String
    let control: SettingsControl
}

enum SettingsControl {
    case selection(SettingsSelectionControl)
    case toggle(SettingsToggleControl)
    case action(SettingsActionControl)
    case destructive(SettingsDestructiveControl)
    case destructiveOptions(SettingsDestructiveOptionsControl)
    case readOnly(SettingsReadOnlyControl)
    case disclosure([SettingsKeyValue])
}

struct SettingsSelectionControl {
    let value: String
    let options: [String]
}

struct SettingsToggleControl {
    let isOn: Bool
}

struct SettingsActionControl {
    let title: String
    let feedback: String
}

struct SettingsDestructiveControl {
    let actionTitle: String
    let confirmationTitle: String
    let confirmationMessage: String
    let feedback: String
}

struct SettingsDestructiveOptionsControl {
    let value: String
    let options: [String]
    let confirmationMessage: String
    let feedback: String
}

struct SettingsReadOnlyControl {
    let value: String
    let actionTitle: String?
    let feedback: String
}

struct SettingsKeyValue: Identifiable {
    let key: String
    let value: String

    var id: String {
        "\(key)-\(value)"
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case playback
    case spatialContent
    case storagePrivacy
    case advanced
    case about

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .playback:
            "Playback"
        case .spatialContent:
            "Spatial Content"
        case .storagePrivacy:
            "Storage & Privacy"
        case .advanced:
            "Advanced"
        case .about:
            "About"
        }
    }

    var summary: String {
        switch self {
        case .playback:
            "Resume behavior, end behavior, and control timing"
        case .spatialContent:
            "Default scenes and immersive entry for spatial media"
        case .storagePrivacy:
            "Cache visibility, cleanup, history, and privacy notes"
        case .advanced:
            "Diagnostics, labs, inspectors, and TestFlight tools"
        case .about:
            "Version, licenses, support, and feedback"
        }
    }

    var icon: String {
        switch self {
        case .playback:
            "play.circle.fill"
        case .spatialContent:
            "visionpro.fill"
        case .storagePrivacy:
            "internaldrive.fill"
        case .advanced:
            "slider.horizontal.3"
        case .about:
            "info.circle.fill"
        }
    }

    var sections: [SettingsSection] {
        switch self {
        case .playback:
            [
                SettingsSection(
                    id: "playback-behavior",
                    title: "Playback Behavior",
                    items: [
                        SettingsItem(
                            id: "resume-strategy",
                            title: "Resume Playback",
                            systemName: "play.circle",
                            control: .selection(.init(
                                value: "Ask Every Time",
                                options: ["Ask Every Time", "Always Resume", "Always Start Over"]
                            ))
                        ),
                        SettingsItem(
                            id: "end-behavior",
                            title: "End of Playback",
                            systemName: "flag.checkered",
                            control: .selection(.init(
                                value: "Stop",
                                options: ["Stop", "Loop Single Episode", "Play Next"]
                            ))
                        ),
                        SettingsItem(
                            id: "controls-auto-hide",
                            title: "Controls Auto-Hide",
                            systemName: "timer",
                            control: .selection(.init(
                                value: "8 Seconds",
                                options: ["5 Seconds", "8 Seconds", "15 Seconds"]
                            ))
                        )
                    ]
                )
            ]

        case .spatialContent:
            [
                SettingsSection(
                    id: "spatial-defaults",
                    title: "Spatial Content",
                    items: [
                        SettingsItem(
                            id: "default-scene",
                            title: "Default Scene",
                            systemName: "mountain.2",
                            control: .selection(.init(
                                value: "Dark Cinema",
                                options: ["Dark Cinema", "Starry Night", "Nature Sunset"]
                            ))
                        ),
                        SettingsItem(
                            id: "enter-immersive",
                            title: "Enter Immersion for Spatial Content",
                            systemName: "visionpro",
                            control: .selection(.init(
                                value: "Ask Every Time",
                                options: ["Off", "Ask Every Time", "Auto Enter"]
                            ))
                        )
                    ]
                )
            ]

        case .storagePrivacy:
            [
                SettingsSection(
                    id: "storage-cache",
                    title: "Cache",
                    items: [
                        SettingsItem(
                            id: "cache-size",
                            title: "Cache Size",
                            systemName: "internaldrive",
                            control: .readOnly(.init(
                                value: "1.8 GB",
                                actionTitle: nil,
                                feedback: ""
                            ))
                        ),
                        SettingsItem(
                            id: "clear-cache",
                            title: "Clear Cache",
                            systemName: "trash",
                            control: .destructive(.init(
                                actionTitle: "Clear",
                                confirmationTitle: "Clear App Cache?",
                                confirmationMessage: "This removes thumbnails and temporary cache. It does not delete video files or playback history.",
                                feedback: "Cleared"
                            ))
                        )
                    ]
                ),
                SettingsSection(
                    id: "privacy-history",
                    title: "Privacy & History",
                    items: [
                        SettingsItem(
                            id: "clear-history",
                            title: "Clear Recent Playback & Progress",
                            systemName: "clock.arrow.circlepath",
                            control: .destructiveOptions(.init(
                                value: "Choose Scope",
                                options: ["Clear All", "Clear Before 30 Days", "Clear Before 90 Days"],
                                confirmationMessage: "This clears local recent playback and resume progress. It does not delete media files or remove remote sources.",
                                feedback: "Cleared"
                            ))
                        ),
                        SettingsItem(
                            id: "privacy-note",
                            title: "Privacy Notice",
                            systemName: "lock.shield",
                            control: .disclosure([
                                .init(key: "Local Files", value: "Selected file access stays on device."),
                                .init(key: "Photos", value: "Permission is used only for media the user chooses."),
                                .init(key: "Remote Credentials", value: "Connection secrets stay in the credential store."),
                                .init(key: "Diagnostics", value: "Logs are local unless the user exports them.")
                            ])
                        )
                    ]
                )
            ]

        case .advanced:
            [
                SettingsSection(
                    id: "advanced-diagnostics",
                    title: "Diagnostic Export",
                    items: [
                        SettingsItem(
                            id: "copy-diagnostic-summary",
                            title: "Copy Diagnostic Summary",
                            systemName: "doc.on.doc",
                            control: .action(.init(title: "Copy", feedback: "Copied"))
                        ),
                        SettingsItem(
                            id: "export-diagnostic-package",
                            title: "Export Diagnostic Package",
                            systemName: "square.and.arrow.up",
                            control: .action(.init(title: "Export", feedback: "Queued"))
                        ),
                        SettingsItem(
                            id: "redaction-preview",
                            title: "Redaction Preview",
                            systemName: "eye.slash",
                            control: .disclosure([
                                .init(key: "Path", value: "/Users/.../Movies/..."),
                                .init(key: "Host", value: "nas-87f2.local"),
                                .init(key: "User", value: "u***"),
                                .init(key: "Token", value: "token-...-redacted")
                            ])
                        )
                    ]
                ),
                SettingsSection(
                    id: "advanced-logs",
                    title: "Logs",
                    items: [
                        SettingsItem(
                            id: "log-level",
                            title: "Log Level",
                            systemName: "list.bullet.rectangle",
                            control: .selection(.init(
                                value: "Info",
                                options: ["Off", "Error", "Info", "Verbose"]
                            ))
                        ),
                        SettingsItem(
                            id: "clear-logs",
                            title: "Clear Logs",
                            systemName: "trash",
                            control: .destructive(.init(
                                actionTitle: "Clear",
                                confirmationTitle: "Clear Local Logs?",
                                confirmationMessage: "This removes local diagnostic logs. It does not change playback history or media files.",
                                feedback: "Cleared"
                            ))
                        ),
                        SettingsItem(
                            id: "verbose-auto-off",
                            title: "Verbose Auto-Off",
                            systemName: "timer",
                            control: .selection(.init(
                                value: "30 Minutes",
                                options: ["Next Launch", "30 Minutes"]
                            ))
                        )
                    ]
                ),
                SettingsSection(
                    id: "advanced-rendering",
                    title: "Playback Engine & Rendering",
                    items: [
                        SettingsItem(
                            id: "route-snapshot",
                            title: "Current Route Snapshot",
                            systemName: "cpu",
                            control: .disclosure([
                                .init(key: "Engine Route", value: "mpv -> Metal texture bridge"),
                                .init(key: "Surface", value: "WindowGroup playback surface"),
                                .init(key: "Pixel Format", value: "rgba16Float"),
                                .init(key: "Colorspace", value: "Display P3"),
                                .init(key: "EDR", value: "Available, inactive")
                            ])
                        ),
                        SettingsItem(
                            id: "engine-reference",
                            title: "mpv / Apple Reference Comparison",
                            systemName: "arrow.left.arrow.right",
                            control: .selection(.init(
                                value: "Current Route",
                                options: ["Current Route", "mpv Session", "Apple Reference Session"]
                            ))
                        ),
                        SettingsItem(
                            id: "reset-engine-overrides",
                            title: "Reset All Engine Overrides",
                            systemName: "arrow.counterclockwise",
                            control: .destructive(.init(
                                actionTitle: "Reset",
                                confirmationTitle: "Reset Engine Overrides?",
                                confirmationMessage: "This returns playback diagnostics to a clean session state.",
                                feedback: "Reset"
                            ))
                        ),
                        SettingsItem(
                            id: "safe-mpv-preset",
                            title: "Safe mpv Test Preset",
                            systemName: "slider.horizontal.3",
                            control: .selection(.init(
                                value: "Default",
                                options: ["Default", "Compatibility First", "HDR Experiment", "Conservative"]
                            ))
                        )
                    ]
                ),
                SettingsSection(
                    id: "advanced-media-inspector",
                    title: "Media Inspector",
                    items: [
                        SettingsItem(
                            id: "current-media-inspector",
                            title: "Current Media Inspector",
                            systemName: "info.circle",
                            control: .disclosure([
                                .init(key: "Codec", value: "HEVC Main10"),
                                .init(key: "Resolution", value: "3840 x 2160"),
                                .init(key: "FPS", value: "23.976"),
                                .init(key: "HDR", value: "HDR10 metadata detected"),
                                .init(key: "Projection", value: "Flat"),
                                .init(key: "Stereo", value: "Mono"),
                                .init(key: "Source", value: "Runtime detection")
                            ])
                        ),
                        SettingsItem(
                            id: "copy-media-summary",
                            title: "Copy Media Summary",
                            systemName: "doc.on.doc",
                            control: .action(.init(title: "Copy", feedback: "Copied"))
                        ),
                        SettingsItem(
                            id: "redetect-media",
                            title: "Re-detect Current Media",
                            systemName: "arrow.clockwise",
                            control: .action(.init(title: "Run", feedback: "Queued"))
                        ),
                        SettingsItem(
                            id: "clear-current-media-cache",
                            title: "Clear Current Media Profile Cache",
                            systemName: "trash",
                            control: .destructive(.init(
                                actionTitle: "Clear",
                                confirmationTitle: "Clear Current Media Profile?",
                                confirmationMessage: "Only the current media profile cache is removed.",
                                feedback: "Cleared"
                            ))
                        ),
                        SettingsItem(
                            id: "clear-all-media-cache",
                            title: "Clear All Media Info Cache",
                            systemName: "arrow.triangle.2.circlepath",
                            control: .destructive(.init(
                                actionTitle: "Rebuild",
                                confirmationTitle: "Rebuild All Media Info?",
                                confirmationMessage: "All cached media profiles will be rebuilt as media is opened again.",
                                feedback: "Queued"
                            ))
                        )
                    ]
                ),
                SettingsSection(
                    id: "advanced-hdr-edr",
                    title: "HDR / EDR Lab",
                    items: [
                        SettingsItem(
                            id: "hdr-edr-state",
                            title: "HDR / EDR Status Panel",
                            systemName: "sun.max",
                            control: .disclosure([
                                .init(key: "Output Mode", value: "System managed"),
                                .init(key: "Layer Format", value: "rgba16Float"),
                                .init(key: "Colorspace", value: "extendedLinearDisplayP3"),
                                .init(key: "wantsEDR", value: "true")
                            ])
                        ),
                        SettingsItem(
                            id: "sample-hdr-frame",
                            title: "Sample Current Frame HDR Data",
                            systemName: "eyedropper",
                            control: .action(.init(title: "Sample", feedback: "Queued"))
                        ),
                        SettingsItem(
                            id: "hdr-session-comparison",
                            title: "HDR On / Off Session Comparison",
                            systemName: "circle.lefthalf.filled",
                            control: .selection(.init(
                                value: "HDR On",
                                options: ["HDR On", "HDR Off"]
                            ))
                        ),
                        SettingsItem(
                            id: "hdr-reference-comparison",
                            title: "mpv / Apple Reference HDR Comparison",
                            systemName: "arrow.left.arrow.right",
                            control: .selection(.init(
                                value: "mpv Route",
                                options: ["mpv Route", "Apple Reference"]
                            ))
                        ),
                        SettingsItem(
                            id: "copy-hdr-summary",
                            title: "Copy HDR Diagnostic Summary",
                            systemName: "doc.on.doc",
                            control: .action(.init(title: "Copy", feedback: "Copied"))
                        )
                    ]
                ),
                SettingsSection(
                    id: "advanced-immersive-state",
                    title: "Immersive State",
                    items: [
                        SettingsItem(
                            id: "immersive-inspector",
                            title: "Immersive State Inspector",
                            systemName: "cube.transparent",
                            control: .disclosure([
                                .init(key: "Space", value: "closed"),
                                .init(key: "Playback Mode", value: "Window"),
                                .init(key: "Projection Override", value: "none"),
                                .init(key: "Stereo Override", value: "none"),
                                .init(key: "Environment", value: "Dark Cinema")
                            ])
                        ),
                        SettingsItem(
                            id: "immersive-open-close-test",
                            title: "Immersive Space Open / Close Test",
                            systemName: "visionpro",
                            control: .selection(.init(
                                value: "No Test",
                                options: ["No Test", "Request Open", "Request Close"]
                            ))
                        ),
                        SettingsItem(
                            id: "reset-scene-position",
                            title: "Reset Scene Screen Position",
                            systemName: "arrow.counterclockwise",
                            control: .destructiveOptions(.init(
                                value: "Choose Scope",
                                options: ["Reset Current Scene", "Reset All Scenes"],
                                confirmationMessage: "This resets saved screen placement. Playback files and sources are not changed.",
                                feedback: "Reset"
                            ))
                        ),
                        SettingsItem(
                            id: "spatial-classification",
                            title: "Current Spatial Content Classification",
                            systemName: "tag",
                            control: .disclosure([
                                .init(key: "Detected Type", value: "flat"),
                                .init(key: "Projection", value: "none"),
                                .init(key: "Stereo", value: "none"),
                                .init(key: "Auto Immersion", value: "not eligible")
                            ])
                        )
                    ]
                ),
                SettingsSection(
                    id: "advanced-network-sources",
                    title: "Network & Sources",
                    items: [
                        SettingsItem(
                            id: "remote-source-test",
                            title: "Remote Source Connection Test",
                            systemName: "network",
                            control: .action(.init(title: "Test", feedback: "Queued"))
                        ),
                        SettingsItem(
                            id: "reconnect-current-source",
                            title: "Reconnect Current Source",
                            systemName: "arrow.clockwise",
                            control: .action(.init(title: "Reconnect", feedback: "Queued"))
                        ),
                        SettingsItem(
                            id: "source-error-summary",
                            title: "Source Error Summary",
                            systemName: "exclamationmark.triangle",
                            control: .disclosure([
                                .init(key: "Code", value: "none"),
                                .init(key: "Duration", value: "0 ms"),
                                .init(key: "Auth", value: "valid"),
                                .init(key: "Host", value: "host-87f2")
                            ])
                        ),
                        SettingsItem(
                            id: "source-read-only-info",
                            title: "Current Source Read-only Info",
                            systemName: "server.rack",
                            control: .disclosure([
                                .init(key: "Type", value: "Local"),
                                .init(key: "Root", value: "~/Movies"),
                                .init(key: "Credential", value: "none")
                            ])
                        )
                    ]
                ),
                SettingsSection(
                    id: "advanced-performance",
                    title: "Performance",
                    items: [
                        SettingsItem(
                            id: "performance-hud",
                            title: "Performance HUD",
                            systemName: "gauge",
                            control: .toggle(.init(isOn: false))
                        ),
                        SettingsItem(
                            id: "performance-report",
                            title: "Sample 30-second Performance Report",
                            systemName: "stopwatch",
                            control: .action(.init(title: "Sample", feedback: "Queued"))
                        ),
                        SettingsItem(
                            id: "controls-never-hide",
                            title: "Controls Never Hide",
                            systemName: "eye",
                            control: .toggle(.init(isOn: false))
                        ),
                        SettingsItem(
                            id: "rendering-load-summary",
                            title: "Current Rendering Load Summary",
                            systemName: "memorychip",
                            control: .disclosure([
                                .init(key: "Resolution", value: "3840 x 2160"),
                                .init(key: "Frame Rate", value: "23.976"),
                                .init(key: "Panorama", value: "false"),
                                .init(key: "HDR", value: "true"),
                                .init(key: "Immersive", value: "false")
                            ])
                        )
                    ]
                )
            ]

        case .about:
            [
                SettingsSection(
                    id: "about-app",
                    title: "App Information",
                    items: [
                        SettingsItem(
                            id: "version-build",
                            title: "Version & Build",
                            systemName: "info.circle",
                            control: .readOnly(.init(
                                value: "0.1.0 (42)",
                                actionTitle: "Copy",
                                feedback: "Copied"
                            ))
                        ),
                        SettingsItem(
                            id: "licenses",
                            title: "Open-source Licenses",
                            systemName: "doc.text",
                            control: .action(.init(title: "View", feedback: "Opened"))
                        ),
                        SettingsItem(
                            id: "support-feedback",
                            title: "Support & Feedback",
                            systemName: "questionmark.circle",
                            control: .selection(.init(
                                value: "Contact Support",
                                options: ["Contact Support", "Copy Diagnostic Summary"]
                            ))
                        )
                    ]
                )
            ]
        }
    }
}

#Preview("Settings", windowStyle: .automatic) {
    SettingsPage()
        .frame(
            width: EmptyPanelWindowContent<EmptyView>.defaultArtboardSize.width,
            height: EmptyPanelWindowContent<EmptyView>.defaultArtboardSize.height
        )
}
