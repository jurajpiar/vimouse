import XCTest
@testable import VimouseCore
import PointerMode
import NudgeMode
import ScrollMode
import RulerMode

/// The modes the app ships, fresh for each test.
func standardModes() -> [Mode] { [PointerMode(), NudgeMode(), ScrollMode(), RulerMode()] }

let standardCursors: [CursorStyle] = [RingCursor(), CrosshairCursor(), DotCursor()]

extension PointerEngine {
    convenience init(keymap: KeyMap = .default) { self.init(modes: standardModes(), cursors: standardCursors, keymap: keymap) }
    var pointer: PointerMode { mode("pointer") as! PointerMode }
    var rulerMode: RulerMode { mode("ruler") as! RulerMode }
    var ruler: Ruler? { rulerMode.ruler }
    var session: BisectSession? { pointer.session }
    var snapping: Bool { pointer.snapping }
}

extension Config {
    static func parse(_ text: String) throws -> Config { try parse(text, modes: standardModes(), cursors: standardCursors) }
    static var defaults: Config { Config(modes: standardModes()) }
    static var defaultTOML: String { ConfigSchema(modes: standardModes(), cursors: standardCursors).template() }
    var scrollStep: Double { settings(ScrollMode.Settings.self, for: "scroll")!.step }
    var rulerDim: Double { settings(RulerMode.Settings.self, for: "ruler")!.dim }
    var snapEnabled: Bool { settings(PointerMode.Settings.self, for: "pointer")!.snap }
    var quadrants: [KeyPress: Quadrant] { settings(PointerMode.Settings.self, for: "pointer")!.quadrants }
    var flickWith: Modifiers? { settings(ScrollMode.Settings.self, for: "scroll")!.flickWith }
    var flickDoubleTapEnabled: Bool { settings(ScrollMode.Settings.self, for: "scroll")!.flickDoubleTapEnabled }
    var rulerRemove: Set<KeyPress> { settings(RulerMode.Settings.self, for: "ruler")!.remove }
}

let schema = ConfigSchema(modes: standardModes(), cursors: standardCursors)

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
        XCTAssertEqual(try Config.parse(Config.defaultTOML), Config.defaults)
    }

    func testEmptyFileIsDefaults() throws {
        XCTAssertEqual(try Config.parse(""), Config.defaults)
    }

    func testOverridesAndKeySpecs() throws {
        let c = try Config.parse("""
        [hotkey]
        activate = "ctrl+alt+m"
        [pointer]
        top_left = "q"
        top_right = "w"
        bottom_left = "a"
        bottom_right = "s"
        snap = false
        [actions]
        left_click = "space"
        [scroll]
        step = 24
        [ruler]
        dim = 2   # clamped
        """)
        XCTAssertEqual(c.keymap.activate, KeyPress(.m, [.control, .option]))
        XCTAssertEqual(c.quadrants[KeyPress(.q)], .topLeft)
        XCTAssertEqual(c.quadrants[KeyPress(.s)], .bottomRight)
        XCTAssertEqual(c.keymap.leftClick, [KeyPress(.space)])
        XCTAssertEqual(c.scrollStep, 24)
        XCTAssertEqual(c.rulerDim, 1)
        XCTAssertFalse(c.snapEnabled)
        XCTAssertEqual(c.keymap.rightClick, KeyMap.default.rightClick) // untouched
    }

    func testErrors() {
        XCTAssertThrowsError(try Config.parse("[pointer]\ntop_left = \"q\""))      // incomplete quadrants
        XCTAssertThrowsError(try Config.parse("[global]\nexit = \"hyper+q\""))     // unknown modifier
        XCTAssertThrowsError(try Config.parse("[scroll]\nstep = \"fast\""))     // wrong type
        XCTAssertThrowsError(try Config.parse("garbage"))                         // not TOML
    }

    func testMigrationAddsMissingAndCommentsUnknown() throws {
        let old = """
        # my notes
        [pointer]
        top_left = "q"
        top_right = "w"
        bottom_left = "a"
        bottom_right = "s"
        mystery = 1
        [scroll]
        step = 24
        """
        let (text, changed) = schema.migrate(old)
        XCTAssertTrue(changed)
        XCTAssertTrue(text.contains("# my notes"))
        XCTAssertTrue(text.contains("# Pointer mode: narrowing down"))      // section description added
        XCTAssertTrue(text.contains("top_left = \"q\"   # Pick the top-left quadrant, e.g. \"i\", \"up\".")) // short comment inline on an existing key
        XCTAssertTrue(text.contains("top_left = \"q\""))                 // user value kept
        XCTAssertFalse(text.contains("mystery = 1\n[scroll]"))              // unknown key removed from its place
        XCTAssertTrue(text.hasSuffix("# Retired settings (see CHANGELOG.md in the vimouse repository):\n# [pointer] mystery = 1\n"))
        XCTAssertTrue(text.contains("left_click = [\"return\", \"m\"]"))   // missing key appended with default
        XCTAssertTrue(text.contains("[ruler]"))                            // missing section appended
        let (t2, _) = schema.migrate("[ruler]\nstep = 20\n")
        XCTAssertTrue(t2.hasSuffix("# Retired settings (see CHANGELOG.md in the vimouse repository):\n# [ruler] step = 20\n"))
        XCTAssertFalse(t2.contains("\nstep = 20"))
        XCTAssertTrue(t2.contains("\nmove = 0"))
        // A renamed setting carries its value to the new place.
        let (t3, _) = schema.migrate("[keys]\nleft_click = \"space\"\nexit = \"q\"\n")
        XCTAssertFalse(t3.contains("[keys]"))                              // empty old section dropped
        XCTAssertFalse(t3.contains("moved to"))                            // renames are silent
        XCTAssertTrue(t3.contains("\nleft_click = \"space\"\n"))
        XCTAssertTrue(t3.contains("\nexit = \"q\"\n"))
        let c3 = try Config.parse(t3)
        XCTAssertEqual(c3.keymap.leftClick, [KeyPress(.space)])
        XCTAssertEqual(c3.keymap.exit, [KeyPress(.q)])
        XCTAssertFalse(schema.migrate(t3).changed)
        // Notes left inline by earlier versions are gathered into the retired block.
        let legacy = "[scroll]\nstep = 24\n# moved to [actions] drag (see x): drag = \"v\"\n# unknown setting, ignored (see x): foo = 1\n"
        let (t4, c4) = schema.migrate(legacy)
        XCTAssertTrue(c4)
        XCTAssertFalse(t4.contains("moved to"))
        XCTAssertTrue(t4.hasSuffix("# Retired settings (see CHANGELOG.md in the vimouse repository):\n# foo = 1\n"))
        XCTAssertFalse(schema.migrate(t4).changed)
        XCTAssertTrue(text.contains("# Darkening outside the band"))      // with its comment
        let c = try Config.parse(text)
        XCTAssertEqual(c.scrollStep, 24)
        XCTAssertEqual(c.quadrants[KeyPress(.q)], .topLeft)
        XCTAssertEqual(c.keymap.leftClick, KeyMap.default.leftClick)
        // A second migration is a no-op.
        XCTAssertFalse(schema.migrate(text).changed)
        XCTAssertFalse(schema.migrate(Config.defaultTOML).changed)
        XCTAssertTrue(schema.migrate("").changed)
        // A reworded comment replaces its earlier wording, inline or above; a user's note stays.
        let reworded = "[global]\nexit = \"escape\"   # Leave Pointer mode (releases a drag; keeps a ruler), e.g. \"escape\".\n# my own note\n# Toggle snapping to UI elements, e.g. \"a\".\nhelp = \"shift+slash\"\n"
        let (t6, _) = schema.migrate(reworded)
        XCTAssertEqual(t6.components(separatedBy: "Leave").count, 2, t6)       // one exit comment, not two
        XCTAssertFalse(t6.contains("Leave Pointer mode"))
        XCTAssertTrue(t6.contains("# my own note\n"))
        XCTAssertTrue(t6.contains("Toggle snapping"))                           // unrelated comment above help: kept
        // The old [snap] section and [drag] restart_search move into [pointer].
        let (t5, _) = schema.migrate("[snap]\nenabled = false\n[drag]\nrestart_search = false\n")
        XCTAssertFalse(t5.contains("[snap]"))
        XCTAssertFalse(try Config.parse(t5).snapEnabled)
        XCTAssertFalse(try Config.parse(t5).settings(PointerMode.Settings.self, for: "pointer")!.dragRestart)
    }

    func testManualMentionsEverySetting() {
        let m = Manual.roff(modes: standardModes(), cursors: standardCursors)
        XCTAssertTrue(m.hasPrefix(".TH VIMOUSE 1"))
        for e in schema.entries { XCTAssertTrue(m.contains(".B \(e.key)"), e.key) }
        XCTAssertTrue(m.contains(".SH DEPRECATIONS"))
        XCTAssertTrue(m.contains("now [actions] left_click"))
    }

    func testColours() throws {
        let c = try Config.parse("[colours.modes]\nscroll = \"#ff0000\"\n[colours.markers]\nsnap = \"#000000\"")
        XCTAssertEqual(c.colours.mode("scroll"), "#FF0000")
        XCTAssertEqual(c.colours.snap, "#000000")
        XCTAssertEqual(c.colours.mode("pointer"), PointerMode().defaultColour)
        XCTAssertThrowsError(try Config.parse("[colours.modes]\nruler = \"red\""))
        // The flat [colours] of the first draft migrates into the sub-sections.
        let (t, _) = schema.migrate("[colours]\npointer = \"#123456\"\ndrag = \"#654321\"\n")
        XCTAssertFalse(t.contains("[colours]\n"))
        let m = try Config.parse(t)
        XCTAssertEqual(m.colours.mode("pointer"), "#123456")
        XCTAssertEqual(m.colours.drag, "#654321")
        XCTAssertFalse(schema.migrate(t).changed)
    }

    func testHoldKey() throws {
        XCTAssertNil(Config.defaults.keymap.hold)
        XCTAssertEqual(try Config.parse("[hotkey]\nhold = \"right_cmd\"").keymap.hold, .key(.rightCommand))
        XCTAssertEqual(try Config.parse("[hotkey]\nhold = \"fn\"").keymap.hold, .key(.function))
        XCTAssertEqual(try Config.parse("[hotkey]\nhold = \"cmd+shift+ctrl\"").keymap.hold, .chord([.command, .shift, .control]))
        XCTAssertEqual(HoldKey.chord([.command, .shift, .control]).label, "⌃⇧⌘")
        XCTAssertEqual(HoldKey.chord([.command, .shift]).bits, [.command, .shift])
        XCTAssertNil(try Config.parse("[hotkey]\nhold = \"\"").keymap.hold)
        XCTAssertThrowsError(try Config.parse("[hotkey]\nhold = \"space\""))
        XCTAssertThrowsError(try Config.parse("[hotkey]\nhold = \"cmd+q\""))
        XCTAssertEqual(KeyCode.rightCommand.modifierBit, .command)
        var k = KeyMap.default
        k.hold = .key(.rightCommand)
        let e = PointerEngine(keymap: k)
        e.heldActivation = true
        _ = e.activate(screen: Rect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(e.hints.contains { $0.key == "release ⌘" })
    }

    func testFlickModifier() throws {
        let c = try Config.parse("[scroll]\nflick_with = \"alt\"\nflick_double_tap = false")
        XCTAssertEqual(c.flickWith, [.option])
        XCTAssertFalse(c.flickDoubleTapEnabled)
        XCTAssertTrue(Config.defaults.flickDoubleTapEnabled)                                                        // auto, no modifier
        XCTAssertFalse(try Config.parse("[scroll]\nflick_with = \"alt\"").flickDoubleTapEnabled)          // auto, modifier set
        XCTAssertTrue(try Config.parse("[scroll]\nflick_with = \"alt\"\nflick_double_tap = true").flickDoubleTapEnabled)
        XCTAssertThrowsError(try Config.parse("[scroll]\nflick_double_tap = \"maybe\""))
        XCTAssertThrowsError(try Config.parse("[scroll]\nflick_with = \"j\""))
        let e = PointerEngine(); e.apply(c)
        _ = e.activate(screen: Rect(x: 0, y: 0, width: 100, height: 100))
        _ = e.handle(KeyPress(.s))
        XCTAssertEqual(e.handle(KeyPress(.j, [.option])), [.scrollFlick(dx: 0, dy: 1, multiplier: 1)])
        // A sided flick modifier: the event carries the generic bit too.
        let c2 = try Config.parse("[scroll]\nflick_with = \"right_alt\"")
        let e2 = PointerEngine(); e2.apply(c2)
        _ = e2.activate(screen: Rect(x: 0, y: 0, width: 100, height: 100))
        _ = e2.handle(KeyPress(.s))
        XCTAssertEqual(e2.handle(KeyPress(.j, [.option, .rightOption])), [.scrollFlick(dx: 0, dy: 1, multiplier: 1)])
        XCTAssertEqual(e2.handle(KeyPress(.j, [.option, .leftOption])), []) // wrong side: nothing
        XCTAssertEqual(e.handle(KeyPress(.j)), [.scrollStart(dx: 0, dy: 1, multiplier: 1)])
    }

    func testStartModes() throws {
        let c = try Config.parse("[hotkey]\nactivate_mode = \"scroll\"\nhold_mode = \"Ruler\"")
        XCTAssertEqual(c.activateMode, "scroll")
        XCTAssertEqual(c.holdMode, "ruler")
        XCTAssertThrowsError(try Config.parse("[hotkey]\nactivate_mode = \"flying\""))
        let e = PointerEngine()
        _ = e.activate(screen: Rect(x: 0, y: 0, width: 100, height: 100), pointer: Point(x: 10, y: 20), mode: "ruler")
        XCTAssertEqual(e.mode, "ruler")
        XCTAssertEqual(e.ruler?.y, 20)
    }

    func testEnterMode() {
        let e = PointerEngine()
        _ = e.activate(screen: Rect(x: 0, y: 0, width: 100, height: 100), pointer: Point(x: 10, y: 30), mode: "nudge")
        XCTAssertEqual(e.enter(mode: "nudge"), [])
        XCTAssertEqual(e.enter(mode: "pointer"), [.redraw])
        XCTAssertEqual(e.mode, "pointer")
        XCTAssertEqual(e.enter(mode: "flying"), [])
        XCTAssertEqual(e.enter(mode: "ruler"), [.redraw])
        XCTAssertEqual(e.ruler?.y, 30)
    }

    func testConfigUpdateSwitch() throws {
        XCTAssertTrue(Config.defaults.autoUpdate)
        XCTAssertFalse(try Config.parse("[config]\nupdate = false").autoUpdate)
        XCTAssertThrowsError(try Config.parse("[config]\nupdate = 1"))
    }

    func testEverySettingAndSectionHasAComment() {
        for e in schema.entries { XCTAssertFalse(e.comment.isEmpty, "\(e.section).\(e.key)") }
        for s in schema.sections { XCTAssertNotNil(schema.sectionComments[s], s) }
    }

    func testArrowKeysAndLabels() throws {
        let c = try Config.parse("""
        [scroll]
        down = "down"
        up = ["k", "up"]
        """)
        let e = PointerEngine(); e.apply(c)
        _ = e.activate(screen: Rect(x: 0, y: 0, width: 100, height: 100))
        _ = e.handle(KeyPress(.s))
        XCTAssertEqual(e.handle(KeyPress(.downArrow)), [.scrollStart(dx: 0, dy: 1, multiplier: 1)])
        XCTAssertEqual(e.handle(KeyPress(.upArrow)), [.scrollStart(dx: 0, dy: -1, multiplier: 1)])
        XCTAssertEqual(e.hints.first?.key, "↓k hl")
        XCTAssertEqual(KeyPress(.tab, [.shift]).label, "⇧⇥")
        XCTAssertEqual(KeyPress(.space, [.command, .shift]).label, "⇧⌘␣")
    }

    func testSidedModifiers() throws {
        let rs = KeyPress.parse("right_shift+r")!
        XCTAssertEqual(rs.modifiers, [.rightShift])
        XCTAssertTrue(rs.matches(event: KeyPress(.r, [.shift, .rightShift])))
        XCTAssertFalse(rs.matches(event: KeyPress(.r, [.shift, .leftShift])))
        XCTAssertFalse(rs.matches(event: KeyPress(.r)))
        let any = KeyPress.parse("shift+r")!
        XCTAssertTrue(any.matches(event: KeyPress(.r, [.shift, .leftShift])))
        XCTAssertTrue(any.matches(event: KeyPress(.r, [.shift, .rightShift])))
        XCTAssertFalse(any.matches(event: KeyPress(.r, [.shift, .command, .leftCommand, .leftShift])))
        XCTAssertEqual(rs.label, "R⇧r")
        // Config: a sided binding and a sided hotkey.
        let c = try Config.parse("[ruler]\nremove = \"right_shift+r\"\n[hotkey]\nactivate = \"cmd+left_shift+ctrl+space\"")
        XCTAssertTrue(c.rulerRemove.has(KeyPress(.r, [.shift, .rightShift])))
        XCTAssertFalse(c.rulerRemove.has(KeyPress(.r, [.shift, .leftShift])))
        XCTAssertTrue(c.keymap.activate.matches(event: KeyPress(.space, [.command, .shift, .control, .leftCommand, .leftShift, .leftControl])))
        XCTAssertFalse(c.keymap.activate.matches(event: KeyPress(.space, [.command, .shift, .control, .leftCommand, .rightShift, .leftControl])))
        // Chord held check and generic stripping.
        let chord = Modifiers.parse("cmd+left_shift")!
        XCTAssertTrue(chord.matchesHeld(in: [.command, .shift, .rightCommand, .leftShift, .option]))
        XCTAssertFalse(chord.matchesHeld(in: [.command, .shift, .rightCommand, .rightShift]))
        XCTAssertEqual(chord.generic, [.command, .shift])
        // The engine ignores side bits unless a binding names a side.
        let e = PointerEngine()
        _ = e.activate(screen: Rect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(e.handle(KeyPress(.i, [.shift, .leftShift])), []) // shifted i is not a plain i
        XCTAssertEqual(e.handle(KeyPress(.i)), [.warp(Point(x: 25, y: 25)), .redraw])
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
        let e = PointerEngine()
        e.context.services.snap = snap
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
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        XCTAssertEqual(e.handle(KeyPress(.i)), [.warp(Point(x: 250, y: 150)), .redraw])
        XCTAssertEqual(e.handle(KeyPress(.a)), [.warp(Point(x: 250, y: 150)), .redraw]) // toggles, no visible effect
    }
}

final class EngineTests: XCTestCase {
    let screen = Rect(x: 0, y: 0, width: 1000, height: 600)

    func testActivateLeavesPointerWhereItIs() {
        let e = PointerEngine()
        XCTAssertEqual(e.activate(screen: screen, pointer: Point(x: 40, y: 50)), [.showOverlay])
        XCTAssertTrue(e.isActive)
        XCTAssertEqual(e.target, Point(x: 40, y: 50))
        // Without a known position the centre is assumed.
        XCTAssertEqual(PointerEngine().activate(screen: screen), [.showOverlay])
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
        XCTAssertEqual(e.handle(KeyPress(.j)), [.scrollStart(dx: 0, dy: 1, multiplier: 45)])
        XCTAssertNil(e.pendingCount)
        XCTAssertEqual(e.handle(KeyPress(.j)), [.scrollStart(dx: 0, dy: 1, multiplier: 1)]) // count consumed
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
        XCTAssertEqual(e.handle(KeyPress(.j)), [.scrollStart(dx: 0, dy: 1, multiplier: 1)])
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
        e.pointer.settings.dragRestart = false
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
        XCTAssertEqual(e.mode, "scroll")
        XCTAssertEqual(e.handle(KeyPress(.j)), [.scrollStart(dx: 0, dy: 1, multiplier: 1)])
        XCTAssertEqual(e.handleRelease(KeyPress(.j)), [.scrollStop])
        XCTAssertEqual(e.handleRelease(KeyPress(.i)), [])
        XCTAssertEqual(e.handle(KeyPress(.k)), [.scrollStart(dx: 0, dy: -1, multiplier: 1)])
        XCTAssertEqual(e.handle(KeyPress(.l)), [.scrollStart(dx: 1, dy: 0, multiplier: 1)])
        XCTAssertEqual(e.handle(KeyPress(.d)), [.scroll(dx: 0, dy: 300)])
        XCTAssertEqual(e.handle(KeyPress(.u)), [.scroll(dx: 0, dy: -300)])
        XCTAssertEqual(e.handle(KeyPress(.i)), []) // quadrant keys inactive in scroll mode
        XCTAssertEqual(e.handle(KeyPress(.s)), [.redraw])
        XCTAssertEqual(e.mode, "pointer")
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
        XCTAssertEqual(e.mode, "nudge")
        XCTAssertEqual(e.handle(KeyPress(.l)), [.nudgeStart(dx: 1, dy: 0, multiplier: 1)])
        XCTAssertEqual(e.handleRelease(KeyPress(.l)), [.nudgeStop])
        XCTAssertEqual(e.handle(KeyPress(.downArrow)), [.nudgeStart(dx: 0, dy: 1, multiplier: 1)])
        // A second key held with the first steers diagonally at the same speed.
        let r = 1 / 2.0.squareRoot()
        XCTAssertEqual(e.handle(KeyPress(.l)), [.nudgeStart(dx: r, dy: r, multiplier: 1)])
        XCTAssertEqual(e.handleRelease(KeyPress(.downArrow)), [.nudgeStart(dx: 1, dy: 0, multiplier: 1)])
        XCTAssertEqual(e.handleRelease(KeyPress(.l)), [.nudgeStop])
        XCTAssertEqual(e.handleRelease(KeyPress(.l)), []) // not held: nothing
        e.pointerMoved(to: Point(x: 255, y: 155)) // the platform moved it
        XCTAssertEqual(e.handle(KeyPress(.h, [.shift])), [.warp(Point(x: 254, y: 155)), .redraw]) // fine: one pixel
        _ = e.handle(KeyPress(.four))
        XCTAssertEqual(e.handle(KeyPress(.k)), [.nudgeStart(dx: 0, dy: -1, multiplier: 4)])
        XCTAssertEqual(e.handle(KeyPress(.i)), []) // quadrant keys inactive here
        _ = e.handle(KeyPress(.nine)); _ = e.handle(KeyPress(.nine)); _ = e.handle(KeyPress(.nine))
        XCTAssertEqual(e.handle(KeyPress(.l, [.shift])), [.warp(Point(x: 999, y: 155)), .redraw]) // fine, clamped to the screen
        XCTAssertEqual(e.handle(KeyPress(.n)), [.redraw])
        XCTAssertEqual(e.mode, "pointer")
        XCTAssertEqual(e.session?.depth, 1) // the descent is untouched
        XCTAssertTrue(e.help.first?.title == "POINTER")
        XCTAssertTrue(e.help.flatMap(\.rows).contains { $0.keys.contains("←") })
    }

    /// Lines 20 px tall every 24 px from y = 100 to 300, only in the column x < 500,
    /// inside a window (0,80)-(500,400).
    final class FakeLines: LineProvider {
        func window(at x: Double, y: Double) -> Rect? { x < 500 ? Rect(x: 0, y: 80, width: 500, height: 320) : nil }
        func textLine(at x: Double, y: Double, direction: Int, on screen: Rect) -> Rect? {
            guard x < 500 else { return nil }
            let lines = stride(from: 100.0, through: 300, by: 24).map { Rect(x: 0, y: $0, width: 400, height: 20) }
            switch direction {
            case 0: return lines.first { y >= $0.y && y < $0.maxY }
            case 1: return lines.first { $0.y > y }
            default: return lines.last { $0.maxY <= y }
            }
        }
    }

    func testRulerFollowsTextLines() {
        let e = PointerEngine()
        let fake = FakeLines()
        e.context.services.lines = fake
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.i)) // (250,150): on the line at y 148..168
        XCTAssertEqual(e.handle(KeyPress(.r)), [.warp(Point(x: 250, y: 158)), .redraw]) // seated on the line, pointer with it
        XCTAssertEqual(e.ruler?.y, 158)
        XCTAssertEqual(e.ruler?.height, 24) // 20 + 2 px padding each side
        XCTAssertEqual(e.ruler?.band(on: screen), Rect(x: 0, y: 146, width: 500, height: 24)) // as wide as the window
        XCTAssertEqual(e.ruler?.dimArea(on: screen), Rect(x: 0, y: 80, width: 500, height: 320))
        e.rulerMode.settings.width = .line
        _ = e.handle(KeyPress(.j)); _ = e.handle(KeyPress(.k))
        XCTAssertEqual(e.ruler?.band(on: screen).width, 402) // the line plus padding, clipped at the screen edge
        e.rulerMode.settings.width = .window
        _ = e.handle(KeyPress(.j))
        XCTAssertEqual(e.ruler?.y, 182)
        _ = e.handle(KeyPress(.two)); _ = e.handle(KeyPress(.k))
        XCTAssertEqual(e.ruler?.y, 134)
        _ = e.handle(KeyPress(.j, [.shift])) // fine moves ignore lines
        XCTAssertEqual(e.ruler?.y, 135)
        _ = e.handle(KeyPress(.a)) // lines off: back to stepping by height
        XCTAssertFalse(e.rulerMode.snapping)
        _ = e.handle(KeyPress(.j))
        XCTAssertEqual(e.ruler?.y, 135 + 24)
        _ = e.handle(KeyPress(.a)) // on again: re-seat on the line under the band
        XCTAssertEqual(e.ruler?.y, 158)
        // Past the last line: fall back to a height step.
        for _ in 0..<10 { _ = e.handle(KeyPress(.j)) }
        XCTAssertEqual(e.ruler?.y, 302 + 4 * 24) // six line steps, then four height steps
        // No text under the column: plain steps from the start.
        let e2 = PointerEngine()
        e2.context.services.lines = fake
        _ = e2.activate(screen: screen)
        _ = e2.handle(KeyPress(.o)) // (750,150)
        _ = e2.handle(KeyPress(.r))
        XCTAssertEqual(e2.ruler, Ruler(screenIndex: 0, x: 750, y: 150, height: 32)) // no window either: the whole screen
        XCTAssertEqual(e2.ruler?.band(on: screen).width, 1000)
    }

    func testRulerLifecycle() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.i)) // target (250,150)
        XCTAssertEqual(e.handle(KeyPress(.r)), [.redraw])
        XCTAssertEqual(e.mode, "ruler")
        XCTAssertEqual(e.ruler, Ruler(screenIndex: 0, x: 250, y: 150, height: 32))
        XCTAssertEqual(e.ruler?.band(on: screen), Rect(x: 0, y: 134, width: 1000, height: 32))
        _ = e.handle(KeyPress(.five))
        XCTAssertEqual(e.handle(KeyPress(.j)), [.warp(Point(x: 250, y: 310)), .redraw]) // the pointer rides along
        XCTAssertEqual(e.ruler?.y, 150 + 5 * 32) // moves by its own height
        XCTAssertEqual(e.target, Point(x: 250, y: 310))
        _ = e.handle(KeyPress(.rightBracket))
        XCTAssertEqual(e.ruler?.height, 36)
        _ = e.handle(KeyPress(.k))
        XCTAssertEqual(e.ruler?.y, 310 - 36)     // and the new height after resizing
        e.rulerMode.settings.move = 10
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
        // Switching to Scroll keeps the band; Escape from there keeps it too (it was kept on purpose).
        _ = e.handle(KeyPress(.s))
        XCTAssertNotNil(e.ruler)
        XCTAssertEqual(e.handle(KeyPress(.escape)), [.redraw])
        XCTAssertFalse(e.isActive)
        XCTAssertTrue(e.needsOverlay)
        // Back in, r returns to the existing band; r again removes it and goes back.
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.r))
        XCTAssertEqual(e.ruler?.y, 600)
        _ = e.handle(KeyPress(.r))
        XCTAssertEqual(e.mode, "pointer")
        XCTAssertNil(e.ruler)
        // Escape straight out of Ruler mode removes the band as well.
        _ = e.handle(KeyPress(.r))
        XCTAssertEqual(e.handle(KeyPress(.escape)), [.hideOverlay])
        XCTAssertNil(e.ruler)
        XCTAssertFalse(e.needsOverlay)
        // A kept band goes with Shift+r from any mode.
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.r)); _ = e.handle(KeyPress(.n))
        XCTAssertNotNil(e.ruler)
        _ = e.handle(KeyPress(.r, [.shift]))
        XCTAssertNil(e.ruler)
    }

    func testEscapeExits() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        XCTAssertEqual(e.handle(KeyPress(.escape)), [.hideOverlay])
        XCTAssertFalse(e.isActive)
        XCTAssertEqual(e.handle(KeyPress(.i)), [])
    }
}

final class PluginTests: XCTestCase {
    let screen = Rect(x: 0, y: 0, width: 1000, height: 600)

    func testEnabledModesAndDefault() throws {
        let c = try Config.parse("[modes]\nenabled = [\"nudge\", \"scroll\"]")
        XCTAssertEqual(c.enabledModes, ["nudge", "scroll"])
        XCTAssertThrowsError(try Config.parse("[modes]\nenabled = [\"flying\"]"))
        XCTAssertThrowsError(try Config.parse("[modes]\nenabled = []"))
        let e = PointerEngine()
        e.apply(c)
        XCTAssertEqual(e.defaultMode, "nudge")
        _ = e.activate(screen: screen, pointer: Point(x: 10, y: 10))
        XCTAssertEqual(e.mode, "nudge")
        XCTAssertEqual(e.handle(KeyPress(.r)), [])            // ruler is disabled: its toggle does nothing
        XCTAssertEqual(e.handle(KeyPress(.s)), [.redraw])
        XCTAssertEqual(e.mode, "scroll")
        XCTAssertEqual(e.handle(KeyPress(.s)), [.redraw])     // own toggle: back to the previous mode
        XCTAssertEqual(e.mode, "nudge")
        XCTAssertEqual(e.handle(KeyPress(.n)), [])            // the default's own toggle: nothing
        XCTAssertEqual(e.activate(screen: screen, mode: "ruler"), [.showOverlay]) // disabled start mode: default
        XCTAssertEqual(e.mode, "nudge")
    }

    func testSceneDescribesWhatToDraw() {
        let e = PointerEngine()
        XCTAssertNil(e.scene())
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.i))
        let s = e.scene()!
        XCTAssertEqual(s.modeName, "POINTER")
        XCTAssertEqual(s.modeColour, PointerMode().defaultColour)
        XCTAssertEqual(s.focus, Point(x: 250, y: 150))
        XCTAssertTrue(s.drawables.contains(.outline(Rect(x: 0, y: 0, width: 500, height: 300), colour: s.modeColour, alpha: 1, width: 2)))
        XCTAssertTrue(s.drawables.contains { if case .label("i", _, _, _) = $0 { return true } else { return false } })
        XCTAssertTrue(s.hints.contains { $0.action == "nudge" })
        XCTAssertNil(s.help)
        XCTAssertEqual(e.scene(showHelp: true)?.help?.first?.title, "POINTER")
        // A ruler stays in the scene after the engine goes idle, dimming its screen.
        _ = e.handle(KeyPress(.r)); _ = e.handle(KeyPress(.s))
        _ = e.handle(KeyPress(.escape))
        let idle = e.scene()!
        XCTAssertNil(idle.modeName)
        XCTAssertTrue(idle.drawables.contains { if case .dim(0, _, _, 0.35) = $0 { return true } else { return false } })
        XCTAssertTrue(idle.hints.isEmpty)
    }

    func testRemovingTheBandInRulerModeReturnsToDefault() {
        let e = PointerEngine()
        _ = e.activate(screen: screen)
        _ = e.handle(KeyPress(.r))
        XCTAssertEqual(e.mode, "ruler")
        XCTAssertEqual(e.handle(KeyPress(.r, [.shift])), [.redraw, .redraw])
        XCTAssertEqual(e.mode, "pointer")
        XCTAssertNil(e.ruler)
        // Entered from Nudge, removing the band returns to Nudge, not the default.
        _ = e.handle(KeyPress(.n)); _ = e.handle(KeyPress(.r))
        XCTAssertEqual(e.handle(KeyPress(.r, [.shift])), [.redraw, .redraw])
        XCTAssertEqual(e.mode, "nudge")
        _ = e.handle(KeyPress(.n))
        // From another mode the band goes but the mode stays.
        _ = e.handle(KeyPress(.r)); _ = e.handle(KeyPress(.s))
        XCTAssertEqual(e.handle(KeyPress(.r, [.shift])), [.redraw])
        XCTAssertEqual(e.mode, "scroll")
        XCTAssertNil(e.ruler)
    }

    func testCursorStyle() throws {
        let e = PointerEngine()
        _ = e.activate(screen: screen, pointer: Point(x: 10, y: 10))
        XCTAssertTrue(e.scene()!.drawables.contains(.ring(Point(x: 10, y: 10), radius: 18, colour: PointerMode().defaultColour, alpha: 1, width: 3)))
        e.apply(try Config.parse("[cursor]\nstyle = \"crosshair\"\nsize = 20\ncolour = \"#ffffff\""))
        XCTAssertTrue(e.scene()!.drawables.contains(.crosshair(Point(x: 10, y: 10), size: 20, colour: "#FFFFFF", alpha: 1, width: 2)))
        e.apply(try Config.parse("[cursor]\nstyle = \"\""))
        XCTAssertFalse(e.scene()!.drawables.contains { if case .ring = $0 { return true }; if case .crosshair = $0 { return true }; return false })
        XCTAssertThrowsError(try Config.parse("[cursor]\nstyle = \"arrow\""))
        XCTAssertThrowsError(try Config.parse("[cursor]\ncolour = \"red\""))
    }

    func testEveryModeSchemaStaysInItsSection() {
        for m in standardModes() {
            for entry in m.schema { XCTAssertEqual(entry.section, m.id) }
            XCTAssertFalse(m.summary.isEmpty)
            XCTAssertTrue(Colours.isValid(m.defaultColour), m.id)
            XCTAssertNoThrow(try m.parseSettings([:]))
        }
    }
}
