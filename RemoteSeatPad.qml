import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

// A floating pad of clickable modifiers, placeable anywhere in the workspace.
//
// Remote desktop connectors forward mouse events faithfully and modifier chords
// unreliably: the controlling machine's OS and browser claim Super, Alt+Tab and
// Ctrl+T before the page ever sees them. So the modifiers are offered as pointer
// targets and the chord is assembled on this side.
//
// The pad has two modes, because "send a modifier" means two different things.
//
// WM mode drives Hyprland's own bindings. The modifiers read "+CTRL" rather
// than "CTRL" because they are additive to Super, not independent: latching
// CTRL moves the compositor into the "remote_ctrl" submap, where the
// SUPER+CTRL+* bindings answer to bare keys. There is no Super-less layer, and
// clicking +CTRL alone engages Super too.
//
// APP mode sends the chord to the focused window instead. There the modifiers
// are independent and read "CTRL", because Ctrl+W means Ctrl+W. This is the
// only way to reach chords the *client* eats — Chrome's Ctrl+T/W/L, Windows'
// Alt+Tab — in an application running on this machine, since those never left
// the controlling PC.
//
// Which mode is armed is visible in the submap name ("remote_ctrl" against
// "remote_app_ctrl"), so the pad still reads its latch state from the
// compositor rather than tracking any of it here.
//
// The window spans the screen so the pad can sit at any coordinate, but its
// input region is masked to the pad itself — everything else stays clickable.
Item {
  id: root

  property var cfg: ({})
  property bool ready: false

  function opt(name, fallback) {
    var v = cfg ? cfg[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  readonly property bool enabled: opt("enabled", true)
  readonly property bool vertical: opt("orientation", "horizontal") === "vertical"
  readonly property int btnW: opt("buttonWidth", 60)
  readonly property int btnH: opt("buttonHeight", 34)
  readonly property int fontSize: opt("fontSize", 11)
  readonly property int spacing: opt("spacing", 5)
  readonly property int radius: opt("radius", 6)
  readonly property real padOpacity: opt("opacity", 0.92)
  readonly property int holdMs: Math.max(250, opt("holdMs", 4000))
  readonly property var keys: opt("keys", ["SUPER", "CTRL", "ALT", "SHIFT"])

  // Live position. Seeded from the file, moved by dragging, written back on
  // release so the placement survives a restart.
  property int posX: 0
  property int posY: 0

  // --- compositor state, derived from the submap name ------------------------
  // The submap encodes the whole latch: "remote_ctrl_shift" means engaged with
  // CTRL and SHIFT held. Reading it back beats tracking state here, because the
  // layer can also be driven from a leader key, from kseat, or by its timeout.
  property string submap: ""
  readonly property bool engaged: submap === "remote" || submap.indexOf("remote_") === 0
  // The app family is a sub-prefix of the same namespace, so it has to be
  // tested before the mods are split off: "remote_app_ctrl" holds ctrl, not
  // "app" and "ctrl".
  readonly property bool appLayer: submap.indexOf("remote_app") === 0
  readonly property var heldMods: engaged ? submap.split("_").slice(appLayer ? 2 : 1) : []

  // Which mechanism the buttons drive. Persisted, because it is a preference
  // rather than compositor state — nothing is latched when the pad is idle.
  readonly property string mode: opt("mode", "wm") === "app" ? "app" : "wm"
  readonly property bool appMode: mode === "app"

  function isHeld(name) { return heldMods.indexOf(name.toLowerCase()) !== -1 }

  function active(name) {
    // In app mode SUPER is an ordinary modifier and latches like the rest; in
    // WM mode it is the layer itself, so it lights whenever the layer is up.
    if (appLayer) return isHeld(name)
    if (appMode) return false
    return name === "SUPER" ? engaged : isHeld(name)
  }

  // "+CTRL" is additive to Super; plain "CTRL" is a real Ctrl going to the app.
  function label(name) {
    if (appMode) return name
    return name === "SUPER" ? name : "+" + name
  }

  function lua(code) { luaProc.exec(["hyprctl", "eval", code]) }

  function press(name, button) {
    if (appMode) {
      if (button === Qt.RightButton) {
        // Sticky: keep the latch after the chord fires, for repeating Ctrl+W.
        lua('require("remote-seat").app_lock()')
        return
      }
      lua('require("remote-seat").app_toggle_mod("' + name.toLowerCase()
          + '", ' + root.holdMs + ')')
      return
    }

    if (name !== "SUPER") {
      lua('require("remote-seat").toggle_mod("' + name.toLowerCase() + '")')
      return
    }

    if (button === Qt.RightButton) {
      lua(root.locked ? 'require("remote-seat").leave()'
                      : 'require("remote-seat").enter(0)')
      root.locked = !root.locked
      return
    }

    root.locked = false
    lua('require("remote-seat").toggle(' + root.holdMs + ')')
  }

  // Switching mechanism mid-latch would leave a modifier lit that no longer
  // does what it says, so the seat is dropped first either way.
  function setMode(next) {
    lua('require("remote-seat").leave()')
    root.locked = false
    root.save({ mode: next })
  }

  property bool locked: false

  Process { id: luaProc }

  // Persist geometry. Writing re-triggers the watcher, but the values then match
  // what is already loaded, so it settles rather than looping.
  function save(patch) {
    if (!root.ready) return
    var next = JSON.parse(JSON.stringify(root.cfg))
    for (var k in patch) next[k] = patch[k]
    root.cfg = next
    configFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.config/omarchy/remote-seat.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.cfg = parsed
        root.posX = parsed.x === undefined ? root.posX : parsed.x
        root.posY = parsed.y === undefined ? root.posY : parsed.y
        root.ready = true
      } catch (e) {
        console.warn("superpad: config is not valid JSON, keeping previous:", e)
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name) !== "submap") return
      var name = String(event.data === undefined || event.data === null ? "" : event.data).trim()
      root.submap = name
      if (name === "") root.locked = false
    }
  }

  PanelWindow {
    id: win
    visible: root.enabled
    color: "transparent"

    WlrLayershell.namespace: "remote-seat-pad"
    WlrLayershell.layer: WlrLayer.Overlay
    // Never take keyboard focus: the key you press next must still reach the
    // window you were working in.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0

    // Span the screen so the pad can be placed at any coordinate...
    anchors { top: true; bottom: true; left: true; right: true }
    // ...but only the pad itself swallows pointer events.
    mask: Region { item: pad }

    Rectangle {
      id: pad
      x: Math.max(0, Math.min(root.posX, win.width - width))
      y: Math.max(0, Math.min(root.posY, win.height - height))
      width: layout.implicitWidth + 2
      height: layout.implicitHeight + 2
      radius: root.radius + 2
      color: Color.background
      opacity: root.padOpacity
      border.width: 1
      border.color: Color.muted

      Grid {
        id: layout
        anchors.centerIn: parent
        columns: root.vertical ? 1 : root.keys.length + 3
        spacing: root.spacing
        padding: root.spacing

        // Drag handle. The pad has no titlebar, and dragging from a button
        // would fight the click, so moving it gets its own grip.
        Rectangle {
          width: root.vertical ? root.btnW : 16
          height: root.vertical ? 16 : root.btnH
          radius: 3
          color: grip.pressed ? Color.muted : "transparent"

          Text {
            anchors.centerIn: parent
            text: root.vertical ? "⋯" : "⋮"
            color: Color.muted
            font.pixelSize: root.fontSize + 2
          }

          MouseArea {
            id: grip
            anchors.fill: parent
            cursorShape: Qt.SizeAllCursor
            property int grabX: 0
            property int grabY: 0
            onPressed: function(mouse) { grabX = mouse.x; grabY = mouse.y }
            onPositionChanged: function(mouse) {
              if (!pressed) return
              root.posX += mouse.x - grabX
              root.posY += mouse.y - grabY
            }
            // Persist once the drag settles, not on every frame.
            onReleased: root.save({ x: pad.x, y: pad.y })
          }
        }

        // Mode switch. WM composes Hyprland bindings; APP injects the chord
        // into the focused window. The label names the mechanism you are in,
        // not the one you would switch to.
        Rectangle {
          id: modeBtn
          width: root.vertical ? root.btnW : 40
          height: root.btnH
          radius: root.radius
          color: root.appMode ? Color.foreground : "transparent"
          border.width: 1
          border.color: root.appMode ? Color.foreground : Color.muted

          Behavior on color { ColorAnimation { duration: 110 } }

          Text {
            anchors.centerIn: parent
            text: root.appMode ? "APP" : "WM"
            color: root.appMode ? Color.background : Color.muted
            font.family: Style.font.family
            font.pixelSize: root.fontSize - 1
            font.weight: root.appMode ? Font.Bold : Font.Medium
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setMode(root.appMode ? "wm" : "app")
          }
        }

        Repeater {
          model: root.keys

          Rectangle {
            id: key
            required property var modelData
            readonly property bool on: root.active(modelData)

            width: root.btnW
            height: root.btnH
            radius: root.radius
            color: on ? Color.urgent : Color.background
            border.width: 1
            border.color: on ? Color.urgent : Color.muted

            Behavior on color { ColorAnimation { duration: 110 } }

            Text {
              anchors.centerIn: parent
              text: root.label(key.modelData)
              color: key.on ? Color.background : Color.foreground
              font.family: Style.font.family
              font.pixelSize: root.fontSize
              font.weight: key.on ? Font.Bold : Font.Medium
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              onPressed: function(mouse) { root.press(key.modelData, mouse.button) }
            }
          }
        }

        // Close. Reopen from the SUPER button on the bar (middle-click),
        // or with `kseat pad enabled true`.
        Rectangle {
          width: root.vertical ? root.btnW : 20
          height: root.vertical ? 20 : root.btnH
          radius: 3
          color: shut.containsMouse ? Color.urgent : "transparent"

          Text {
            anchors.centerIn: parent
            text: "✕"
            color: shut.containsMouse ? Color.background : Color.muted
            font.pixelSize: root.fontSize
          }

          MouseArea {
            id: shut
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.save({ enabled: false })
          }
        }
      }
    }
  }
}
