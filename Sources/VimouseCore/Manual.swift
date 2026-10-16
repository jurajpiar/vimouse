import Foundation

/// The manual, generated from the schema and the default key map so it never drifts
/// from the code. Rendered as a man page (roff); view with `man <path>`.
public enum Manual {
    public static let version = "0.1-dev"

    public static func roff(modes: [Mode], date: String = "2026-10") -> String {
        let schema = ConfigSchema(modes: modes)
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
        line("A menu bar app. Press the activation hotkey (default \(esc(k.activate.label))) to enter the default mode.")
        line(".SH DESCRIPTION")
        line("vimouse drives the pointer from the keyboard through modes: by default, quadrant navigation (the screen is divided into four, one key picks a quadrant, which is divided again, until the pointer is on the target), pixel nudging, scrolling and a reading ruler. Modes are plugins; [modes] enabled in the configuration chooses which are available. Clicks and drags work in every mode. A status strip at the screen edge lists the keys valid at any moment; hold the help key for the full map.")
        line(".PP")
        line("Counts work as in vi: digits typed before a command repeat or scale it (45j scrolls 45 steps, 3\\(:backspace: goes up three levels, 3\\(:return: triple-clicks, 2\\(:tab: switches to display 2).")

        line(".SH MODES")
        for m in modes {
            line(".TP")
            line(".B \(m.name.capitalized)")
            let toggle = m.toggle.isEmpty ? "" : " Enter it with \(esc(keys(m.toggle))) (again: back to the default mode)."
            line(esc(m.manual) + toggle)
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
        for section in schema.sections {
            line(".SS [\(section)]")
            line(esc(schema.sectionComments[section] ?? ""))
            for e in schema.entries where e.section == section {
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
                let o = ConfigSchema.split(old), n = ConfigSchema.split(new)
                line(".TP")
                line(".B [\(o.section)] \(o.key)")
                line("now [\(n.section)] \(n.key)")
            }
            line(".PP")
            line("Settings that no longer exist (left in the Retired settings block):")
            for (old, note) in ConfigSchema.superseded.sorted(by: { $0.key < $1.key }) {
                let o = ConfigSchema.split(old)
                line(".TP")
                line(".B [\(o.section)] \(o.key)")
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
