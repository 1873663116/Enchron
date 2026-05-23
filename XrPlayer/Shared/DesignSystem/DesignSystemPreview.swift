import SwiftUI

// MARK: - Design System Preview Catalog

// Comprehensive preview catalog for all DesignTokens.
// Open this file in Xcode and use Canvas (⌥⌘↩) to inspect each section.

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: 1 — Glass Variants
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Shows every `enchronGlass*()` modifier side by side.
#Preview("Glass Variants") {
    ScrollView {
        VStack(spacing: DesignTokens.Spacing.lg) {

            // — Window
            previewLabel("enchronGlassWindow()")
            Rectangle()
                .fill(.clear)
                .frame(height: 120)
                .overlay {
                    Text("Window — base 40pt")
                        .foregroundStyle(.primary)
                }
                .enchronGlassWindow()

            // — Control (Capsule)
            previewLabel("enchronGlassControl()")
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "backward.fill")
                Image(systemName: "play.fill")
                Image(systemName: "forward.fill")
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .enchronGlassControl()

            // — Panel
            previewLabel("enchronGlassPanel()")
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Panel Title").font(DesignTokens.Typography.headline)
                Text("Regular material for readable content.")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Spacing.md)
            .frame(width: 300)
            .enchronGlassPanel()

            // — Card (with .lift hover)
            previewLabel("enchronGlassCard()  →  .lift")
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .fill(DesignTokens.Surface.elevated)
                    .frame(height: DesignTokens.Card.thumbnailHeight)
                    .overlay {
                        Image(systemName: "play.circle")
                            .font(DesignTokens.SymbolSize.hero)
                            .foregroundStyle(.tertiary)
                    }
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("Video Title")
                        .font(DesignTokens.Typography.headline)
                    Text("1080p · H.265 · 2.4 GB")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DesignTokens.Card.paddingH)
                .padding(.vertical, DesignTokens.Card.paddingV)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: DesignTokens.Card.gridMin)
            .enchronGlassCard()

            // — Menu Item (with .highlight hover)
            previewLabel("enchronGlassMenuItem()  →  .highlight")
            VStack(spacing: DesignTokens.Spacing.xxs) {
                ForEach(["Audio Track", "Subtitle", "Speed"], id: \.self) { item in
                    HStack {
                        Text(item).font(.body)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .frame(minHeight: DesignTokens.Interactive.rowHeight)
                    .enchronGlassMenuItem()
                }
            }
            .padding(DesignTokens.Menu.glassPadding)
            .frame(width: DesignTokens.Menu.panelWidth)
            .enchronGlassMenu()

            // — Menu Container (no hover)
            previewLabel("enchronGlassMenu()")
            Text("Menu container — glass only, no hover")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .padding(DesignTokens.Spacing.md)
                .frame(width: 260)
                .enchronGlassMenu()

            // — Badge
            previewLabel("enchronGlassBadge()")
            HStack(spacing: DesignTokens.Spacing.xs) {
                badgeSample("HDR10+")
                badgeSample("MV-HEVC")
                badgeSample("Atmos")
            }

            // — Pill (with .lift hover)
            previewLabel("enchronGlassPill()  →  .lift")
            HStack(spacing: DesignTokens.Spacing.xs) {
                pillSample("All", selected: true)
                pillSample("Movies", selected: false)
                pillSample("TV Shows", selected: false)
            }

            // — Sidebar (system-managed)
            previewLabel("enchronGlassSidebar()")
            Text("System NavigationSplitView provides glass automatically")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
                .padding(DesignTokens.Spacing.md)
        }
        .padding(DesignTokens.Spacing.xxl)
    }
    .glassBackgroundEffect()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: 2 — Spacing Scale
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#Preview("Spacing Scale") {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
        spacingRow("xxs", DesignTokens.Spacing.xxs)
        spacingRow("xs", DesignTokens.Spacing.xs)
        spacingRow("sm", DesignTokens.Spacing.sm)
        spacingRow("md", DesignTokens.Spacing.md)
        spacingRow("lg", DesignTokens.Spacing.lg)
        spacingRow("xl", DesignTokens.Spacing.xl)
        spacingRow("xxl", DesignTokens.Spacing.xxl)
        spacingRow("xxxl", DesignTokens.Spacing.xxxl)
    }
    .padding(DesignTokens.Spacing.xxl)
    .glassBackgroundEffect()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: 3 — Radius & Shapes
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#Preview("Radius & Shapes") {
    VStack(spacing: DesignTokens.Spacing.xl) {
        // — Four tiers side by side
        HStack(spacing: DesignTokens.Spacing.xl) {
            // panel
            VStack(spacing: DesignTokens.Spacing.xs) {
                DesignTokens.ShapeToken.panel
                    .fill(DesignTokens.Surface.elevated)
                    .frame(width: 240, height: 160)
                    .overlay { Text("panel\n40pt").multilineTextAlignment(.center).font(.caption) }
                Text("ShapeToken.panel").font(DesignTokens.Typography.metadata).foregroundStyle(.secondary)
            }
            // card
            VStack(spacing: DesignTokens.Spacing.xs) {
                DesignTokens.ShapeToken.card
                    .fill(DesignTokens.Surface.elevated)
                    .frame(width: 200, height: 140)
                    .overlay { Text("card\n32pt").multilineTextAlignment(.center).font(.caption) }
                Text("ShapeToken.card").font(DesignTokens.Typography.metadata).foregroundStyle(.secondary)
            }
            // element
            VStack(spacing: DesignTokens.Spacing.xs) {
                DesignTokens.ShapeToken.element
                    .fill(DesignTokens.Surface.elevated)
                    .frame(width: 160, height: 100)
                    .overlay { Text("element\n24pt").multilineTextAlignment(.center).font(.caption) }
                Text("ShapeToken.element").font(DesignTokens.Typography.metadata).foregroundStyle(.secondary)
            }
            // capsule (badges/tags)
            VStack(spacing: DesignTokens.Spacing.xs) {
                Capsule()
                    .fill(DesignTokens.Surface.elevated)
                    .frame(width: 120, height: 44)
                    .overlay { Text("Capsule").font(.caption) }
                Text("Capsule()").font(DesignTokens.Typography.metadata).foregroundStyle(.secondary)
            }
        }

        // — Concentric nesting demo (real usage: menu → menuItem)
        HStack(spacing: DesignTokens.Spacing.xl) {
            // menu(card) → menuItem(element): 8pt glassPadding
            VStack(spacing: DesignTokens.Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .fill(DesignTokens.Surface.card)
                        .frame(width: 200, height: 160)
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.element, style: .continuous)
                        .fill(DesignTokens.Surface.overlay)
                        .frame(width: 184, height: 144)
                }
                Text("menu → menuItem\n35 −8→ 27").multilineTextAlignment(.center)
                    .font(DesignTokens.Typography.metadata).foregroundStyle(.secondary)
            }
        }
    }
    .padding(DesignTokens.Spacing.xxl)
    .glassBackgroundEffect()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: 4 — Interactive Sizes
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#Preview("Interactive Sizes") {
    HStack(spacing: DesignTokens.Spacing.xl) {
        interactiveSample("mini", DesignTokens.Interactive.mini)
        interactiveSample("regular", DesignTokens.Interactive.regular)
        interactiveSample("large", DesignTokens.Interactive.large)
        interactiveSample("xl", DesignTokens.Interactive.xl)
    }
    .padding(DesignTokens.Spacing.xxl)
    .glassBackgroundEffect()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: 5 — Typography Scale
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#Preview("Typography Scale") {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
        Text("Title — .title2")
            .font(DesignTokens.Typography.title)
        Text("Headline — .headline")
            .font(DesignTokens.Typography.headline)
        Text("Metadata — .caption")
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(.secondary)
        Text("SECTION HEADER — .caption2")
            .font(DesignTokens.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
        Text("Badge — .caption")
            .font(DesignTokens.Typography.badge)
        Text("00:12:34.56 — monospacedDetail")
            .font(DesignTokens.Typography.monospacedDetail)
            .foregroundStyle(.secondary)

        Divider().padding(.vertical, DesignTokens.Spacing.xs)

        Text("Symbol Sizes")
            .font(DesignTokens.Typography.headline)

        HStack(spacing: DesignTokens.Spacing.xl) {
            VStack {
                Image(systemName: "play.fill").font(DesignTokens.SymbolSize.control)
                Text("control").font(.caption2).foregroundStyle(.tertiary)
            }
            VStack {
                Image(systemName: "play.fill").font(DesignTokens.SymbolSize.card)
                Text("card").font(.caption2).foregroundStyle(.tertiary)
            }
            VStack {
                Image(systemName: "play.fill").font(DesignTokens.SymbolSize.action)
                Text("action").font(.caption2).foregroundStyle(.tertiary)
            }
            VStack {
                Image(systemName: "play.fill").font(DesignTokens.SymbolSize.feature)
                Text("feature").font(.caption2).foregroundStyle(.tertiary)
            }
            VStack {
                Image(systemName: "play.fill").font(DesignTokens.SymbolSize.hero)
                Text("hero").font(.caption2).foregroundStyle(.tertiary)
            }
            VStack {
                Image(systemName: "play.fill").font(DesignTokens.SymbolSize.giant)
                Text("giant").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
    .padding(DesignTokens.Spacing.xxl)
    .glassBackgroundEffect()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: 6 — Surface & Stroke
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#Preview("Surface & Stroke") {
    VStack(spacing: DesignTokens.Spacing.lg) {
        // Surface tiers
        Text("Surface Tiers").font(DesignTokens.Typography.headline)

        HStack(spacing: DesignTokens.Spacing.md) {
            surfaceSample("card\n0.03", DesignTokens.Surface.card)
            surfaceSample("elevated\n0.04", DesignTokens.Surface.elevated)
            surfaceSample("overlay\n0.06", DesignTokens.Surface.overlay)
            surfaceSample("selected\n0.08", DesignTokens.Surface.selected)
            surfaceSample("border\n0.05", DesignTokens.Surface.border)
        }

        Divider().padding(.vertical, DesignTokens.Spacing.xs)

        // Stroke tiers
        Text("Stroke Widths").font(DesignTokens.Typography.headline)

        HStack(spacing: DesignTokens.Spacing.xl) {
            strokeSample("subtle", DesignTokens.Stroke.subtle)
            strokeSample("regular", DesignTokens.Stroke.regular)
            strokeSample("bold", DesignTokens.Stroke.bold)
        }
    }
    .padding(DesignTokens.Spacing.xxl)
    .glassBackgroundEffect()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: 7 — Animation Tokens
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Tap each row to trigger its animation.
struct AnimationPreview: View {
    @State private var triggered: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Tap to trigger").font(DesignTokens.Typography.headline)

            animRow("controlsTransition", DesignTokens.AnimationToken.controlsTransition)
            animRow("panelSpring", DesignTokens.AnimationToken.panelSpring)
            animRow("menuPopup", DesignTokens.AnimationToken.menuPopup)
            animRow("selection", DesignTokens.AnimationToken.selection)
            animRow("playback", DesignTokens.AnimationToken.playback)
            animRow("scene", DesignTokens.AnimationToken.scene)
            animRow("fadeIn", DesignTokens.AnimationToken.fadeIn)
            animRow("skeleton", DesignTokens.AnimationToken.skeleton)
        }
        .padding(DesignTokens.Spacing.xxl)
        .glassBackgroundEffect()
    }

    @ViewBuilder
    private func animRow(_ name: String, _ anim: Animation) -> some View {
        let isActive = triggered.contains(name)
        HStack {
            Text(name)
                .font(.system(.body, design: .monospaced))
                .frame(width: 200, alignment: .leading)

            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(isActive ? Color.accentColor : DesignTokens.Surface.elevated)
                .frame(width: isActive ? 200 : 60, height: 36)
                .animation(anim, value: isActive)

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isActive {
                triggered.remove(name)
            } else {
                triggered.insert(name)
            }
        }
    }
}

#Preview("Animation Tokens") {
    AnimationPreview()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: 8 — Component Standards
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#Preview("Component Standards") {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
        // Card
        Text("Card").font(DesignTokens.Typography.headline)
        HStack(spacing: DesignTokens.Spacing.xs) {
            labelValue("paddingH", DesignTokens.Card.paddingH)
            labelValue("paddingV", DesignTokens.Card.paddingV)
            labelValue("gridMin", DesignTokens.Card.gridMin)
            labelValue("gridSpacing", DesignTokens.Card.gridSpacing)
        }

        Divider()

        // Menu
        Text("Menu").font(DesignTokens.Typography.headline)
        HStack(spacing: DesignTokens.Spacing.xs) {
            labelValue("glassPadding", DesignTokens.Menu.glassPadding)
            labelValue("panelWidth", DesignTokens.Menu.panelWidth)
            labelValue("submenuWidth", DesignTokens.Menu.submenuWidth)
        }

        Divider()

        // ControlBar
        Text("ControlBar").font(DesignTokens.Typography.headline)
        HStack(spacing: DesignTokens.Spacing.xs) {
            labelValue("width", DesignTokens.ControlBar.width)
            labelValue("buttonSpacing", DesignTokens.ControlBar.buttonSpacing)
        }

        Divider()

        // Layout
        Text("Layout").font(DesignTokens.Typography.headline)
        HStack(spacing: DesignTokens.Spacing.xs) {
            labelValue("playerControlsWidth", DesignTokens.Layout.playerControlsWidth)
            labelValue("ornamentGap", DesignTokens.Layout.ornamentGap)
        }
    }
    .padding(DesignTokens.Spacing.xxl)
    .glassBackgroundEffect()
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Private Helpers
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@ViewBuilder
private func previewLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
}

@ViewBuilder
private func spacingRow(_ name: String, _ value: CGFloat) -> some View {
    HStack(spacing: DesignTokens.Spacing.sm) {
        Text(name)
            .font(.system(.body, design: .monospaced))
            .frame(width: 50, alignment: .trailing)
        Text("\(Int(value))pt")
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(.secondary)
            .frame(width: 40, alignment: .trailing)
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.accentColor.opacity(0.6))
            .frame(width: value * 4, height: 20)
    }
}

@ViewBuilder
private func interactiveSample(_ name: String, _ size: CGFloat) -> some View {
    VStack(spacing: DesignTokens.Spacing.xs) {
        Circle()
            .fill(DesignTokens.Surface.overlay)
            .frame(width: size, height: size)
            .overlay {
                Text("\(Int(size))")
                    .font(.system(.caption2, design: .monospaced))
            }

        // 60pt minimum target zone
        Circle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(.tertiary)
            .frame(width: 60, height: 60)
            .overlay {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: size, height: size)
            }

        Text(name)
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(.secondary)
    }
}

@ViewBuilder
private func surfaceSample(_ label: String, _ color: Color) -> some View {
    VStack(spacing: DesignTokens.Spacing.xxs) {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
            .fill(color)
            .frame(width: 80, height: 80)
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .strokeBorder(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.subtle)
            }
        Text(label)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

@ViewBuilder
private func strokeSample(_ name: String, _ width: CGFloat) -> some View {
    VStack(spacing: DesignTokens.Spacing.xs) {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
            .strokeBorder(.white.opacity(0.4), lineWidth: width)
            .frame(width: 80, height: 50)
        Text("\(name)\n\(String(format: "%.1f", width))pt")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

@ViewBuilder
private func badgeSample(_ text: String) -> some View {
    Text(text)
        .font(DesignTokens.Typography.badge)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .enchronGlassBadge()
}

@ViewBuilder
private func pillSample(_ text: String, selected: Bool) -> some View {
    Text(text)
        .font(.body)
        .foregroundStyle(selected ? .primary : .secondary)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(
            selected ? DesignTokens.Surface.selected : .clear,
            in: Capsule()
        )
        .enchronGlassPill()
}

@ViewBuilder
private func labelValue(_ name: String, _ value: CGFloat) -> some View {
    VStack(spacing: 2) {
        Text("\(Int(value))")
            .font(.system(.title3, design: .monospaced))
        Text(name)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, DesignTokens.Spacing.xs)
    .padding(.vertical, DesignTokens.Spacing.xxs)
    .enchronGlassBadge()
}
