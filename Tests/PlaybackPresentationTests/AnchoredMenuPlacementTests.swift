import CoreGraphics
@testable import DesignSystem
import Testing
import SwiftUI

@Suite("Anchored menu geometry")
struct AnchoredMenuPlacementTests {
    @MainActor
    @Test("A parent click closes the child without opening another until the next click",
          arguments: ["audio", "speed"])
    func parentClickClosesChild(key: String) throws {
        let menu = AnchoredMenuPresentation()
        menu.present(key: "more", source: .zero) { Text("Categories") }
        menu.presentSubmenu(key: "audio", source: .zero) { Text("Audio") }
        #expect(menu.selectedSubmenu == "audio")
        let closing = try #require(menu.child)

        menu.presentSubmenu(key: key, source: .zero) { Text("New options") }
        #expect(menu.isPresented)
        #expect(menu.selectedSubmenu == nil)
        menu.presentSubmenu(key: "episodes", source: .zero) { Text("Rapid click") }
        menu.finished(closing.id)
        #expect(menu.child == nil)
        #expect(menu.isPresented)

        menu.presentSubmenu(key: key, source: .zero) { Text("New options") }
        #expect(menu.selectedSubmenu == key)
    }

    @MainActor
    @Test("An outside click closes both menus regardless of animation completion order",
          arguments: [true, false])
    func outsideClickClosesBoth(rootFinishesFirst: Bool) throws {
        let menu = AnchoredMenuPresentation()
        var dismissed = 0
        menu.present(key: "more", source: .zero, onDismiss: { dismissed += 1 }) { Text("Categories") }
        menu.presentSubmenu(key: "audio", source: .zero) { Text("Audio") }
        #expect(menu.selectedSubmenu == "audio")
        let root = try #require(menu.root)
        let child = try #require(menu.child)

        menu.dismiss()
        #expect(!menu.isPresented)
        #expect(menu.selectedSubmenu == nil)
        menu.presentSubmenu(key: "speed", source: .zero) { Text("Blocked opening") }
        for id in rootFinishesFirst ? [root.id, child.id] : [child.id, root.id] { menu.finished(id) }
        #expect(!menu.isActive)
        #expect(menu.child == nil)
        #expect(dismissed == 1)
    }

    @Test("Menu content sizes have shared limits and respect a smaller viewport")
    func boundedContentSize() {
        #expect(AnchoredMenuSizing.content.width(idealContentWidth: 80, availableWidth: 800) == 196)
        #expect(AnchoredMenuSizing.content.width(idealContentWidth: 250, availableWidth: 800) == 266)
        #expect(AnchoredMenuSizing.content.width(idealContentWidth: 900, availableWidth: 800) == 376)
        #expect(AnchoredMenuSizing.content.width(idealContentWidth: 900, availableWidth: 150) == 150)
        #expect(AnchoredMenuSizing.content.height(contentHeight: 60, availableHeight: 800) == 76)
        #expect(AnchoredMenuSizing.content.height(contentHeight: 240, availableHeight: 800) == 256)
        #expect(AnchoredMenuSizing.content.height(contentHeight: 900, availableHeight: 800) == 420)
        #expect(AnchoredMenuSizing.content.height(contentHeight: 900, availableHeight: 200) == 200)
    }

    @Test("Episode grids use whole cells and editor forms keep their own width")
    func gridAndEditorSizes() {
        #expect(AnchoredMenuSizing.grid(itemCount: 2).width(idealContentWidth: 0, availableWidth: 800) == 196)
        #expect(AnchoredMenuSizing.grid(itemCount: 4).width(idealContentWidth: 0, availableWidth: 800) == 256)
        #expect(AnchoredMenuSizing.grid(itemCount: 300).width(idealContentWidth: 0, availableWidth: 800) == 376)
        #expect(AnchoredMenuSizing.fixed(width: 520).width(idealContentWidth: 0, availableWidth: 800) == 520)
        #expect(AnchoredMenuSizing.fixed(width: 520).height(contentHeight: 500, availableHeight: 800) == 516)
    }

    @Test("Number hover inset matches the visible rounded square and preserves the larger target")
    func numberHoverGeometry() {
        let target = CGRect(x: 0, y: 0, width: 60, height: 60)
        let visible = CGRect(x: 8, y: 8, width: 44, height: 44)
        let insets = EdgeInsets(top: DesignTokens.Spacing.xs, leading: DesignTokens.Spacing.xs,
                               bottom: DesignTokens.Spacing.xs, trailing: DesignTokens.Spacing.xs)
        let hover = EnchronHoverRegion(DesignTokens.ShapeToken.menuNumber, insets: insets).path(in: target)
        #expect(hover == DesignTokens.ShapeToken.menuNumber.path(in: visible))
        #expect(hover.boundingRect == visible)
        #expect(DesignTokens.ShapeToken.menuNumberTarget.path(in: target).boundingRect == target)
    }

    @Test("A menu row highlight leaves silent edges inside its sixty point target")
    func rowHoverGeometry() {
        let target = CGRect(x: 0, y: 0, width: 180, height: 60)
        let visible = CGRect(x: 2, y: 8, width: 176, height: 44)
        let insets = EdgeInsets(top: DesignTokens.Menu.rowVerticalInset, leading: DesignTokens.Menu.rowVisualInset,
                               bottom: DesignTokens.Menu.rowVerticalInset, trailing: DesignTokens.Menu.rowVisualInset)
        let hover = EnchronHoverRegion(DesignTokens.ShapeToken.menuRow, insets: insets).path(in: target)
        #expect(DesignTokens.Menu.rowVisualHeight == 44)
        #expect(hover.boundingRect == visible)
        #expect(!hover.contains(CGPoint(x: 90, y: 1)))
        #expect(DesignTokens.ShapeToken.menuRow.path(in: target).contains(CGPoint(x: 90, y: 1)))
    }

    @Test("Each view mode icon highlights only its visible circle inside a taller interaction target")
    func viewModeHoverGeometry() {
        let target = CGRect(x: 0, y: 0, width: 44, height: 60)
        let insets = EdgeInsets(top: DesignTokens.Spacing.xs, leading: 0,
                               bottom: DesignTokens.Spacing.xs, trailing: 0)
        let hover = EnchronHoverRegion(Circle(), insets: insets).path(in: target)
        #expect(hover.boundingRect == CGRect(x: 0, y: 8, width: 44, height: 44))
        #expect(!hover.contains(CGPoint(x: 22, y: 1)))
        #expect(Rectangle().path(in: target).contains(CGPoint(x: 22, y: 1)))
    }

    @Test("Menu corners derive from the container while the minimum matches a padded capsule")
    func containerRelativeCorners() {
        #expect(DesignTokens.ShapeToken.menu().radius == 38)
        let parent = RectangleCornerRadii(topLeading: 46, bottomLeading: 30, bottomTrailing: 30, topTrailing: 40)
        #expect(DesignTokens.ShapeToken.menu(containerRadii: parent).radius == 46)
        let rect = CGRect(x: 0, y: 0, width: 196, height: 76)
        #expect(DesignTokens.ShapeToken.menu().inset(by: 8).path(in: rect)
                == RoundedRectangle(cornerRadius: 30, style: .continuous).path(in: rect.insetBy(dx: 8, dy: 8)))
        let row = DesignTokens.ShapeToken.menuRow.path(in: CGRect(x: 0, y: 0, width: 180, height: 60))
        #expect(row.contains(CGPoint(x: 1, y: 30)))
        #expect(!row.contains(CGPoint(x: 1, y: 1)))
    }
    @Test("Opening and spring overshoot keep the menu clear of its trigger")
    func avoidsTriggerThroughoutAnimation() {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 900)
        for source in [CGRect(x: 1080, y: 20, width: 60, height: 60),
                       CGRect(x: 20, y: 800, width: 60, height: 60),
                       CGRect(x: 550, y: 400, width: 60, height: 60)] {
            for edge in AnchoredMenuPlacement.Edge.allCases {
                let placement = AnchoredMenuPlacement.root(
                    source: source, size: CGSize(width: 200, height: 256),
                    bounds: bounds, preferredEdge: edge
                )
                #expect(bounds.contains(placement.frame))
                for step in 0...120 {
                    let frame = placement.frame(at: CGFloat(step) / 100)
                    #expect(!frame.intersects(source))
                }
                #expect(placement.frame(at: 0).width == 20)
                #expect(placement.frame(at: 1) == placement.frame)
            }
        }
    }

    @Test("A submenu beside the right edge opens on the left with only edge overlap")
    func submenuUsesAvailableSide() {
        let parent = CGRect(x: 900, y: 150, width: 200, height: 256)
        let source = CGRect(x: 908, y: 218, width: 184, height: 60)
        let placement = AnchoredMenuPlacement.submenu(
            source: source, parent: parent, size: CGSize(width: 200, height: 300),
            bounds: CGRect(x: 0, y: 0, width: 1120, height: 800)
        )
        #expect(placement.edge == .leading)
        #expect(placement.frame == CGRect(x: 708, y: 98, width: 200, height: 300))
        for step in 0...120 {
            let overlap = parent.intersection(placement.frame(at: CGFloat(step) / 100))
            #expect(overlap.isNull || overlap.width <= 8.000001)
        }
    }

    @Test("A submenu beside the left edge opens on the right and stays in the viewport")
    func submenuAtLeftEdge() {
        let placement = AnchoredMenuPlacement.submenu(
            source: CGRect(x: 28, y: 28, width: 184, height: 60),
            parent: CGRect(x: 20, y: 20, width: 200, height: 256),
            size: CGSize(width: 200, height: 300),
            bounds: CGRect(x: 0, y: 0, width: 1120, height: 800)
        )
        #expect(placement.edge == .trailing)
        #expect(placement.frame == CGRect(x: 212, y: 0, width: 200, height: 300))
    }

    @Test("A tall episode menu moves upward while the selected parent row stays visible")
    func tallSubmenuMovesUpward() {
        let placement = AnchoredMenuPlacement.submenu(
            source: CGRect(x: 860, y: 544, width: 180, height: 60),
            parent: CGRect(x: 852, y: 356, width: 196, height: 256),
            size: CGSize(width: 376, height: 420),
            bounds: CGRect(x: 0, y: 0, width: 1496, height: 1064)
        )
        #expect(placement.frame == CGRect(x: 1040, y: 192, width: 376, height: 420))
        #expect(placement.frame.maxY == 612)
    }
}
