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

  // Window controls act on the focused window. They are left-click only, and
  // that is the whole point: measured on a browser-based client, buttons 2 and
  // 3 never reach the compositor at all — the client keeps them for its context
  // menu and its paste. Omarchy's own active-window widget closes on right- or
  // middle-click and is therefore dead on such a seat. Left-click is the one
  // pointer event that always arrives.
  //
  // MIN is not minimise. Hyprland has no minimise: the window dispatchers are
  // close, fullscreen, float, pin, move, resize and friends, and none of them
  // hide a window. Moving it to the scratchpad special workspace is the honest
  // equivalent, and is what Omarchy binds itself.
  readonly property var winKeys: opt("windowControls", ["SHOW", "MIN", "MAX", "CLOSE"])
  readonly property bool showWin: winKeys.length > 0
  // Icons, not buttons. These are one-shot actions, not modifiers you compose,
  // and at modifier width every one added grows the pad by another 60px.
  readonly property int iconW: opt("iconWidth", 26)
  readonly property int iconH: opt("iconHeight", 22)

  // What the hover label is currently showing. The icons are deliberately
  // small and unlabelled, which is only tolerable if hovering says what they do.
  property string hint: ""

  readonly property var winHint: ({
    "SHOW": "Scratchpad drawer",
    "MIN":  "Send to scratchpad",
    "MAX":  "Maximise window",
    "CLOSE": "Close window",
    "FULL": "Fullscreen window",
    "FLOAT": "Float window"
  })

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

  // Taken verbatim from Omarchy's own bindings (SUPER+W, SUPER+ALT+F, SUPER+ALT+S,
  // SUPER+S, SUPER+T) so a click does exactly what the keybinding does.
  readonly property var winAction: ({
    "CLOSE": 'hl.dsp.window.close()',
    "MAX":   'hl.dsp.window.fullscreen({ mode = "maximized" })',
    "FULL":  'hl.dsp.window.fullscreen({ mode = "fullscreen" })',
    "MIN":   'hl.dsp.window.move({ follow = false, workspace = "special:scratchpad" })',
    "SHOW":  'hl.dsp.workspace.toggle_special("scratchpad")',   // the drawer MIN puts things in
    "FLOAT": 'hl.dsp.window.float({ action = "toggle" })'
  })

  readonly property var winGlyph: ({
    "SHOW": "\u25aa", "MIN": "\u2013", "MAX": "\u25a1", "CLOSE": "\u2715",
    "FULL": "\u25a0", "FLOAT": "\u25ab"
  })

  function winPress(name) {
    var action = root.winAction[name]
    // hl.dsp.* only BUILDS a dispatcher; evaluating one does nothing at all.
    // The modifier buttons get away with plain eval because they call module
    // functions that dispatch internally. These are raw dispatchers, so they
    // have to be handed to hl.dispatch or the click is a silent no-op —
    // measured: bare eval left fullscreen=0, wrapped set it to 1.
    if (action) lua("hl.dispatch(" + action + ")")
  }

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

  // The engine is installed from here as well as from the bar widget. Either
  // half can be enabled without the other, and the installer is idempotent.
  Loader { source: Qt.resolvedUrl("EngineInstaller.qml") }

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
    // No file yet is not "wait" -- it means there are no preferences to
    // protect, so the defaults already standing in are the config and the
    // first save is safe. Any other read error still holds `ready` low, so a
    // config that exists but cannot be read is never overwritten with
    // defaults, which is what this gate is for.
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) root.ready = true
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
    // ...but only the pad itself swallows pointer events. The hover label is
    // deliberately outside that region: it renders, and clicks pass through it.
    mask: Region { item: pad }

    Rectangle {
      id: tip
      visible: root.hint !== ""
      // Above the pad, unless the pad is near the top, in which case below.
      x: Math.max(0, Math.min(pad.x, win.width - width))
      y: pad.y > height + 8 ? pad.y - height - 6 : pad.y + pad.height + 6
      width: tipText.implicitWidth + 16
      height: tipText.implicitHeight + 10
      radius: 4
      color: Color.foreground
      opacity: 0.95

      Text {
        id: tipText
        anchors.centerIn: parent
        text: root.hint
        color: Color.background
        font.family: Style.font.family
        font.pixelSize: root.fontSize
      }
    }

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

      // Two groups, stacked. The modifiers set the pad's width; the window
      // controls sit under them in a shorter strip rather than extending the
      // row, which is what made the pad grow by 60px for every control added.
      Grid {
        id: layout
        anchors.centerIn: parent
        rows: root.vertical ? 1 : 2
        columns: root.vertical ? 2 : 1
        spacing: root.spacing
        padding: root.spacing

      Grid {
        id: primary
        rows: root.vertical ? root.keys.length + 3 : 1
        columns: root.vertical ? 1 : root.keys.length + 3
        spacing: root.spacing

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
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.hint = root.appMode ? "APP — send chords to the focused window"
                                                : "WM — compose Hyprland bindings"
            onExited: root.hint = ""
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


        // Hide the pad itself. Last, and a chevron rather than an ✕, so it does
        // not read as a second "close the window" beside the one that is.
        // Bring it back with the pip beside the SUPER button on the bar.
        Rectangle {
          width: root.vertical ? root.btnW : 20
          height: root.vertical ? 20 : root.btnH
          radius: 3
          color: shut.containsMouse ? Color.urgent : "transparent"

          Text {
            anchors.centerIn: parent
            text: "\u2304"
            color: shut.containsMouse ? Color.background : Color.muted
            font.pixelSize: root.fontSize + 2
          }

          MouseArea {
            id: shut
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.hint = "Hide this pad"
            onExited: root.hint = ""
            onClicked: root.save({ enabled: false })
          }
        }
      }

      // The icon strip. Sized to the modifier row so it can be centred under
      // it, and it never widens the pad: if it outgrows the row the pad grows,
      // which is the situation this layout exists to avoid.
      Item {
        visible: root.showWin
        width: root.vertical ? root.iconW : primary.width
        height: root.vertical ? primary.height : root.iconH

        Grid {
          anchors.centerIn: parent
          rows: root.vertical ? root.winKeys.length : 1
          columns: root.vertical ? 1 : root.winKeys.length
          spacing: root.spacing - 1

        Repeater {
          model: root.showWin ? root.winKeys : []

          Rectangle {
            id: winKey
            required property var modelData

            width: root.vertical ? root.btnW : root.iconW
            height: root.vertical ? root.iconH : root.iconH
            radius: 3
            color: winArea.pressed ? Color.urgent
                                   : (winArea.containsMouse ? Color.muted : "transparent")

            Behavior on color { ColorAnimation { duration: 110 } }

            Text {
              anchors.centerIn: parent
              text: root.winGlyph[winKey.modelData] || winKey.modelData
              color: winArea.pressed ? Color.background : Color.foreground
              font.family: Style.font.family
              font.pixelSize: root.fontSize + 1
              font.weight: Font.Medium
            }

            MouseArea {
              id: winArea
              anchors.fill: parent
              hoverEnabled: true
              // Left button only. The others never arrive over a browser client.
              acceptedButtons: Qt.LeftButton
              cursorShape: Qt.PointingHandCursor
              onEntered: root.hint = root.winHint[winKey.modelData] || winKey.modelData
              onExited: root.hint = ""
              onClicked: root.winPress(winKey.modelData)
            }
          }
        }
        }
      }

      }
    }
  }
}
