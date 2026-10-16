public enum MouseButton: Equatable, Sendable {
    case left, right, middle
}

/// What the platform layer must do after the engine handles a key.
/// Effects are applied in order. This is the platform's vocabulary: a mode can only ask
/// for what is listed here.
public enum Effect: Equatable, Sendable {
    case showOverlay
    case redraw
    case hideOverlay
    case warp(Point)
    case click(MouseButton, count: Int, modifiers: Modifiers)
    case mouseDown(MouseButton)
    case mouseUp(MouseButton)
    /// Abandon a drag: tell the system to cancel it and release the button back at the origin.
    case cancelDrag(origin: Point)
    /// Pixels. Positive dy reveals content below (like vim's j), positive dx content to the right.
    case scroll(dx: Double, dy: Double)
    /// A scroll key went down: direction (unit components) and multiplier (count prefix).
    /// The platform taps, accelerates while held and coasts after release.
    case scrollStart(dx: Double, dy: Double, multiplier: Double)
    /// The scroll key went up.
    case scrollStop
    /// Flick: launch a coast in this direction without a hold.
    case scrollFlick(dx: Double, dy: Double, multiplier: Double)
    /// The held nudge keys changed: the combined unit direction (diagonal when a horizontal
    /// and a vertical key are both down) and count multiplier. The platform moves one step
    /// on the first press, accelerates while any key is held, steers on later changes and
    /// stops on `nudgeStop`. The platform reports the pointer back via `pointerMoved`.
    case nudgeStart(dx: Double, dy: Double, multiplier: Double)
    case nudgeStop
}

/// The modal state machine. Pure: no platform calls, fully testable. Modes plug in
/// (see `Mode`); the engine owns what they share.
public final class PointerEngine {
    public private(set) var modes: [Mode]
    /// Ids of the modes that may be entered, in configured order; the first is the default.
    public private(set) var enabled: [String]
    public var keymap: KeyMap
    public let context = ModeContext()
    public private(set) var cursors: [CursorStyle]
    public private(set) var cursor = CursorConfig()

    /// vi-style count prefix typed so far; nil when none. Consumed by the next command.
    public private(set) var pendingCount: Int?
    /// The mode active before the current one in this activation; where a mode's own
    /// toggle (or a mode handing back) returns to.
    public private(set) var previousMode: String?
    /// True when the current activation came from the hold key (quasi-mode).
    public var heldActivation = false

    /// `modes` in registration order; `enabled` defaults to all of them.
    public init(modes: [Mode], cursors: [CursorStyle] = [], keymap: KeyMap = .default, enabled: [String]? = nil) {
        precondition(!modes.isEmpty, "at least one mode")
        self.modes = modes
        self.cursors = cursors
        self.keymap = keymap
        self.enabled = enabled ?? modes.map(\.id)
        for m in modes { context.colours.modes[m.id] = m.defaultColour }
    }

    /// Apply a (re)loaded configuration. Safe at any time.
    public func apply(_ c: Config) {
        keymap = c.keymap
        context.colours = c.colours
        cursor = c.cursor
        if let e = c.enabledModes { enabled = e.filter { id in modes.contains { $0.id == id } } }
        if enabled.isEmpty { enabled = [modes[0].id] }
        for m in modes {
            if let s = c.modeSettings[m.id] { m.apply(s) }
        }
    }

    public func mode(_ id: String) -> Mode? { modes.first { $0.id == id } }
    public var defaultMode: String { enabled[0] }

    public var isActive: Bool { context.activeMode != nil }
    /// Id of the active mode; nil when idle.
    public var mode: String? { context.activeMode }
    public var activeMode: Mode? { context.activeMode.flatMap(mode) }
    public var screens: [Rect] { context.screens }
    public var screenIndex: Int { context.screenIndex }
    public var target: Point { context.target }
    public var dragging: Bool { context.dragging }
    public var dragOrigin: Point? { context.dragOrigin }

    /// True when the overlay has anything to draw (an active mode or a persistent drawing).
    public var needsOverlay: Bool { isActive || modes.contains { $0.drawsWhileIdle } }

    // MARK: Activation

    /// Start over `screens[index]` (CG coordinates) in `mode` (the default mode when nil
    /// or not enabled). The pointer stays where it is (`pointer`); modes move it.
    public func activate(screens: [Rect], index: Int, pointer: Point? = nil, mode: String? = nil) -> [Effect] {
        precondition(!screens.isEmpty && screens.indices.contains(index))
        context.screens = screens
        context.screenIndex = index
        pendingCount = nil
        context.services.snap?.prepare(screen: screens[index])
        context.target = pointer ?? screens[index].center
        let id = mode.flatMap { enabled.contains($0) ? $0 : nil } ?? defaultMode
        previousMode = nil
        context.activeMode = id
        let before = context.target
        self.mode(id)?.activate(context)
        // A mode may place the pointer on activation (a band seating on a text line).
        return context.target == before ? [.showOverlay] : [.showOverlay, .warp(context.target)]
    }

    /// Convenience for a single screen.
    public func activate(screen: Rect, pointer: Point? = nil, mode: String? = nil) -> [Effect] {
        activate(screens: [screen], index: 0, pointer: pointer, mode: mode)
    }

    /// Switch the active mode (for example when a held activation is pinned by the
    /// hotkey, which carries its own start mode). Ignored when idle, unknown or disabled.
    public func enter(mode id: String) -> [Effect] {
        guard let current = context.activeMode, current != id, enabled.contains(id), let next = mode(id) else { return [] }
        mode(current)?.deactivate(context, exiting: false)
        // Going back to where we came from clears the trail; anything else records it.
        previousMode = id == previousMode ? nil : current
        context.activeMode = id
        let before = context.target
        next.activate(context)
        return context.target == before ? [.redraw] : [.warp(context.target), .redraw]
    }

    /// The mode to fall back to: the previous one if still enabled, else the default.
    public var returnMode: String {
        if let p = previousMode, enabled.contains(p) { return p }
        return defaultMode
    }

    /// Leave the active mode, releasing a held drag first. Idle drawings stay.
    public func deactivate() -> [Effect] {
        guard let current = context.activeMode else { return [] }
        mode(current)?.deactivate(context, exiting: true)
        context.activeMode = nil
        pendingCount = nil
        var fx: [Effect] = []
        if context.dragging {
            context.dragging = false
            context.dragOrigin = nil
            fx.append(.mouseUp(.left))
        }
        fx.append(needsOverlay ? .redraw : .hideOverlay)
        return fx
    }

    /// The platform moved the pointer on its own (a held nudge); keep the target in step.
    public func pointerMoved(to p: Point) {
        context.target = p
    }

    // MARK: Keys

    /// Handle a key press while active. Returns the effects to apply.
    /// Unbound keys are swallowed and produce no effects.
    public func handle(_ key: KeyPress) -> [Effect] {
        guard let currentID = context.activeMode, let current = mode(currentID) else { return [] }

        // Count prefix: digits accumulate until a command consumes them.
        if let d = keymap.digit(for: key) {
            pendingCount = min((pendingCount ?? 0) * 10 + d, 9999)
            return [.redraw]
        }
        let count = pendingCount
        pendingCount = nil

        if keymap.exit.has(key) {
            // As in vi, Escape with a count pending only cancels the count.
            if count != nil { return [.redraw] }
            // During a drag, Escape abandons the drag and stays in the mode.
            if context.dragging, let origin = context.dragOrigin {
                context.dragging = false
                context.dragOrigin = nil
                context.target = origin
                return [.cancelDrag(origin: origin), .redraw]
            }
            return deactivate()
        }
        // Mode toggles: another mode's key enters it; the active mode's own returns to the default.
        for id in enabled {
            guard let m = mode(id), m.toggle.has(key) else { continue }
            if id == currentID {
                return returnMode == id ? [] : enter(mode: returnMode)
            }
            return enter(mode: id)
        }
        if keymap.dragToggle.has(key) {
            context.dragging.toggle()
            if context.dragging {
                context.dragOrigin = context.target
                current.dragStarted(context)
                return [.mouseDown(.left), .redraw]
            }
            context.dragOrigin = nil
            return [.mouseUp(.left), .redraw]
        }
        if let fx = clickEffects(for: key, count: count) { return fx }
        if keymap.nextScreen.has(key) {
            // With a count, Tab jumps to that screen (1-based); without, to the next one.
            if let c = count { return switchScreen(to: c - 1) }
            return switchScreen(to: (context.screenIndex + 1) % context.screens.count)
        }
        if keymap.previousScreen.has(key) {
            if let c = count { return switchScreen(to: c - 1) }
            return switchScreen(to: (context.screenIndex - 1 + context.screens.count) % context.screens.count)
        }
        for id in enabled {
            if let fx = mode(id)?.handleAnywhere(key, count: count, context) { return fx + requestedSwitch() }
        }
        if let fx = current.handle(key, count: count, context) { return fx + requestedSwitch() }
        return count == nil ? [] : [.redraw]
    }

    /// A mode asked for a switch while handling a key.
    private func requestedSwitch() -> [Effect] {
        guard let request = context.requestedMode else { return [] }
        context.requestedMode = nil
        return enter(mode: request ?? returnMode)
    }

    /// A key went up; the active mode may end a held movement.
    public func handleRelease(_ key: KeyPress) -> [Effect] {
        activeMode?.handleRelease(key, context) ?? []
    }

    /// Click keys match on key code only; held modifiers are passed into the click.
    /// A count prefix sets the click count (3⏎ triple-clicks); it is capped at 3.
    private func clickEffects(for key: KeyPress, count: Int?) -> [Effect]? {
        let bare = KeyPress(key.code)
        let mods = key.modifiers
        let clicks = min(count ?? 1, 3)
        if keymap.leftClick.has(bare) { return clickAndExit(.left, count: clicks, mods) }
        if keymap.doubleClick.has(bare) { return clickAndExit(.left, count: 2, mods) }
        if keymap.rightClick.has(bare) { return clickAndExit(.right, count: 1, mods) }
        if keymap.middleClick.has(bare) { return clickAndExit(.middle, count: 1, mods) }
        if keymap.clickStay.has(bare) { return [.click(.left, count: clicks, modifiers: mods)] }
        return nil
    }

    private func clickAndExit(_ button: MouseButton, count: Int, _ mods: Modifiers) -> [Effect] {
        var fx: [Effect] = []
        if context.dragging {
            // A click while dragging ends the drag at the current spot.
            context.dragging = false
            context.dragOrigin = nil
            fx.append(.mouseUp(.left))
        } else {
            fx.append(.click(button, count: count, modifiers: mods))
        }
        activeMode?.deactivate(context, exiting: true)
        context.activeMode = nil
        fx.append(needsOverlay ? .redraw : .hideOverlay)
        return fx
    }

    /// Move the session to another screen. No-op for an invalid index.
    private func switchScreen(to index: Int) -> [Effect] {
        guard context.screens.indices.contains(index), index != context.screenIndex, let m = activeMode else { return [] }
        context.screenIndex = index
        context.target = context.screens[index].center
        context.services.snap?.prepare(screen: context.screens[index])
        m.screenChanged(context)
        return [.warp(context.target), .redraw]
    }

    // MARK: Discoverability

    /// The keys valid right now, for the status strip. Labels come from the bindings,
    /// so a rebind (j -> down arrow) shows as "↓" here and inside the rectangles.
    public var hints: [(key: String, action: String)] {
        guard let m = activeMode else { return [] }
        let k = keymap
        func l(_ set: Set<KeyPress>) -> String { KeyMap.label(of: set) }
        var h = m.hints(context)
        h.append((l(k.leftClick), "click"))
        h.append((l(k.clickStay), "click+stay"))
        h.append((l(k.dragToggle), context.dragging ? "drop" : "drag"))
        for id in enabled where id != m.id {
            guard let other = mode(id), !other.toggle.isEmpty else { continue }
            h.append((l(other.toggle), other.id))
        }
        if context.screens.count > 1 { h.append((l(k.nextScreen) + " / n" + l(k.nextScreen), "screen")) }
        h.append((l(k.help), "help"))
        let exitAction = pendingCount != nil ? "cancel count" : (context.dragging ? "cancel drag" : "exit")
        if let hold = k.hold, heldActivation {
            h.append(("release " + hold.label, context.dragging ? "drop+exit" : "exit"))
            h.append((k.activate.label, "pin"))
        }
        h.append((l(k.exit), exitAction))
        return h
    }

    /// Every binding, grouped, for the hold-? help panel. The current mode's group comes first.
    public var help: [(title: String, rows: [(keys: String, action: String)])] {
        let k = keymap
        func all(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: " ") }
        var groups: [(String, [(String, String)])] = []
        for id in enabled {
            guard let m = mode(id) else { continue }
            var rows = m.help(context).map { ($0.keys, $0.action) }
            if !m.toggle.isEmpty { rows.append((all(m.toggle), "\(id) mode (again: back to the previous mode)")) }
            groups.append((m.name, rows))
        }
        let shared: [(String, String)] = [
            (all(k.leftClick), "left click and exit (count: double/triple)"),
            (all(k.clickStay), "left click and stay"),
            (all(k.doubleClick), "double click and exit"),
            (all(k.rightClick), "right click and exit"),
            (all(k.middleClick), "middle click and exit"),
            ("⇧ ⌘ ⌥ + click key", "modifier click"),
            (all(k.dragToggle), "press / release left button (drag, select)"),
            ("0-9", "count prefix for the next command"),
            (all(k.nextScreen) + " / " + all(k.previousScreen), "next / previous display (count: that display)"),
            (all(k.help), "hold for this help"),
            (all(k.exit), "exit (cancels a pending count or a drag first)"),
        ]
        groups.append(("ANY MODE", shared))
        if let name = activeMode?.name, let i = groups.firstIndex(where: { $0.0 == name }) { groups.insert(groups.remove(at: i), at: 0) }
        return groups.map { (title: $0.0, rows: $0.1.map { (keys: $0.0, action: $0.1) }) }
    }

    /// What the overlay should show; nil when nothing.
    public func scene(showHelp: Bool = false) -> Scene? {
        guard needsOverlay else { return nil }
        var drawables: [Drawable] = []
        for m in modes where m.drawsWhileIdle && m.id != context.activeMode {
            drawables += m.draw(context, active: false)
        }
        let active = activeMode
        if let active {
            drawables += active.draw(context, active: true)
            if let style = cursors.first(where: { $0.id == cursor.style }) {
                let colour = cursor.colour.isEmpty ? context.colour(of: active.id) : cursor.colour
                drawables += style.draw(at: context.target, size: cursor.size, colour: colour)
            }
            if context.dragging, let o = context.dragOrigin {
                if active.showsDragLine {
                    drawables.append(.line(o, context.target, colour: context.colours.drag, alpha: 0.4, width: 1, dashed: true))
                }
                drawables.append(.dot(o, radius: 4, colour: context.colours.drag, alpha: 0.8))
            }
        }
        let colour = active.map { context.colour(of: $0.id) } ?? context.colours.mode(defaultMode)
        return Scene(
            screens: context.screens,
            activeScreen: context.screenIndex,
            modeName: active?.name,
            modeColour: colour,
            dragging: context.dragging,
            pendingCount: pendingCount,
            focus: context.target,
            hints: active == nil ? [] : hints.map { Scene.HintEntry(key: $0.key, action: $0.action) },
            help: showHelp && active != nil ? help.map { Scene.HelpGroup(title: $0.title, rows: $0.rows.map { Scene.HelpRow(keys: $0.keys, action: $0.action) }) } : nil,
            drawables: drawables,
            colours: context.colours
        )
    }
}
