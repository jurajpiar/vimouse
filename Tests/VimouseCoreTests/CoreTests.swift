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

    func testIntersection() {
        let a = Rect(x: 0, y: 0, width: 100, height: 100)
        let b = Rect(x: 50, y: 60, width: 100, height: 100)
        XCTAssertTrue(a.intersects(b))
        XCTAssertEqual(a.intersection(b), Rect(x: 50, y: 60, width: 50, height: 40))
        let c = Rect(x: 200, y: 0, width: 10, height: 10)
        XCTAssertFalse(a.intersects(c))
        XCTAssertEqual(a.intersection(c).width, 0)
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

final class ConfigTests: XCTestCase {
    func testDefaultTemplateReproducesDefaults() throws {
        XCTAssertEqual(try Config.parse(Config.defaultTOML), Config())
    }

    func testEmptyFileIsDefaults() throws {
        XCTAssertEqual(try Config.parse(""), Config())
    }

    func testOverridesAndKeySpecs() throws {
        let c = try Config.parse("""
        [hotkey]
        activate = "ctrl+alt+m"
        [keys]
        top_left = "q"
        top_right = "w"
        bottom_left = "a"
        bottom_right = "s"
        left_click = "space"
        [scroll]
        step = 24
        [ruler]
        dim = 2   # clamped
        [snap]
        enabled = false
        """)
        XCTAssertEqual(c.keymap.activate, KeyPress(.m, [.control, .option]))
        XCTAssertEqual(c.keymap.quadrants[KeyPress(.q)], .topLeft)
        XCTAssertEqual(c.keymap.quadrants[KeyPress(.s)], .bottomRight)
        XCTAssertEqual(c.keymap.leftClick, [KeyPress(.space)])
        XCTAssertEqual(c.scrollStep, 24)
        XCTAssertEqual(c.rulerDim, 1)
        XCTAssertFalse(c.snapEnabled)
        XCTAssertEqual(c.keymap.rightClick, KeyMap.default.rightClick) // untouched
    }

    func testErrors() {
        XCTAssertThrowsError(try Config.parse("[keys]\ntop_left = \"q\""))      // incomplete quadrants
        XCTAssertThrowsError(try Config.parse("[keys]\nexit = \"hyper+q\""))     // unknown modifier
        XCTAssertThrowsError(try Config.parse("[scroll]\nstep = \"fast\""))     // wrong type
        XCTAssertThrowsError(try Config.parse("garbage"))                         // not TOML
    }

    func testMigrationAddsMissingAndCommentsUnknown() throws {
        let old = """
        # my notes
        [keys]
        top_left = "q"
        top_right = "w"
        bottom_left = "a"
        bottom_right = "s"
        mystery = 1
        [scroll]
        step = 24
        """
        let (text, changed) = ConfigSchema.migrate(old)
        XCTAssertTrue(changed)
        XCTAssertTrue(text.contains("# my notes"))
        XCTAssertTrue(text.contains("# Bindings inside Pointer mode"))      // section description added
        XCTAssertTrue(text.contains("# Pick the top-left quadrant, e.g. \"i\", \"up\".\ntop_left = \"q\"")) // comment for an existing key
        XCTAssertTrue(text.contains("top_left = \"q\""))                 // user value kept
        XCTAssertTrue(text.contains("ignored (see CHANGELOG.md in the vimouse repository): mystery = 1"))
        XCTAssertTrue(text.contains("left_click = [\"return\", \"m\"]"))   // missing key appended with default
        XCTAssertTrue(text.contains("[ruler]"))                            // missing section appended
        let (t2, _) = ConfigSchema.migrate("[ruler]\nstep = 20\n")
        XCTAssertTrue(t2.contains("# superseded by `move` (0 = the band's own height), ignored (see CHANGELOG.md in the vimouse repository): step = 20"))
        XCTAssertTrue(t2.contains("\nmove = 0"))
        XCTAssertTrue(text.contains("# Darkening outside the band"))      // with its comment
        let c = try Config.parse(text)
        XCTAssertEqual(c.scrollStep, 24)
        XCTAssertEqual(c.keymap.quadrants[KeyPress(.q)], .topLeft)
        XCTAssertEqual(c.keymap.leftClick, KeyMap.default.leftClick)
        // A second migration is a no-op.
        XCTAssertFalse(ConfigSchema.migrate(text).changed)
        XCTAssertFalse(ConfigSchema.migrate(Config.defaultTOML).changed)
        XCTAssertTrue(ConfigSchema.migrate("").changed)
    }

    func testEverySettingAndSectionHasAComment() {
        for e in ConfigSchema.entries { XCTAssertFalse(e.comment.isEmpty, "\(e.section).\(e.key)") }
        for s in ConfigSchema.sections { XCTAssertNotNil(ConfigSchema.sectionComments[s], s) }
    }

    func testArrowKeysAndLabels() throws {
        let c = try Config.parse("""
        [scroll]
        down = "down"
        up = ["k", "up"]
        """)
        let e = PointerEngine(keymap: c.keymap)
        _ = e.activate(screen: Rect(x: 0, y: 0, width: 100, height: 100))
        _ = e.handle(KeyPress(.s))
        XCTAssertEqual(e.handle(KeyPress(.downArrow)), [.scroll(dx: 0, dy: 60)])
        XCTAssertEqual(e.handle(KeyPress(.upArrow)), [.scroll(dx: 0, dy: -60)])
        XCTAssertEqual(e.hints.first?.key, "↓k hl")
        XCTAssertEqual(KeyPress(.tab, [.shift]).label, "⇧⇥")
        XCTAssertEqual(KeyPress(.space, [.command, .shift]).label, "⇧⌘␣")
    }

    func testKeySpecs() {
        XCTAssertEqual(KeyPress.parse("cmd+shift+space"), KeyPress(.space, [.command, .shift]))
        XCTAssertEqual(KeyPress.parse("]"), KeyPress(.rightBracket))
        XCTAssertEqual(KeyPress.parse("Shift+Tab"), KeyPress(.tab, [.shift]))
        XCTAssertNil(KeyPress.parse("f13"))
    }
}

final class TOMLTests: XCTestCase {
    func testSubset() throws {
        let t = try TOML.parse("""
        # comment
        name = "a # not a comment"
        [s]
        n = 1_000
        f = 2.5
        b = true
        list = ["x", "y, z"]
        """)
        XCTAssertEqual(t[""]?["name"], .string("a # not a comment"))
        XCTAssertEqual(t["s"]?["n"], .int(1000))
        XCTAssertEqual(t["s"]?["f"], .double(2.5))
        XCTAssertEqual(t["s"]?["b"], .bool(true))
        XCTAssertEqual(t["s"]?["list"], .array([.string("x"), .string("y, z")]))
        XCTAssertEqual(t["s"]?["list"]?.strings, ["x", "y, z"])
    }
}

final class FakeSnap: SnapProvider {
    var points: [Point] = []
    var prepared = 0
    func prepare(screen: Rect) { prepared += 1 }
    func snapPoint(in rect: Rect) -> Point? {
        points.filter { rect.contains($0) }.min { a, b in
            let c = rect.center
            return (a.x - c.x) * (a.x - c.x) + (a.y - c.y) * (a.y - c.y) < (b.x - c.x) * (b.x - c.x) + (b.y - c.y) * (b.y - c.y)
        }
    }
}

final class SnapTests: XCTestCase {
    let screen = Rect(x: 0, y: 0, width: 1000, height: 600)

    func testSnapsToNearestElementInsideRectAndToggles() {
        let snap = FakeSnap()
        snap.points = [Point(x: 100, y: 100), Point(x: 240, y: 140), Point(x: 900, y: 500)]
        let e = PointerEngine(snapping: true, snapProvider: snap)
        _ = e.activate(screen: screen)
        XCTAssertEqual(snap.prepared, 1)
        // Top-left quadrant (0,0,500,300), centre (250,150): nearest element inside is (240,140).
        XCTAssertEqual(e.handle(KeyPress(.i)), [.warp(Point(x: 240, y: 140)), .redraw])
        XCTAssertEqual(e.target, Point(x: 240, y: 140))
        // Toggle off: back to the geometric centre.
        XCTAssertEqual(e.handle(KeyPress(.a)), [.warp(Point(x: 250, y: 150)), .redraw])
        XCTAssertFalse(e.snapping)
        // Toggle on, then a quadrant with no elements inside falls back to its centre.
        _ = e.handle(KeyPress(.a))
        XCTAssertEqual(e.handle(KeyPress(.o)), [.warp(Point(x: 375, y: 75)), .redraw])
    }

    func testNoProviderMeansCentre() {
        let e = PointerEngine(snapping: true)
        _ = e.activate(screen: screen)
        XCTAssertEqual(e.handle(KeyPress(.i)), [.warp(Point(x: 250, y: 150)), .redraw])
        XCTAssertEqual(e.handle(KeyPress(.a)), [.warp(Point(x: 250, y: 150)), .redraw]) // toggles, no visible effect
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

    func testDragRestartsSearchAndEscapeCancels() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.i)); _ = e.handle(KeyPress(.i)) // depth 2, target (125,75)
        XCTAssertEqual(e.handle(KeyPress(.v)), [.mouseDown(.left), .redraw])
        XCTAssertEqual(e.session?.depth, 0)             // search restarted from the whole screen
        XCTAssertEqual(e.target, Point(x: 125, y: 75))   // pointer did not move
        XCTAssertEqual(e.dragOrigin, Point(x: 125, y: 75))
        _ = e.handle(KeyPress(.k))                        // drag towards bottom-right
        _ = e.handle(KeyPress(.s))                        // scrolling while dragging is allowed
        XCTAssertEqual(e.handle(KeyPress(.j)), [.scroll(dx: 0, dy: 60)])
        XCTAssertTrue(e.dragging)
        // Escape abandons the drag, returns the pointer to the origin, and stays active.
        XCTAssertEqual(e.handle(KeyPress(.escape)), [.cancelDrag(origin: Point(x: 125, y: 75)), .redraw])
        XCTAssertFalse(e.dragging)
        XCTAssertTrue(e.isActive)
        XCTAssertEqual(e.target, Point(x: 125, y: 75))
        XCTAssertEqual(e.handle(KeyPress(.escape)), [.hideOverlay])
    }

    func testTopKeyAndDragWithoutRestart() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.i)); _ = e.handle(KeyPress(.i))
        XCTAssertEqual(e.handle(KeyPress(.u, [.shift])), [.warp(Point(x: 500, y: 300)), .redraw])
        XCTAssertEqual(e.session?.depth, 0)
        XCTAssertEqual(e.handle(KeyPress(.delete, [.shift])), []) // already at the top
        e.dragRestartsSearch = false
        _ = e.handle(KeyPress(.i)); _ = e.handle(KeyPress(.i))
        _ = e.handle(KeyPress(.v))
        XCTAssertEqual(e.session?.depth, 2) // descent kept for extending a selection
    }

    func testDeactivateWhileDraggingReleasesButton() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.v))
        XCTAssertEqual(e.deactivate(), [.mouseUp(.left), .hideOverlay])
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

    func testNudgeMode() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.i)) // target (250,150)
        XCTAssertEqual(e.handle(KeyPress(.n)), [.redraw])
        XCTAssertEqual(e.mode, .nudge)
        XCTAssertEqual(e.handle(KeyPress(.l)), [.warp(Point(x: 255, y: 150)), .redraw])
        XCTAssertEqual(e.handle(KeyPress(.downArrow)), [.warp(Point(x: 255, y: 155)), .redraw])
        XCTAssertEqual(e.handle(KeyPress(.h, [.shift])), [.warp(Point(x: 254, y: 155)), .redraw])
        _ = e.handle(KeyPress(.four))
        XCTAssertEqual(e.handle(KeyPress(.k)), [.warp(Point(x: 254, y: 135)), .redraw])
        XCTAssertEqual(e.handle(KeyPress(.i)), []) // quadrant keys inactive here
        _ = e.handle(KeyPress(.nine)); _ = e.handle(KeyPress(.nine)); _ = e.handle(KeyPress(.nine))
        XCTAssertEqual(e.handle(KeyPress(.l)), [.warp(Point(x: 999, y: 135)), .redraw]) // clamped to the screen
        XCTAssertEqual(e.handle(KeyPress(.n)), [.redraw])
        XCTAssertEqual(e.mode, .pointer)
        XCTAssertEqual(e.session?.depth, 1) // the descent is untouched
        XCTAssertTrue(e.help.first?.title == "POINTER")
        XCTAssertTrue(e.help.flatMap(\.rows).contains { $0.keys.contains("←") })
    }

    func testRulerLifecycle() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.i)) // target (250,150)
        XCTAssertEqual(e.handle(KeyPress(.r)), [.redraw])
        XCTAssertEqual(e.mode, .ruler)
        XCTAssertEqual(e.ruler, Ruler(screenIndex: 0, y: 150, height: 32))
        XCTAssertEqual(e.ruler?.band(on: screen), Rect(x: 0, y: 134, width: 1000, height: 32))
        _ = e.handle(KeyPress(.five))
        XCTAssertEqual(e.handle(KeyPress(.j)), [.redraw])
        XCTAssertEqual(e.ruler?.y, 150 + 5 * 32) // moves by its own height
        _ = e.handle(KeyPress(.rightBracket))
        XCTAssertEqual(e.ruler?.height, 36)
        _ = e.handle(KeyPress(.k))
        XCTAssertEqual(e.ruler?.y, 310 - 36)     // and the new height after resizing
        e.rulerMove = 10
        _ = e.handle(KeyPress(.k))
        XCTAssertEqual(e.ruler?.y, 274 - 10)     // explicit pixel step
        _ = e.handle(KeyPress(.j, [.shift]))
        XCTAssertEqual(e.ruler?.y, 265)          // Shift: one pixel
        _ = e.handle(KeyPress(.three))
        _ = e.handle(KeyPress(.leftBracket, [.shift]))
        XCTAssertEqual(e.ruler?.height, 33)      // Shift with a count: three pixels
        // Clamped to the screen.
        _ = e.handle(KeyPress(.nine)); _ = e.handle(KeyPress(.nine))
        _ = e.handle(KeyPress(.j))
        XCTAssertEqual(e.ruler?.y, 600)
        // Escape keeps the ruler and only asks for a redraw, not a hide.
        XCTAssertEqual(e.handle(KeyPress(.escape)), [.redraw])
        XCTAssertFalse(e.isActive)
        XCTAssertTrue(e.needsOverlay)
        XCTAssertNotNil(e.ruler)
        // Back in, r returns to the existing ruler, R removes it.
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.r))
        XCTAssertEqual(e.ruler?.y, 600)
        _ = e.handle(KeyPress(.r))
        XCTAssertEqual(e.mode, .pointer)
        _ = e.handle(KeyPress(.r, [.shift]))
        XCTAssertNil(e.ruler)
        XCTAssertEqual(e.handle(KeyPress(.escape)), [.hideOverlay])
        XCTAssertFalse(e.needsOverlay)
    }

    func testEscapeExits() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        XCTAssertEqual(e.handle(KeyPress(.escape)), [.hideOverlay])
        XCTAssertFalse(e.isActive)
        XCTAssertEqual(e.handle(KeyPress(.i)), [])
    }
}
