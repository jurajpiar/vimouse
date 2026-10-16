import Foundation

/// The manual, generated from the schema and the default key map so it never drifts
/// from the code. Rendered as a man page (roff); view with `man <path>`.
public enum Manual {
    public static let version = "0.1-dev"

    public static func roff(date: String = "2026-10") -> String {
        var o = ""
        func line(_ s: String) { o += s + "\n" }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "-", with: "\\-")
        }
        let k = KeyMap.default
        func keys(_ set: Set<KeyPress>) -> String { set.map(\.label).sorted().joined(separator: ", ") }

        line(".TH VIMOUSE 1 \"\(date)\" \"vimouse \(version)\" \"User Commands\"")
        line(".SH NAME")
        line("vimouse \\- drive the mouse pointer from the keyboard")
        line(".SH SYNOPSIS")
        line(".B vimouse")
        line(".PP")
        line("A menu bar app. Press the activation hotkey (default \(esc(k.activate.label))) to enter Pointer mode.")
        line(".SH DESCRIPTION")
        line("vimouse divides the screen into four quadrants; one key picks a quadrant, which is divided again, until the pointer is on the target. Clicks, drags, scrolling, a reading ruler and pixel nudging are available at any depth. A status strip at the screen edge lists the keys valid at any moment; hold the help key for the full map.")
        line(".PP")
        line("Counts work as in vi: digits typed before a command repeat or scale it (45j scrolls 45 steps, 3\\(:backspace: goes up three levels, 3\\(:return: triple-clicks, 2\\(:tab: switches to display 2).")

        line(".SH MODES")
        let modes: [(String, String)] = [
            ("Pointer", "Quadrant navigation. Keys: \(esc([Quadrant.topLeft, .topRight, .bottomLeft, .bottomRight].map { k.label(for: $0) }.joined(separator: " "))) pick a quadrant; \(esc(keys(k.up))) up one level; \(esc(keys(k.top))) back to the whole screen; \(esc(keys(k.snapToggle))) toggles snapping to UI elements."),
            ("Nudge", "Pixel movement for the final adjustment. \(esc(keys(k.nudgeToggle))) enters and leaves; \(esc(keys(k.nudgeLeft))) / \(esc(keys(k.nudgeDown))) / \(esc(keys(k.nudgeUp))) / \(esc(keys(k.nudgeRight))) move; Shift held moves one pixel."),
            ("Scroll", "Scrolls the content under the pointer. \(esc(keys(k.scrollToggle))) enters and leaves; \(esc(keys(k.scrollDown))) / \(esc(keys(k.scrollUp))) / \(esc(keys(k.scrollLeft))) / \(esc(keys(k.scrollRight))) scroll; \(esc(keys(k.scrollHalfDown))) / \(esc(keys(k.scrollHalfUp))) half a screen. Key repeat works here."),
            ("Ruler", "A reading band that dims everything except the line being read. \(esc(keys(k.rulerToggle))) creates it at the pointer and enters the mode (again: back to Pointer, band stays); \(esc(keys(k.rulerDown))) / \(esc(keys(k.rulerUp))) move it by its own height; \(esc(keys(k.rulerShrink))) / \(esc(keys(k.rulerGrow))) resize; Shift held makes one-pixel changes; \(esc(keys(k.rulerRemove))) removes the band. The band survives leaving Pointer mode."),
        ]
        for (name, text) in modes {
            line(".TP")
            line(".B \(name)")
            line(text)
        }

        line(".SH ACTIONS")
        line("Available in every mode.")
        let actions: [(String, String)] = [
            (keys(k.leftClick), "left click and exit; a count sets the click count (2 double, 3 triple)"),
            (keys(k.clickStay), "left click and stay"),
            (keys(k.doubleClick), "double click and exit"),
            (keys(k.rightClick), "right click (context menu) and exit"),
            (keys(k.middleClick), "middle click and exit"),
            ("Shift, Cmd or Option held with a click key", "modifier click"),
            (keys(k.dragToggle), "press the left button (drag or text selection); press again, or a click key, to release. Escape cancels the drag and returns the pointer to where the button went down"),
            (keys(k.nextScreen) + " / " + keys(k.previousScreen), "next / previous display; with a count, that display"),
            (keys(k.help), "hold for the full key map"),
            (keys(k.exit), "exit (first cancels a pending count or an active drag)"),
        ]
        for (key, text) in actions {
            line(".TP")
            line(".B \(esc(key))")
            line(text)
        }

        line(".SH CONFIGURATION")
        line("Settings live in")
        line(".I ~/.config/vimouse/config.toml")
        line("(created on first run) and are reloaded within a second of saving. Keys are named by their position on a US layout: letters, digits, space, return, tab, escape, backspace, left, right, up, down, pageup, pagedown, home, end, comma, period, slash, leftbracket, rightbracket, minus, equal; modifiers cmd, shift, ctrl, alt are joined with \"+\" (\"cmd+shift+space\"); a list binds several keys to one action ([\"j\", \"down\"]).")
        line(".PP")
        line("On start, unless [config] update = false, settings missing from the file are appended with their defaults and unknown or superseded ones are moved to a \"Retired settings\" block at the end. The file")
        line(".I ~/.config/vimouse/config.example.toml")
        line("is always rewritten with the current defaults.")
        for section in ConfigSchema.sections {
            line(".SS [\(section)]")
            line(esc(ConfigSchema.sectionComments[section] ?? ""))
            for e in ConfigSchema.entries where e.section == section {
                line(".TP")
                line(".B \(esc(e.key))")
                line("\(esc(e.comment)) Default: \(esc(e.defaultValue))")
            }
        }

        line(".SH DEPRECATIONS")
        if ConfigSchema.renamed.isEmpty && ConfigSchema.superseded.isEmpty {
            line("None.")
        } else {
            line("Settings that moved (values are carried over automatically):")
            for (old, new) in ConfigSchema.renamed.sorted(by: { $0.key < $1.key }) {
                let o = old.split(separator: "."), n = new.split(separator: ".")
                line(".TP")
                line(".B [\(o[0])] \(o[1])")
                line("now [\(n[0])] \(n[1])")
            }
            line(".PP")
            line("Settings that no longer exist (left in the Retired settings block):")
            for (old, note) in ConfigSchema.superseded.sorted(by: { $0.key < $1.key }) {
                let o = old.split(separator: ".")
                line(".TP")
                line(".B [\(o[0])] \(o[1])")
                line(esc(note))
            }
        }

        line(".SH FILES")
        line(".TP")
        line(".I ~/.config/vimouse/config.toml")
        line("Settings.")
        line(".TP")
        line(".I ~/.config/vimouse/config.example.toml")
        line("Current defaults with comments; rewritten on every start.")
        line(".TP")
        line(".I ~/.config/vimouse/vimouse.1")
        line("This manual; rewritten on every start. View with: man ~/.config/vimouse/vimouse.1")

        line(".SH PERMISSIONS")
        line("The keyboard event tap needs Accessibility access (System Settings > Privacy & Security > Accessibility). Apps in secure input mode (password fields, some terminals) block the tap until they leave it.")
        line(".SH LICENSE")
        line("GPL-3.0-or-later.")
        return o
    }
}
