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
        XCTAssertEqual(e.handle(KeyPress(.return)), [.click(.left, count: 1), .hideOverlay])
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
        XCTAssertEqual(e.handle(KeyPress(.two)), []) // already there
        XCTAssertEqual(e.handle(KeyPress(.nine)), []) // no such screen
        XCTAssertEqual(e.handle(KeyPress(.one)), [.warp(Point(x: 500, y: 300)), .redraw])
    }

    func testEscapeExits() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        XCTAssertEqual(e.handle(KeyPress(.escape)), [.hideOverlay])
        XCTAssertFalse(e.isActive)
        XCTAssertEqual(e.handle(KeyPress(.i)), [])
    }
}
