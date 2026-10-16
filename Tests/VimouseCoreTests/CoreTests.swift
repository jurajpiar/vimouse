import XCTest
@testable import VimouseCore

final class GeometryTests: XCTestCase {
    func testSubdivisionCoversRect() {
        let r = Rect(x: 10, y: 20, width: 100, height: 50)
        let q = r.subdivided()
        XCTAssertEqual(q[.topLeft], Rect(x: 10, y: 20, width: 50, height: 25))
        XCTAssertEqual(q[.topRight], Rect(x: 60, y: 20, width: 50, height: 25))
        XCTAssertEqual(q[.bottomLeft], Rect(x: 10, y: 45, width: 50, height: 25))
        XCTAssertEqual(q[.bottomRight], Rect(x: 60, y: 45, width: 50, height: 25))
        // Quadrant centres lie inside the parent.
        for sub in q.values { XCTAssertTrue(r.contains(sub.center)) }
    }
}

final class BisectTests: XCTestCase {
    func testEightStepsReach10pxOn2560Wide() {
        var s = BisectSession(root: Rect(x: 0, y: 0, width: 2560, height: 1440))
        for _ in 0..<8 { s.select(.bottomRight) }
        XCTAssertEqual(s.depth, 8)
        XCTAssertEqual(s.current.width, 10)
        XCTAssertEqual(s.current.height, 5.625)
        XCTAssertEqual(s.ancestors.count, 8)
        XCTAssertEqual(s.ancestors.first, s.root)
    }

    func testUpStopsAtRoot() {
        var s = BisectSession(root: Rect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertFalse(s.up())
        s.select(.topLeft)
        XCTAssertTrue(s.up())
        XCTAssertEqual(s.current, s.root)
    }
}

final class EngineTests: XCTestCase {
    let screen = Rect(x: 0, y: 0, width: 1000, height: 600)

    func testActivateWarpsToCentre() {
        let e = PointerEngine()
        XCTAssertEqual(e.activate(screen: screen), [.showOverlay, .warp(Point(x: 500, y: 300))])
        XCTAssertTrue(e.isActive)
    }

    func testQuadrantThenClick() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        XCTAssertEqual(e.handle(KeyPress(.i)), [.warp(Point(x: 250, y: 150)), .redraw])
        XCTAssertEqual(e.handle(KeyPress(.k)), [.warp(Point(x: 375, y: 225)), .redraw])
        XCTAssertEqual(e.handle(KeyPress(.return)), [.click(.left, count: 1, modifiers: []), .hideOverlay])
        XCTAssertFalse(e.isActive)
    }

    func testUnboundKeyIsSwallowedSilently() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        XCTAssertEqual(e.handle(KeyPress(.q)), [])
        XCTAssertTrue(e.isActive)
    }

    func testUpAtRootDoesNothing() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        XCTAssertEqual(e.handle(KeyPress(.delete)), [])
    }

    func testScreenSwitching() {
        let e = PointerEngine()
        let second = Rect(x: 1000, y: -200, width: 800, height: 800)
        _ = e.activate(screens: [screen, second], index: 0)
        _ = e.handle(KeyPress(.i))
        XCTAssertEqual(e.handle(KeyPress(.tab)), [.warp(Point(x: 1400, y: 200)), .redraw])
        XCTAssertEqual(e.screenIndex, 1)
        XCTAssertEqual(e.session?.depth, 0)
        XCTAssertEqual(e.handle(KeyPress(.tab)), [.warp(Point(x: 500, y: 300)), .redraw]) // wraps
        XCTAssertEqual(e.handle(KeyPress(.tab, [.shift])), [.warp(Point(x: 1400, y: 200)), .redraw])
        XCTAssertEqual(e.handle(KeyPress(.two)), [.redraw]) // count prefix
        XCTAssertEqual(e.handle(KeyPress(.tab)), []) // 2⇥: already on screen 2
        _ = e.handle(KeyPress(.nine))
        XCTAssertEqual(e.handle(KeyPress(.tab)), []) // 9⇥: no such screen
        _ = e.handle(KeyPress(.one))
        XCTAssertEqual(e.handle(KeyPress(.tab)), [.warp(Point(x: 500, y: 300)), .redraw]) // 1⇥
    }

    func testCountPrefix() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.s))
        _ = e.handle(KeyPress(.four))
        XCTAssertEqual(e.handle(KeyPress(.five)), [.redraw])
        XCTAssertEqual(e.pendingCount, 45)
        XCTAssertEqual(e.handle(KeyPress(.j)), [.scroll(dx: 0, dy: 45 * 60)])
        XCTAssertNil(e.pendingCount)
        XCTAssertEqual(e.handle(KeyPress(.j)), [.scroll(dx: 0, dy: 60)]) // count consumed
        // Escape with a pending count cancels the count, not the mode.
        _ = e.handle(KeyPress(.three))
        XCTAssertEqual(e.handle(KeyPress(.escape)), [.redraw])
        XCTAssertTrue(e.isActive)
        XCTAssertNil(e.pendingCount)
        // Counts in pointer mode: repeat a quadrant, go up several levels, multi-click.
        _ = e.handle(KeyPress(.s))
        _ = e.handle(KeyPress(.three))
        _ = e.handle(KeyPress(.i))
        XCTAssertEqual(e.session?.depth, 3)
        _ = e.handle(KeyPress(.two))
        _ = e.handle(KeyPress(.delete))
        XCTAssertEqual(e.session?.depth, 1)
        _ = e.handle(KeyPress(.three))
        XCTAssertEqual(e.handle(KeyPress(.return)), [.click(.left, count: 3, modifiers: []), .hideOverlay])
    }

    func testModifierClickAndClickStay() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        XCTAssertEqual(e.handle(KeyPress(.space, [.shift])), [.click(.left, count: 1, modifiers: [.shift])])
        XCTAssertTrue(e.isActive)
        XCTAssertEqual(e.handle(KeyPress(.x, [.command])), [.click(.left, count: 2, modifiers: [.command]), .hideOverlay])
        XCTAssertFalse(e.isActive)
    }

    func testDragThenNavigateThenDrop() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        XCTAssertEqual(e.handle(KeyPress(.v)), [.mouseDown(.left), .redraw])
        XCTAssertTrue(e.dragging)
        XCTAssertEqual(e.handle(KeyPress(.k)), [.warp(Point(x: 750, y: 450)), .redraw])
        XCTAssertEqual(e.handle(KeyPress(.v)), [.mouseUp(.left), .redraw])
        XCTAssertFalse(e.dragging)
        XCTAssertTrue(e.isActive)
    }

    func testEscapeWhileDraggingReleasesButton() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.v))
        XCTAssertEqual(e.handle(KeyPress(.escape)), [.mouseUp(.left), .hideOverlay])
        XCTAssertFalse(e.dragging)
    }

    func testScrollMode() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        XCTAssertEqual(e.handle(KeyPress(.s)), [.redraw])
        XCTAssertEqual(e.mode, .scroll)
        XCTAssertEqual(e.handle(KeyPress(.j)), [.scroll(dx: 0, dy: 60)])
        XCTAssertEqual(e.handle(KeyPress(.k)), [.scroll(dx: 0, dy: -60)])
        XCTAssertEqual(e.handle(KeyPress(.l)), [.scroll(dx: 60, dy: 0)])
        XCTAssertEqual(e.handle(KeyPress(.d)), [.scroll(dx: 0, dy: 300)])
        XCTAssertEqual(e.handle(KeyPress(.u)), [.scroll(dx: 0, dy: -300)])
        XCTAssertEqual(e.handle(KeyPress(.i)), []) // quadrant keys inactive in scroll mode
        XCTAssertEqual(e.handle(KeyPress(.s)), [.redraw])
        XCTAssertEqual(e.mode, .pointer)
        XCTAssertEqual(e.handle(KeyPress(.j)), [.warp(Point(x: 250, y: 450)), .redraw]) // j is a quadrant again
    }

    func testHintsReflectState() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        XCTAssertFalse(e.hints.contains { $0.action == "up" })
        _ = e.handle(KeyPress(.i))
        XCTAssertTrue(e.hints.contains { $0.action == "up" })
        _ = e.handle(KeyPress(.s))
        XCTAssertTrue(e.hints.contains { $0.action == "half page" })
    }

    func testEscapeExits() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        XCTAssertEqual(e.handle(KeyPress(.escape)), [.hideOverlay])
        XCTAssertFalse(e.isActive)
        XCTAssertEqual(e.handle(KeyPress(.i)), [])
    }
}
