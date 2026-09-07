import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Ui
import qs.Commons

// A Super key you click instead of press.
//
// Every remote desktop connector forwards mouse events faithfully; none of them
// reliably forward Super, because the client's own OS claims it first. So the
// modifier is offered as a pointer target rather than a key, which makes it
// connector-agnostic by construction: a browser-based client, a native VNC or
// RDP viewer and a tablet app all behave the same, because none of them are
// asked for anything they cannot do.
//
// Clicking engages the "remote" submap, in which every Super binding is
// reachable with Super dropped. See engine/remote-seat.lua.
BarWidget {
  id: root
  moduleName: "io.github.knivfjell.super-button"

  // --- tunables, set per-widget in shell.json -------------------------------
  // holdMs      how long one click keeps Super engaged before releasing
  // label       what the button reads when idle
  // countdown   show the remaining seconds while engaged
  // lockEnabled right-click latches Super open until clicked again
  readonly property int holdMs: Math.max(250, setting("holdMs", 4000))
  readonly property string idleLabel: setting("label", "SUPER")
  readonly property bool countdown: setting("countdown", true)
  readonly property bool lockEnabled: setting("lockEnabled", true)

  readonly property string submapName: "remote"

  property bool engaged: false
  property bool locked: false
  property var heldMods: []
  property int remainingMs: 0

  function lua(code) {
    if (root.bar) root.bar.run("hyprctl eval " + Util.shellQuote(code))
  }

  Loader { source: Qt.resolvedUrl("EngineInstaller.qml") }

  // The floating pad can be closed from its own ✕. This button is how it comes
  // back, so it needs to see and set the pad's enabled flag.
  property bool padEnabled: true
  property var padCfg: ({})
  property bool padCfgReady: false

  FileView {
    id: padFile
    path: Quickshell.env("HOME") + "/.config/omarchy/remote-seat.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        root.padCfg = JSON.parse(text())
        root.padEnabled = root.padCfg.enabled !== false
        root.padCfgReady = true
      } catch (e) {
        // A half-written file during someone else's save; the watcher will
        // fire again once it settles.
      }
    }
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) root.padCfgReady = true
    }
  }

  function togglePad() {
    // The pad's own config is the source of truth. Requiring an explicit
    // "enabled" key here used to make the button a silent no-op on a config
    // that had never been toggled; a missing key just means "showing". A
    // missing file means the same thing, so gate on having *looked* rather
    // than on having found something -- an empty config is a real state, not
    // a reason to refuse.
    if (!root.padCfgReady) return
    var next = JSON.parse(JSON.stringify(root.padCfg))
    next.enabled = !root.padEnabled
    root.padCfg = next
    root.padEnabled = next.enabled
    padFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  // One click in, one click out — whatever state it was already in.
  function tapHold() {
    if (root.engaged) {
      lua('require("remote-seat").leave()')
      return
    }

    root.locked = false
    root.remainingMs = root.holdMs
    lua('require("remote-seat").enter(' + root.holdMs + ')')
  }

  // Latched: stays engaged with no timer, for chaining several bindings.
  function toggleLock() {
    if (root.engaged && root.locked) {
      lua('require("remote-seat").leave()')
      return
    }

    root.locked = true
    root.remainingMs = 0
    lua('require("remote-seat").enter(0)')
  }

  function handlePress(button) {
    if (button === Qt.MiddleButton) togglePad()
    else if (button === Qt.RightButton && root.lockEnabled) toggleLock()
    else tapHold()
  }

  // The submap is the authority on whether Super is engaged: the layer can also
  // be entered from a leader key or released by its own timeout, and the button
  // has to show that rather than only what it did itself.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name) !== "submap") return

      var name = String(event.data === undefined || event.data === null ? "" : event.data).trim()
      // The layer is a family: "remote", "remote_ctrl", "remote_alt_shift"...
      // Matching only the base name would blank the button whenever a modifier
      // is latched from the pad.
      var nowEngaged = name === root.submapName || name.indexOf(root.submapName + "_") === 0
      root.heldMods = nowEngaged ? name.split("_").slice(1) : []

      if (nowEngaged === root.engaged) return
      root.engaged = nowEngaged

      if (!nowEngaged) {
        root.locked = false
        root.remainingMs = 0
        return
      }

      // Engaged by something other than this button — a leader key, or kseat.
      // Show the configured hold rather than a countdown that starts at zero.
      if (!root.locked && root.remainingMs <= 0) root.remainingMs = root.holdMs
    }
  }

  // Drives the countdown only. The authoritative timer lives in Lua, so this
  // never releases anything — it just shows how much of the hold is left.
  Timer {
    interval: 100
    repeat: true
    running: root.engaged && !root.locked && root.countdown
    onTriggered: root.remainingMs = Math.max(0, root.remainingMs - interval)
  }

  // Every state carries a two-character suffix so the button keeps one width as
  // the countdown ticks, instead of shoving the rest of the bar sideways once a
  // second. U+2007 is the figure space: blank, and exactly as wide as a digit.
  readonly property string faceText: {
    if (!engaged) return idleLabel + " \u2007"
    if (locked) return idleLabel + " ∞"
    if (!countdown) return idleLabel + " •"
    // Still engaged with the countdown spent means it is being held open by
    // something without a timer, so stop showing a zero that never moves.
    if (remainingMs <= 0) return idleLabel + " ∞"
    return idleLabel + " " + Math.min(9, Math.ceil(remainingMs / 1000))
  }

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  // Two targets, not one. Middle-click used to be the only way to bring the pad
  // back after its ✕, which is precisely the kind of dependency this whole
  // protocol exists to avoid: a browser-hosted connector need not deliver
  // button 2 at all, and Chrome claims it for autoscroll. Once the pad is
  // closed, a control you cannot click is a control that does not exist.
  //
  // So the pad toggle gets its own **left-click** target on the bar. Left-click
  // is the one pointer event every connector forwards.
  Grid {
    id: layout
    rows: root.vertical ? 2 : 1
    columns: root.vertical ? 1 : 2
    spacing: 0

    WidgetButton {
      id: button
      bar: root.bar
      text: root.faceText
      active: root.engaged
      fontSize: Style.font.caption
      horizontalMargin: 7
      tooltipText: {
        if (root.engaged) {
          var held = root.heldMods.length ? " +" + root.heldMods.join(" +").toUpperCase() : ""
          return root.locked ? "Super latched" + held + " — click to release"
                             : "Super held" + held + " — press a key"
        }
        return root.lockEnabled ? "Click: hold Super · Right-click: latch"
                                : "Click to hold Super"
      }
      onPressed: function(mouseButton) { root.handlePress(mouseButton) }
    }

    // Filled when the pad is on screen, hollow when it is not, so the bar always
    // says whether there is a pad to go back to.
    WidgetButton {
      id: padToggle
      bar: root.bar
      text: root.padEnabled ? "▣" : "▢"
      active: root.padEnabled
      fontSize: Style.font.caption
      horizontalMargin: 4
      tooltipText: (root.padEnabled ? "Hide" : "Show") + " the modifier pad"
      onPressed: function(mouseButton) { root.togglePad() }
    }
  }
}
