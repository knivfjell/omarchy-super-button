import QtQuick
import Quickshell
import Quickshell.Io

// Puts the engine where Hyprland will load it, and makes sure it is live.
//
// This is loaded by both entry points, because neither can be relied on alone:
// the bar widget is not instantiated until someone places it on the bar, and a
// user may run the pad without the button or the button without the pad. It is
// idempotent, so running twice costs one `cmp`.
//
// The engine has to run inside Hyprland's config, which QML cannot enter. So it
// is copied to ~/.local/state/omarchy/toggles/hypr — a directory Omarchy
// already require()s from hyprland.lua on every config load, after all bindings
// are registered. Nothing in ~/.config/hypr is written or patched.
//
// The file copied there is static and shipped with the plugin. Nothing is
// generated, interpolated or fetched, which is the only version of "a plugin
// installs executable Lua" that is reviewable.
Item {
  id: installer

  readonly property string enginePath: Qt.resolvedUrl("engine/remote-seat.lua").toString().replace("file://", "")
  // Must match Omarchy's own rule exactly, from default/hypr/paths.lua: honour
  // XDG_STATE_HOME, and treat it as unset when it is set but empty, per the XDG
  // spec. Get this wrong on a machine that sets it and the engine is written
  // somewhere Hyprland never looks — with no error, and nothing working.
  readonly property string stateHome: {
    var xdg = Quickshell.env("XDG_STATE_HOME")
    if (xdg === undefined || xdg === null || String(xdg) === "") return Quickshell.env("HOME") + "/.local/state"
    return String(xdg)
  }
  readonly property string dropInDir: stateHome + "/omarchy/toggles/hypr"

  function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  Process { id: proc }

  Component.onCompleted: {
    // Two reasons to reload, and the second is not obvious. Bytes changing is
    // one. The other is that the engine can be present and correct yet inert:
    // remove the plugin and add it back and the file is identical, so nothing
    // is copied, but the running config was loaded while the plugin was absent
    // and the engine orphaned itself. Reload when it is not actually live.
    proc.exec(["sh", "-c",
      "set -e; mkdir -p " + shellQuote(installer.dropInDir) + "; " +
      "src=" + shellQuote(installer.enginePath) + "; " +
      "dst=" + shellQuote(installer.dropInDir + "/remote-seat.lua") + "; " +
      "changed=0; cmp -s \"$src\" \"$dst\" || { install -m 644 \"$src\" \"$dst\"; changed=1; }; " +
      "live=$(hyprctl repl 'local M = package.loaded[\"remote-seat\"] return (M and not M.orphaned) and \"yes\" or \"no\"' 2>/dev/null | tail -1); " +
      "if [ \"$changed\" = 1 ] || [ \"$live\" != yes ]; then hyprctl reload >/dev/null; fi"])
  }
}
