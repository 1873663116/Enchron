import SwiftUI

// MARK: - Token Reference Previews
// Visual reference for all DesignToken values.

// MARK: - Spacing Scale

struct SpacingScalePreview: View {
    var body: some View {
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
        .navigationTitle("Spacing Scale")
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
}

// MARK: - Radius & Shapes

struct RadiusShapesPreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                HStack(spacing: DesignTokens.Spacing.xl) {
                    shapeDemo("panel\n40pt", DesignTokens.ShapeToken.panel, width: 240, height: 160)
                    shapeDemo("card\n32pt", DesignTokens.ShapeToken.card, width: 200, height: 140)
                    shapeDemo("element\n24pt", DesignTokens.ShapeToken.element, width: 160, height: 100)
                    capsuleDemo()
                }

                Divider()

                Text("Concentric Nesting (8pt grid)")
                    .font(DesignTokens.Typography.headline)

                HStack(spacing: DesignTokens.Spacing.xl) {
                    concentricDemo("panel → card\n40 −8→ 32",
                                   outer: DesignTokens.Radius.panel, inner: DesignTokens.Radius.card,
                                   outerSize: 220, innerInset: 8)
                    concentricDemo("card → element\n32 −8→ 24",
                                   outer: DesignTokens.Radius.card, inner: DesignTokens.Radius.element,
                                   outerSize: 200, innerInset: 8)
                    concentricDemo("menu → menuItem\ncard(32) −8→ element(24)",
                                   outer: DesignTokens.Radius.card, inner: DesignTokens.Radius.element,
                                   outerSize: 200, innerInset: 8)
                }
            }
            .padding(DesignTokens.Spacing.xxl)
        }
        .navigationTitle("Radius & Shapes")
    }

    @ViewBuilder
    private func shapeDemo(_ label: String, _ shape: some Shape, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            shape.fill(DesignTokens.Surface.elevated)
                .frame(width: width, height: height)
                .overlay { Text(label).multilineTextAlignment(.center).font(.caption) }
            Text(label.components(separatedBy: "\n").first ?? "")
                .font(DesignTokens.Typography.metadata).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func capsuleDemo() -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Capsule().fill(DesignTokens.Surface.elevated)
                .frame(width: 120, height: 44)
                .overlay { Text("Capsule").font(.caption) }
            Text("Capsule").font(DesignTokens.Typography.metadata).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func concentricDemo(_ label: String, outer: CGFloat, inner: CGFloat,
                                outerSize: CGFloat, innerInset: CGFloat) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: outer, style: .continuous)
                    .fill(DesignTokens.Surface.card)
                    .frame(width: outerSize, height: outerSize * 0.8)
                RoundedRectangle(cornerRadius: inner, style: .continuous)
                    .fill(DesignTokens.Surface.overlay)
                    .frame(width: outerSize - innerInset * 2,
                           height: outerSize * 0.8 - innerInset * 2)
            }
            Text(label).multilineTextAlignment(.center)
                .font(DesignTokens.Typography.metadata).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Interactive Sizes

struct InteractiveSizesPreview: View {
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            interactiveItem("mini", DesignTokens.Interactive.mini)
            interactiveItem("regular", DesignTokens.Interactive.regular)
            interactiveItem("large", DesignTokens.Interactive.large)
            interactiveItem("xl", DesignTokens.Interactive.xl)
        }
        .padding(DesignTokens.Spacing.xxl)
        .navigationTitle("Interactive Sizes")
    }

    @ViewBuilder
    private func interactiveItem(_ name: String, _ size: CGFloat) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Circle().fill(DesignTokens.Surface.overlay)
                .frame(width: size, height: size)
                .overlay { Text("\(Int(size))").font(.system(.caption2, design: .monospaced)) }
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.tertiary)
                .frame(width: 60, height: 60)
                .overlay {
                    Circle().fill(Color.accentColor.opacity(0.15))
                        .frame(width: size, height: size)
                }
            Text(name).font(DesignTokens.Typography.metadata).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Typography Scale

struct TypographyScalePreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                Text("Title — .title2").font(DesignTokens.Typography.title)
                Text("Headline — .headline").font(DesignTokens.Typography.headline)
                Text("Metadata — .caption").font(DesignTokens.Typography.metadata).foregroundStyle(.secondary)
                Text("SECTION HEADER — .caption2")
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(.secondary).textCase(.uppercase)
                Text("Badge — .caption").font(DesignTokens.Typography.badge)
                Text("00:12:34.56 — monospacedDetail")
                    .font(DesignTokens.Typography.monospacedDetail).foregroundStyle(.secondary)

                Divider().padding(.vertical, DesignTokens.Spacing.xs)

                Text("Symbol Sizes").font(DesignTokens.Typography.headline)
                HStack(spacing: DesignTokens.Spacing.xl) {
                    symbolItem("control", DesignTokens.SymbolSize.control)
                    symbolItem("card", DesignTokens.SymbolSize.card)
                    symbolItem("action", DesignTokens.SymbolSize.action)
                    symbolItem("feature", DesignTokens.SymbolSize.feature)
                    symbolItem("hero", DesignTokens.SymbolSize.hero)
                    symbolItem("giant", DesignTokens.SymbolSize.giant)
                }
            }
            .padding(DesignTokens.Spacing.xxl)
        }
        .navigationTitle("Typography")
    }

    @ViewBuilder
    private func symbolItem(_ name: String, _ font: Font) -> some View {
        VStack {
            Image(systemName: "play.fill").font(font)
            Text(name).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Surface & Stroke

struct SurfaceStrokePreview: View {
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Text("Surface Tiers").font(DesignTokens.Typography.headline)
            HStack(spacing: DesignTokens.Spacing.md) {
                surfaceItem("card\n0.03", DesignTokens.Surface.card)
                surfaceItem("elevated\n0.04", DesignTokens.Surface.elevated)
                surfaceItem("overlay\n0.06", DesignTokens.Surface.overlay)
                surfaceItem("selected\n0.08", DesignTokens.Surface.selected)
                surfaceItem("border\n0.05", DesignTokens.Surface.border)
            }
            Divider().padding(.vertical, DesignTokens.Spacing.xs)
            Text("Stroke Widths").font(DesignTokens.Typography.headline)
            HStack(spacing: DesignTokens.Spacing.xl) {
                strokeItem("subtle", DesignTokens.Stroke.subtle)
                strokeItem("regular", DesignTokens.Stroke.regular)
                strokeItem("bold", DesignTokens.Stroke.bold)
            }
        }
        .padding(DesignTokens.Spacing.xxl)
        .navigationTitle("Surface & Stroke")
    }

    @ViewBuilder
    private func surfaceItem(_ label: String, _ color: Color) -> some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(color).frame(width: 80, height: 80)
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .strokeBorder(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.subtle)
                }
            Text(label).font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func strokeItem(_ name: String, _ width: CGFloat) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .strokeBorder(.white.opacity(0.4), lineWidth: width)
                .frame(width: 80, height: 50)
            Text("\(name)\n\(String(format: "%.1f", width))pt")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}

// MARK: - Animation Tokens

struct AnimationTokensPreview: View {
    @State private var triggered: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
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
        .navigationTitle("Animation Tokens")
    }

    @ViewBuilder
    private func animRow(_ name: String, _ anim: Animation) -> some View {
        let isActive = triggered.contains(name)
        Button {
            if isActive { triggered.remove(name) } else { triggered.insert(name) }
        } label: {
            HStack {
                Text(name).font(.system(.body, design: .monospaced))
                    .frame(width: 200, alignment: .leading)
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(isActive ? Color.accentColor : DesignTokens.Surface.elevated)
                    .frame(width: isActive ? 200 : 60, height: 36)
                    .animation(anim, value: isActive)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
