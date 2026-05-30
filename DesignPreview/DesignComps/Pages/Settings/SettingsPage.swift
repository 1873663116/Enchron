import SwiftUI

struct SettingsPage: View {
    var body: some View {
        MainWindowPage(selectedTab: .settings)
            .accessibilityIdentifier("DesignComps-SettingsPage")
            .accessibilityLabel("Settings page")
    }
}

struct SettingsDetailRow: View {
    let item: SettingsItem
    let showsDivider: Bool

    @State private var selectedValue: String
    @State private var isOn: Bool
    @State private var isExpanded = false
    @State private var statusText = ""
    @State private var showsConfirmation = false
    @State private var confirmation = SettingsConfirmation.empty

    init(item: SettingsItem, showsDivider: Bool) {
        self.item = item
        self.showsDivider = showsDivider
        _selectedValue = State(initialValue: item.control.initialSelection)
        _isOn = State(initialValue: item.control.initialToggleState)
    }

    var body: some View {
        rowControl
            .confirmationDialog(
                confirmation.title,
                isPresented: $showsConfirmation,
                titleVisibility: .visible
            ) {
                Button(confirmation.actionTitle, role: .destructive) {
                    showStatus(confirmation.feedback)
                }
                Button("Cancel") {
                    showsConfirmation = false
                }
            } message: {
                Text(confirmation.message)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("DesignComps-SettingsPage-detail-\(item.id)")
    }

    @ViewBuilder
    private var rowControl: some View {
        switch item.control {
        case .selection(let config):
            rowSurface {
                Menu {
                    ForEach(config.options, id: \.self) { option in
                        Button {
                            selectedValue = option
                        } label: {
                            Label(option, systemImage: option == selectedValue ? "checkmark" : "")
                        }
                    }
                } label: {
                    SettingsSelectionChip(title: selectedValue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            } expanded: {
                EmptyView()
            }

        case .toggle:
            rowSurface {
                SettingsAccessoryButton(accessibilityLabel: item.title) {
                    withAnimation(DesignTokens.AnimationToken.selection) {
                        isOn.toggle()
                    }
                } label: {
                    SettingsToggleIndicator(isOn: isOn)
                }
            } expanded: {
                EmptyView()
            }

        case .action(let config):
            rowSurface {
                SettingsAccessoryButton(accessibilityLabel: item.title) {
                    showStatus(config.feedback)
                } label: {
                    SettingsActionChip(title: statusText.isEmpty ? config.title : statusText)
                }
            } expanded: {
                EmptyView()
            }

        case .destructive(let config):
            rowSurface {
                SettingsAccessoryButton(accessibilityLabel: item.title) {
                    confirmation = SettingsConfirmation(
                        title: config.confirmationTitle,
                        message: config.confirmationMessage,
                        actionTitle: config.actionTitle,
                        feedback: config.feedback
                    )
                    showsConfirmation = true
                } label: {
                    SettingsActionChip(title: config.actionTitle, role: .destructive)
                }
            } expanded: {
                EmptyView()
            }

        case .destructiveOptions(let config):
            rowSurface {
                Menu {
                    ForEach(config.options, id: \.self) { option in
                        Button(option, role: .destructive) {
                            selectedValue = option
                            confirmation = SettingsConfirmation(
                                title: "\(option)?",
                                message: config.confirmationMessage,
                                actionTitle: option,
                                feedback: config.feedback
                            )
                            showsConfirmation = true
                        }
                    }
                } label: {
                    SettingsSelectionChip(title: selectedValue, role: .destructive)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            } expanded: {
                EmptyView()
            }

        case .readOnly(let config):
            if let actionTitle = config.actionTitle {
                rowSurface {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        SettingsValueText(statusText.isEmpty ? config.value : statusText)
                        SettingsAccessoryButton(accessibilityLabel: item.title) {
                            showStatus(config.feedback)
                        } label: {
                            SettingsActionChip(title: actionTitle)
                        }
                    }
                } expanded: {
                    EmptyView()
                }
            } else {
                rowSurface {
                    SettingsValueText(config.value)
                } expanded: {
                    EmptyView()
                }
            }

        case .disclosure(let rows):
            rowSurface {
                SettingsAccessoryButton(accessibilityLabel: item.title) {
                    toggleExpansion()
                } label: {
                    SettingsDisclosureChip(isExpanded: isExpanded)
                }
            } expanded: {
                if isExpanded {
                    SettingsKeyValueList(rows: rows)
                        .transition(settingsExpansionTransition)
                }
            }
        }
    }

    private var settingsExpansionTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.96, anchor: .topTrailing)
                .combined(with: .opacity)
                .combined(with: .move(edge: .top)),
            removal: .opacity
        )
    }

    private func rowSurface<Trailing: View, Expanded: View>(
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder expanded: () -> Expanded
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(item.title)
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.primary)

                    Text(item.subtitle)
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: 0, alignment: .leading)

                Spacer(minLength: DesignTokens.Spacing.lg)

                trailing()
                    .layoutPriority(1)
            }
            .frame(minHeight: DesignTokens.Interactive.rowHeight)

            expanded()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(DesignTokens.Surface.divider)
                    .frame(height: DesignTokens.Stroke.regular)
                    .padding(.horizontal, DesignTokens.Spacing.md)
            }
        }
        .contentShape(.hoverEffect, DesignTokens.ShapeToken.element)
        .hoverEffect(.highlight)
        .contentShape(DesignTokens.ShapeToken.element)
        .animation(DesignTokens.AnimationToken.selection, value: isExpanded)
    }

    private func toggleExpansion() {
        withAnimation(DesignTokens.AnimationToken.selection) {
            isExpanded.toggle()
        }
    }

    private func showStatus(_ text: String) {
        statusText = text
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            await MainActor.run {
                if statusText == text {
                    statusText = ""
                }
            }
        }
    }
}

struct SettingsDetailSectionView: View {
    let section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(section.title)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    SettingsDetailRow(
                        item: item,
                        showsDivider: index < section.items.count - 1
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .enchronTranslucentListContainer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSelectionChip: View {
    let title: String
    var role: SettingsActionRole = .normal

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Typography.sectionHeader)
                .lineLimit(1)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
        }
        .foregroundStyle(role == .destructive ? .red : DesignTokens.Surface.accessoryText)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .frame(minHeight: DesignTokens.Interactive.compact)
        .background(DesignTokens.Surface.elevated, in: Capsule())
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.highlight)
        .contentShape(Capsule())
    }
}

private struct SettingsActionChip: View {
    let title: String
    var role: SettingsActionRole = .normal

    var body: some View {
        Text(title)
            .font(DesignTokens.Typography.sectionHeader)
            .foregroundStyle(role == .destructive ? .red : DesignTokens.Surface.accessoryText)
            .lineLimit(1)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .frame(minHeight: DesignTokens.Interactive.compact)
            .background(DesignTokens.Surface.elevated, in: Capsule())
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(.highlight)
            .contentShape(Capsule())
    }
}

private struct SettingsAccessoryButton<Label: View>: View {
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(.plain)
        .frame(minHeight: DesignTokens.Interactive.large)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SettingsValueText: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(DesignTokens.Typography.sectionHeader)
            .foregroundStyle(DesignTokens.Surface.accessoryText)
            .lineLimit(1)
    }
}

private struct SettingsDisclosureChip: View {
    let isExpanded: Bool

    var body: some View {
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
            .rotationEffect(isExpanded ? .degrees(90) : .zero)
            .frame(width: DesignTokens.Interactive.compact, height: DesignTokens.Interactive.compact)
            .background(DesignTokens.Surface.elevated, in: Circle())
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.highlight)
            .contentShape(Circle())
    }
}

private struct SettingsToggleIndicator: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? DesignTokens.Theme.accent : DesignTokens.Surface.elevated)
            .frame(width: 50, height: 30)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 26, height: 26)
                    .padding(2)
            }
            .clipShape(Capsule())
            .glassBackgroundEffect(in: Capsule())
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(.highlight)
            .contentShape(Capsule())
    }
}

private struct SettingsKeyValueList: View {
    let rows: [SettingsKeyValue]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Rectangle()
                .fill(DesignTokens.Surface.border)
                .frame(height: DesignTokens.Stroke.subtle)
                .padding(.top, DesignTokens.Spacing.xxs)

            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
                    Text(row.key)
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                        .frame(width: 160, alignment: .leading)

                    Text(row.value)
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Surface.accessoryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.bottom, DesignTokens.Spacing.sm)
    }
}

struct SettingsSection: Identifiable {
    let id: String
    let title: String
    let items: [SettingsItem]
}

struct SettingsItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
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

    var initialSelection: String {
        switch self {
        case .selection(let config):
            config.value
        case .destructiveOptions(let config):
            config.value
        case .toggle, .action, .destructive, .readOnly, .disclosure:
            ""
        }
    }

    var initialToggleState: Bool {
        switch self {
        case .toggle(let config):
            config.isOn
        case .selection, .action, .destructive, .destructiveOptions, .readOnly, .disclosure:
            false
        }
    }
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

private struct SettingsConfirmation {
    let title: String
    let message: String
    let actionTitle: String
    let feedback: String

    static let empty = SettingsConfirmation(
        title: "",
        message: "",
        actionTitle: "",
        feedback: ""
    )
}

private enum SettingsActionRole {
    case normal
    case destructive
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
                            subtitle: "Controls how progress is handled when a video opens again.",
                            control: .selection(.init(
                                value: "Ask Every Time",
                                options: ["Ask Every Time", "Always Resume", "Always Start Over"]
                            ))
                        ),
                        SettingsItem(
                            id: "end-behavior",
                            title: "End of Playback",
                            subtitle: "Choose the next step after the current video ends.",
                            control: .selection(.init(
                                value: "Stop",
                                options: ["Stop", "Loop Single Episode", "Play Next"]
                            ))
                        ),
                        SettingsItem(
                            id: "controls-auto-hide",
                            title: "Controls Auto-Hide",
                            subtitle: "Hide playback controls after a short delay.",
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
                            subtitle: "Scene used when immersive viewing starts.",
                            control: .selection(.init(
                                value: "Dark Cinema",
                                options: ["Dark Cinema", "Starry Night", "Nature Sunset"]
                            ))
                        ),
                        SettingsItem(
                            id: "enter-immersive",
                            title: "Enter Immersion for Spatial Content",
                            subtitle: "Applies to 3D, 180, 360, and future immersive media.",
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
                            subtitle: "App thumbnails, indexes, and temporary playback cache.",
                            control: .readOnly(.init(
                                value: "1.8 GB",
                                actionTitle: nil,
                                feedback: ""
                            ))
                        ),
                        SettingsItem(
                            id: "clear-cache",
                            title: "Clear Cache",
                            subtitle: "Removes App cache without deleting videos or history.",
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
                            subtitle: "Deletes local watch history and resume points.",
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
                            subtitle: "Review local files, photos access, credentials, and logs.",
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
                            subtitle: "App, Build, device, visionOS, route, and media state.",
                            control: .action(.init(title: "Copy", feedback: "Copied"))
                        ),
                        SettingsItem(
                            id: "export-diagnostic-package",
                            title: "Export Diagnostic Package",
                            subtitle: "Logs, recent errors, media, rendering, and cache state.",
                            control: .action(.init(title: "Export", feedback: "Queued"))
                        ),
                        SettingsItem(
                            id: "redaction-preview",
                            title: "Redaction Preview",
                            subtitle: "Shows how paths, hosts, names, tokens, and filenames hide.",
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
                            subtitle: "Temporary logging level for TestFlight diagnostics.",
                            control: .selection(.init(
                                value: "Info",
                                options: ["Off", "Error", "Info", "Verbose"]
                            ))
                        ),
                        SettingsItem(
                            id: "clear-logs",
                            title: "Clear Logs",
                            subtitle: "Clears local diagnostic logs before reproducing an issue.",
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
                            subtitle: "Prevents long-running verbose logging.",
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
                            subtitle: "Shows the actual engine, surface, pixel format, and EDR state.",
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
                            subtitle: "Session-only comparison route for the current media.",
                            control: .selection(.init(
                                value: "Current Route",
                                options: ["Current Route", "mpv Session", "Apple Reference Session"]
                            ))
                        ),
                        SettingsItem(
                            id: "reset-engine-overrides",
                            title: "Reset All Engine Overrides",
                            subtitle: "Clears renderer, HDR, presets, and diagnostic flags.",
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
                            subtitle: "Preset-only testing. Raw mpv arguments are not exposed.",
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
                            subtitle: "Codec, resolution, fps, HDR, projection, stereo, and metadata source.",
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
                            subtitle: "Copies the current media profile for support.",
                            control: .action(.init(title: "Copy", feedback: "Copied"))
                        ),
                        SettingsItem(
                            id: "redetect-media",
                            title: "Re-detect Current Media",
                            subtitle: "Runs lightweight or runtime detection again.",
                            control: .action(.init(title: "Run", feedback: "Queued"))
                        ),
                        SettingsItem(
                            id: "clear-current-media-cache",
                            title: "Clear Current Media Profile Cache",
                            subtitle: "Repairs a single file with incorrect media facts.",
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
                            subtitle: "Rebuilds cached media profiles after batch pollution.",
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
                            subtitle: "HDROutputMode, pixel format, colorspace, and EDR surface state.",
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
                            subtitle: "Counts values above 1.0 and records max, mean, source, and contract.",
                            control: .action(.init(title: "Sample", feedback: "Queued"))
                        ),
                        SettingsItem(
                            id: "hdr-session-comparison",
                            title: "HDR On / Off Session Comparison",
                            subtitle: "Session-only switch for comparing the HDR path.",
                            control: .selection(.init(
                                value: "HDR On",
                                options: ["HDR On", "HDR Off"]
                            ))
                        ),
                        SettingsItem(
                            id: "hdr-reference-comparison",
                            title: "mpv / Apple Reference HDR Comparison",
                            subtitle: "Compares color, brightness, and saturation on the same media.",
                            control: .selection(.init(
                                value: "mpv Route",
                                options: ["mpv Route", "Apple Reference"]
                            ))
                        ),
                        SettingsItem(
                            id: "copy-hdr-summary",
                            title: "Copy HDR Diagnostic Summary",
                            subtitle: "Outputs HDR type, route, and sampling result.",
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
                            subtitle: "Space state, playback mode, projection override, stereo override, and scene.",
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
                            subtitle: "Requests open or close and records system cancellation.",
                            control: .selection(.init(
                                value: "No Test",
                                options: ["No Test", "Request Open", "Request Close"]
                            ))
                        ),
                        SettingsItem(
                            id: "reset-scene-position",
                            title: "Reset Scene Screen Position",
                            subtitle: "Repairs polluted spatial screen placement.",
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
                            subtitle: "Shows the trigger condition for immersive entry.",
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
                            subtitle: "Tests connect, directory listing, and playback URL resolution.",
                            control: .action(.init(title: "Test", feedback: "Queued"))
                        ),
                        SettingsItem(
                            id: "reconnect-current-source",
                            title: "Reconnect Current Source",
                            subtitle: "Reconnects the active NAS or WebDAV source.",
                            control: .action(.init(title: "Reconnect", feedback: "Queued"))
                        ),
                        SettingsItem(
                            id: "source-error-summary",
                            title: "Source Error Summary",
                            subtitle: "Error code, duration, auth state, and redacted host fingerprint.",
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
                            subtitle: "Source type, root path, and credential key fingerprint.",
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
                            subtitle: "fps, frame pacing, drops, memory, texture size, and resolution.",
                            control: .toggle(.init(isOn: false))
                        ),
                        SettingsItem(
                            id: "performance-report",
                            title: "Sample 30-second Performance Report",
                            subtitle: "fps, frame time, memory, thermal, media profile, and playback mode.",
                            control: .action(.init(title: "Sample", feedback: "Queued"))
                        ),
                        SettingsItem(
                            id: "controls-never-hide",
                            title: "Controls Never Hide",
                            subtitle: "Diagnostic-only mode for recordings and reproduction.",
                            control: .toggle(.init(isOn: false))
                        ),
                        SettingsItem(
                            id: "rendering-load-summary",
                            title: "Current Rendering Load Summary",
                            subtitle: "Resolution, frame rate, panorama, HDR, and immersive pressure.",
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
                            subtitle: "Used for feedback, TestFlight, and issue triage.",
                            control: .readOnly(.init(
                                value: "0.1.0 (42)",
                                actionTitle: "Copy",
                                feedback: "Copied"
                            ))
                        ),
                        SettingsItem(
                            id: "licenses",
                            title: "Open-source Licenses",
                            subtitle: "Third-party notices for mpv, FFmpeg, and dependencies.",
                            control: .action(.init(title: "View", feedback: "Opened"))
                        ),
                        SettingsItem(
                            id: "support-feedback",
                            title: "Support & Feedback",
                            subtitle: "Contact support or copy a diagnostic summary.",
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
