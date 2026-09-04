# Super Button

**Omarchy is unusable over a remote desktop, because Super never arrives.**

Nearly every Omarchy binding starts with Super. When you reach the machine
through a remote desktop connector — VNC, RDP, a browser-based client, a tablet
— the client's own operating system claims Super for itself before the session
ever sees it. `SUPER + W` does nothing. Neither does the menu, the launcher, or
any window management at all. The desktop is there, and you cannot drive it.

Hyprland is not at fault and there is no server-side setting that fixes it. The
key is taken upstream, on the machine you are sitting at, and never sent.

Super is not the only casualty:

- **The client's OS takes chords.** `Alt+Tab`, `Alt+F4` and `Win+L` are consumed
  by the desktop you are sitting at, so the bindings Omarchy puts on them are
  unreachable.
- **A browser-based client takes more.** `Ctrl+T`, `Ctrl+W`, `Ctrl+L`, `F11`
  and friends open tabs and close windows on the client, not in your session.
- **Some keys cannot be sent at all.** Volume, brightness and media live on
  XF86 keysyms a VNC client has no way to generate, and PrintScreen is usually
  taken by the client before it is forwarded.

This plugin gives every one of those functions a path that survives the
connector, without asking anything of the client. The one thing every connector
forwards faithfully is **mouse events**, so the modifier becomes a pointer
target: click Super, then press the key.

It needs no particular client, no browser extension, no Keyboard Lock, no
fullscreen, no HTTPS and no native viewer. A browser-based client over a VPN
behaves the same as a native one, which is the point.

## Install

    omarchy plugin add https://github.com/knivfjell/omarchy-super-button.git --enable

That installs the engine and the floating pad, and they work immediately. No
`hyprland.lua` hook, no config of yours patched, no script to run.

Then put the **button** on the bar, which Omarchy leaves to you for any
third-party widget. Either pick it from `omarchy menu plugin`, or add an entry
to the `left` section of `bar.layout` in `~/.config/omarchy/shell.json`, which
hot-reloads on save:

    { "id": "io.github.knivfjell.super-button", "holdMs": 4000, "label": "SUPER",
      "countdown": true, "lockEnabled": true }

Note that `omarchy bar put <id>` prints "is on the bar" without placing a
third-party widget on Omarchy 4.0.2 — it is not doing anything, whatever it
says. Use the menu or the config entry above.

The pad does not need the button: it is a separate plugin kind, enabled by the
install line, and the button is how you re-open it after its ✕.

## Uninstall

    omarchy plugin remove io.github.knivfjell.super-button
    rm ~/.local/state/omarchy/toggles/hypr/remote-seat.lua

The second line is tidiness, not a requirement: the engine checks on every load
whether the plugin that owns it is still installed, and does nothing if it is
not. Removing the plugin is enough to stop it.

## Files

| Path | Role |
|---|---|
| `<plugin>/RemoteSeat.qml` | The bar widget: clickable Super, and the pad toggle |
| `<plugin>/RemoteSeatPad.qml` | The floating modifier pad |
| `<plugin>/engine/remote-seat.lua` | The layer, the mirrors, app mode, the key probe |
| `~/.local/state/omarchy/toggles/hypr/remote-seat.lua` | Where the engine is installed to (a copy; do not edit) |
| `~/.config/omarchy/remote-seat.json` | Pad geometry, placement, mode and hold |
| `~/.config/omarchy/shell.json` | Where the button sits on the bar, and its hold |
| `~/.local/bin/kseat` | Optional: out-of-band control and measurement over SSH |

Nothing under `/usr/share/omarchy/` or `~/.config/hypr/` is touched, so both
`omarchy update` and your own Hyprland config are left alone.

## How it hooks in without touching your config

The mirrors have to be built inside Hyprland's Lua config, which a QML plugin
cannot enter. The usual answer is to make you paste two lines into
`hyprland.lua`. This does not.

Instead the plugin drops its engine into
`~/.local/state/omarchy/toggles/hypr/`, a directory Omarchy already `require()`s
from `hyprland.lua` on every config load — after every binding is registered.
The file copied there is static and shipped in the plugin: nothing is generated,
interpolated, or fetched. It is copied only when it differs, so a shell restart
costs nothing and Hyprland is reloaded only on a genuine change.

Running that late would normally be too late to mirror anything, because the
usual technique is to wrap `hl.bind` *while* bindings register. So the engine
recovers them from the far end instead: it re-requires the binding modules with
an `hl.bind` that records and returns **without registering**, which yields the
real dispatcher objects while leaving the live bind table untouched. Measured
against the load-time capture it is exact — 178 mirrors for 178, nothing
missing. The rest of the `hl` API is stubbed during that pass, because those
files call `hl.unbind`, `hl.on`, `hl.dispatch`, `hl.config` and `hl.timer`, and
re-running those would tear out real bindings and duplicate handlers.

## 1. The leader layer

Press a leader, then the Super binding with Super dropped.

    SUPER + W            ->   <leader>  then  W
    SUPER + SHIFT + LEFT ->   <leader>  then  SHIFT + LEFT

Leaders (any of them):

- `CTRL + ALT + SPACE` — unused by Omarchy, and clear of the
  `Ctrl+Alt+Shift` chord some browser-based clients reserve for their own menu
- `MENU` — no modifier, for connectors that mangle modifier state
- `PAUSE` — same

The layer is sticky, so several window operations can be chained on one leader
press. That matters on a laggy software-rendered link.

Leaving it: `Escape`, `Ctrl+G`, any leader again, or wait — it drops itself
after 12s idle, so a stray leader press can never strand the keyboard. While
active, the compositor itself draws an indicator (not the notification daemon,
so it shows even if Quickshell is wedged).

The 178 mirrors are generated by wrapping `hl.bind`, so they are derived from
the bindings actually registered. New Omarchy defaults and personal bindings in
`bindings.lua` are picked up automatically — this file never needs updating.

Pointer bindings (`SUPER` + drag/scroll) are deliberately not mirrored: a
latched layer cannot express "Super held while dragging". Use the `kseat run`
escape hatch or the mouse directly.

## 2. The function row

Inside the layer, F1–F12 carry what a VNC client physically cannot send. The
commands are Omarchy's own, so behaviour matches the real keys.

| Key | Action | Key | Action |
|---|---|---|---|
| F1 | Mute | F7 | Previous track |
| F2 | Volume down | F8 | Play / pause |
| F3 | Volume up | F9 | Next track |
| F4 | Mute microphone | F10 | Screenshot |
| F5 | Brightness down | F11 | Screen recording |
| F6 | Brightness up | F12 | Extract text (OCR) |

## 3. Out-of-band control — `kseat`

SSH does not care what the connector ate, so this works when the desktop does
not. It resolves `HYPRLAND_INSTANCE_SIGNATURE` itself, which a non-login SSH
shell does not have.

    kseat status            session, connectors, layer state
    kseat binds [filter]    cheat sheet: Super binding -> leader equivalent
    kseat layer on|off      drive the layer remotely
    kseat menu              open the Omarchy menu with no keyboard at all
    kseat run '<lua>'       any dispatcher, e.g. hl.dsp.window.close()
    kseat send <mods> <key> send a real chord to the focused window
    kseat unstick           reset the layer and clear stuck modifier state

## 4. Measuring a connector — do not guess

No tool on this box can tell you what a connector delivers. `wtype` and other
virtual-keyboard tools report modmask 0, so they cannot stand in for a real
Super press. The only trustworthy answer comes from pressing the key through
the connector and reading what arrived:

    kseat probe on
    kseat probe tail        # then press SUPER+W in the connector

A line showing `mods=SUPER` means Super reaches the VM and the connector is not
the problem. No line, or `mods=-`, means it was swallowed upstream. Then:

    kseat probe off

## 5. The Super button — the connector-agnostic answer

Every remote desktop connector forwards **mouse events** faithfully. None of
them reliably forward Super, because the client's own OS claims it first. So the
modifier is offered as a pointer target instead of a key.

A `SUPER` button sits on the bar, left of the workspaces. Click it, then press
the key. `SUPER + W` becomes *click, then W*.

- **Click** — engages Super for the hold duration, then releases itself. The
  button counts the seconds down so the window is visible.
- **Right-click** — latches it open (shown as `∞`) for chaining several
  bindings. Click again to release.
- **Esc**, `Ctrl+G` or any leader key also releases it.

The bar is a layer-shell surface with `WlrKeyboardFocus.None`, so clicking the
button never takes keyboard focus away from the window you are working in.

### Tuning the hold

    kseat hold           # show the current duration
    kseat hold 6000      # set it to 6 seconds

It lives in `~/.config/omarchy/shell.json` on the widget's layout entry, which
hot-reloads on save:

    { "id": "io.github.knivfjell.super-button", "holdMs": 4000, "label": "SUPER",
      "countdown": true, "lockEnabled": true }

| Setting | Meaning |
|---|---|
| `holdMs` | How long one click keeps Super engaged (minimum 250) |
| `label` | Button text |
| `countdown` | Show remaining seconds while engaged |
| `lockEnabled` | Whether right-click latches |

## 6. Other captured keys, and the modifier pad

Super is not the only casualty. Anything the controlling machine claims first
never arrives, and the mirror scheme made this worse before it made it better:
dropping SUPER turns `SUPER+CTRL+T` into `CTRL+T` and `SUPER+ALT+TAB` into
`ALT+TAB` — chords Chrome and Windows take for themselves.

Exactly what is claimed depends on the client you are sitting at. A Windows
desktop driving a browser-based client is the worst case, and a representative
one:

| Claimed by | Chords |
|---|---|
| The OS, absolutely | `Ctrl+Alt+Del`, `Win+L` — below every application, nothing can intercept them |
| The desktop shell | `Alt+Tab`, `Ctrl+Alt+Tab`, `Alt+Space`, `Alt+F4` |
| The browser | `Ctrl+T/N/W/P/D/F/L/R/Q/I`, `Ctrl+Shift+*`, `Alt+Left/Right`, `F11`, `F12` |
| The remote client itself | often a chord such as `Ctrl+Alt+Shift` for its own menu |

A native viewer on a Linux client claims less, and a tablet client claims
different things again. The mechanism below does not care which: it stops any
chord from needing to leave the client at all.

Omarchy binds straight into that: `CTRL+ALT+DELETE` is "Close all windows",
`ALT+TAB` is "Focus next window", `CTRL+ALT+TAB` is "Focus next monitor".

### The fix: no chord ever leaves the client

Each residual modifier set gets its own submap, so every binding is reachable as
a **bare key** — and a bare letter is the one thing nothing upstream claims.

| Submap | Bindings | Reached by |
|---|---|---|
| `remote` | 38 | Super alone |
| `remote_ctrl` | 41 | Super + Ctrl |
| `remote_shift` | 38 | Super + Shift |
| `remote_alt` | 23 | Super + Alt |
| `remote_alt_shift` | 25 | Super + Alt + Shift |
| `remote_ctrl_alt` | 7 | Super + Ctrl + Alt |
| `remote_ctrl_shift` | 6 | Super + Ctrl + Shift |

`SUPER+CTRL+T` becomes: click SUPER, click CTRL, press `T`. The base submap
still carries every mirror with its chord intact, so a real keyboard loses
nothing.

Latching a combination nothing is bound under is refused rather than dropping
into an undefined submap that would swallow every key.

### The floating pad

The pad draws the modifiers as a floating overlay, placeable anywhere in the
workspace.

The modifiers read **`+CTRL`**, **`+ALT`**, **`+SHIFT`** rather than `CTRL`,
`ALT`, `SHIFT` because they are additive to Super, not independent. There is no
Super-less layer: latching `+CTRL` moves the compositor into `remote_ctrl` and
lights SUPER too, because Super genuinely is engaged. Clicking `+CTRL` from
idle engages both in one step.

That also means WM mode **cannot send a plain `Ctrl+key` to an application** —
click `+CTRL`, press `W`, and you fire the binding `SUPER+CTRL+W`, not `Ctrl+W`
to the focused window. That is what app mode below is for.

- **Click** a modifier to latch it, click again to release.
- **Click SUPER** for a timed hold; **right-click** to latch it open.
- **Drag the grip** (⋮ on the left) to move the pad; the position is written
  back to the config on release, so it survives a restart.
- **✕** closes it. The **▣ / ▢ pip** beside the SUPER button on the bar brings
  it back — **left-click**, because that is the one pointer event every
  connector forwards. It is filled while the pad is on screen and hollow when it
  is not, so the bar always says whether there is a pad to go back to.
  Middle-clicking the SUPER button itself still toggles it, and so does
  `kseat pad enabled true`.

  Middle-click alone was not enough: a browser-hosted connector need not deliver
  button 2 at all (Chrome claims it for autoscroll), and once the pad is closed a
  control you cannot click is a control that does not exist.

The window spans the screen so the pad can sit at any coordinate, but its input
region is masked to the pad itself (`mask: Region { item: pad }`), so every
click outside it reaches whatever is underneath. Keyboard focus is never taken
(`WlrKeyboardFocus.None`), and it reserves no space (`exclusiveZone: 0`).

State comes from the submap name rather than being tracked locally, so the pad
stays correct when the layer is driven from a leader key, from `kseat`, or by
its own timeout expiring.

### Window controls

The icons after the divider act on the **focused window**, and are left-click only
because right- and middle-click are not delivered by a browser-based client (see the
trap below).

| Icon | Does | Same as |
|---|---|---|
| `▪` | show/hide the scratchpad drawer | `SUPER + S` |
| `–` | send the window to the scratchpad | `SUPER + ALT + S` |
| `□` | maximise | `SUPER + ALT + F` |
| `✕` | close the window | `SUPER + W` |

They sit on their own strip **below** the modifiers, not beside them. Two reasons:
these are one-shot actions rather than things you compose, and a control added to the
modifier row costs the pad another 60px of width. On the strip they only add height —
the pad stays 358px wide with four controls, the same width it had with none.

Hover any of them for a label. They are deliberately small and unlabelled, which is
only tolerable if hovering says what they do; the label renders outside the pad's
input region, so it never swallows a click.

`⌄` at the top right hides the pad itself — a chevron, not a second `✕`, so it cannot
be mistaken for closing the window.

**`–` is not minimise.** Hyprland has no minimise: its window verbs are close,
fullscreen, float, pin, move, resize and friends, and none of them hide a window.
Moving it to the scratchpad special workspace is the honest equivalent, and is what
Omarchy binds itself. A window sent there is not gone, it is elsewhere — `▪` brings
the drawer back, and `kseat scratch` lists what is in it without showing it.

Choose which appear, and their size, with `windowControls`, `iconWidth` and
`iconHeight` in `remote-seat.json`. An empty `windowControls` removes the strip and
the pad returns to a single row.

### Placing and sizing it

    kseat pad                        # everything, plus the computed size
    kseat pad center                 # or top-left / top-right / bottom-left /
                                     #    bottom-right, with an optional margin
    kseat pad bottom-right 40        # same, 40px margin
    kseat pad x 400                  # or place it by hand, anywhere
    kseat pad y 300
    kseat pad orientation vertical   # horizontal | vertical
    kseat pad buttonWidth 76
    kseat pad keys SUPER,CTRL,ALT    # which modifiers appear

| Setting | Meaning |
|---|---|
| `enabled` | Whether the pad is on screen |
| `mode` | `wm` (drive Hyprland bindings) or `app` (send chords to the focused window) |
| `x`, `y` | Free position within the usable area (below the bar) |
| `orientation` | Row or column |
| `buttonWidth`, `buttonHeight`, `fontSize`, `spacing`, `radius` | Size |
| `opacity` | Pad transparency |
| `holdMs` | Hold before auto-release |
| `keys` | Which modifiers appear |

The pad clamps itself inside the screen, so an off-screen coordinate is pulled
back rather than losing the pad.

Enable or remove the whole thing with
`omarchy plugin enable|disable io.github.knivfjell.super-button` — third-party plugins are
opt-in, unlike first-party ones.

## 7. App mode — real chords into the focused window

Everything above drives **Hyprland's own bindings**. That is the wrong mechanism
for an application: click `+CTRL`, press `W`, and you fire `SUPER+CTRL+W`; the
focused window never sees a key at all.

The gap matters because the chords a connector eats belong to the *client*. The
client's browser takes `Ctrl+T/W/L/N/R`; the client's OS takes `Alt+Tab` and
`Alt+F4`. Both do so before the connector is reached. So if the browser or
editor you want those chords in is running **in the Omarchy session**, no amount
of submap work will deliver them — they were consumed on the machine you are
sitting at.

So the pad has a second mode with a different mechanism. The modifier is still
latched by clicking, but the key that follows is captured and re-emitted into
the focused window with `send_shortcut`, which injects a **real chord** instead
of firing a binding.

    WM mode    click +CTRL, press W   ->   Hyprland binding SUPER+CTRL+W
    APP mode   click  CTRL, press W   ->   the focused window receives Ctrl+W

Click the **`WM`/`APP`** button at the left of the pad to switch. The label
names the mode you are *in*, not the one you would switch to, and the setting
persists in `remote-seat.json`. Switching drops any active latch, because a lit
modifier that had changed meaning would be lying.

In app mode the modifiers lose their `+` and read `CTRL`, `ALT`, `SHIFT`,
because here they genuinely are independent — `Ctrl+W` means `Ctrl+W`. `SUPER`
becomes an ordinary latchable modifier too, rather than the layer itself.

- **Click** a modifier to latch it; latch several for `Ctrl+Shift+T`.
- **Press the key** and the chord goes to the focused window. The latch then
  releases itself, the way a real modifier does.
- **Right-click** any modifier to make the latch *sticky* (shown as `∞`), for
  repeating the same chord. Click again, or press `Esc`, to release.
- The latch drops itself after `holdMs` regardless, so a forgotten click cannot
  strand the keyboard.

`Escape` is deliberately not sendable: it is the way out of the layer, and it
reaches applications through every connector anyway.

### How it is wired

App mode is its own submap family, one submap per modifier combination, so the
submap name still says both what is latched *and* which mechanism is armed:

| WM mode | App mode |
|---|---|
| `remote_ctrl` | `remote_app_ctrl` |
| `remote_ctrl_shift` | `remote_app_ctrl_shift` |

The pad keeps reading its whole state from that name rather than tracking any of
it locally, so it stays correct when the layer is driven from `kseat` or drops
itself on a timeout. All 15 combinations of `SUPER`/`CTRL`/`ALT`/`SHIFT` are
defined — 73 chordable keys each, about 1100 binds, measured at 3ms to register
— so unlike the WM family there is no unbound combination to refuse.

### Sending a chord out of band

    kseat send ctrl w            # Ctrl+W to the focused window
    kseat send ctrl+shift t      # several modifiers
    kseat send '' F11            # no modifier at all
    kseat send alt Tab

This is the same path the pad uses, so it also answers "is app mode wired up?"
without needing a keyboard the connector respects. `kseat status` reports the
pad's mode, whether a latch is armed and what it holds.

### Trap: the mods string is not validated

`send_shortcut` accepts a malformed modifier string, reports `ok`, and then
delivers **nothing**. `mods = "CTRL_SHIFT"` is a silent no-op; `"CTRL SHIFT"`
and `"CTRLSHIFT"` both work. Everything here therefore assembles that string
from a fixed vocabulary rather than passing text through, and `kseat send`
refuses an unknown modifier by name instead of sending a dud.

### Trap: describing these binds breaks SUPER+K

`omarchy-menu-keybindings` — what `SUPER+K` runs — enumerates every bind that
carries a **description**, and ships the whole list to the shell in one IPC
payload. Describing the app-mode chords adds 1095 entries and takes that payload
from ~34KB to ~126KB, at which point the call never returns: the picker never
opens and `SUPER+K` silently does nothing. The failure looks like a broken
compositor binding, and is not.

So the chord binds are registered with **no description**, which that
enumeration skips outright:

    [[ -z $description && $dispatcher == "__lua" ]] && continue

They are mechanical — 15 combinations of the same 73 keys — so they are noise in
a cheatsheet anyway. `kseat status` reports the shape instead of listing them.

The general rule for anything added here: **a described bind costs bar-menu
payload**. Bulk binds should carry none.

### Confirmed working

Verified against a browser running in the Omarchy session, driven from a
browser-based client: `APP` → `CTRL` → `T` opened a new tab in the *session's*
browser. That is the whole point of app mode. `Ctrl+T` is a chord the client's
own browser eats, so it can never arrive over the connector, and the compositor
layer could only ever have fired `SUPER+CTRL+T`.

It took a human key press to establish, for the reason in the next trap.

### Trap: wtype cannot test this

`wtype` sends every character as **keycode 9**, which Hyprland resolves against
its *own* keymap as `Escape` — so in any submap it triggers the exit binding
rather than the key you asked for, and the chord never fires. The app receives
the right letter, because it resolves the keycode against wtype's uploaded
keymap, which makes the tool look like it works. It cannot stand in for a real
key press here any more than it can for a real Super press (see §4).

### Multiple monitors

The bar button appears on every bar. The pad is a single floating surface and
appears on one output, so on a multi-head setup put it where you work, or drive
the seat from the bar button and the leader keys instead.

### Still unreachable

`Ctrl+Alt+Del` and `Win+L` are consumed on the controlling machine below every
application, so nothing here can deliver them.

That matters for the handful of Omarchy bindings that carry no Super and so are
never mirrored into the layer: `CTRL+ALT+DELETE` (close all windows), `ALT+TAB`
and `ALT+SHIFT+TAB` (cycle windows), `CTRL+ALT+TAB` (next monitor). The pad
cannot reach them, because the pad only latches modifiers onto Super bindings.

For those, either drive them out of band:

    kseat run 'hl.dsp.window.cycle_next()'

or give them a Super binding in `~/.config/hypr/bindings.lua`, which the mirror
picks up automatically on the next reload:

    o.bind("SUPER + SHIFT + Q", "Close all windows", "omarchy-hyprland-window-close-all")

## 8. Hyprland 0.56 trap

`hyprctl dispatch` now takes **Lua**, not the old string form. The classic
syntax fails, and reads as a near-silent no-op:

    hyprctl dispatch submap reset                  # error
    hyprctl dispatch 'hl.dsp.submap("reset")'      # correct

`kseat` wraps this so callers do not have to remember it. `hyprctl eval` runs a
Lua string; `hyprctl repl` runs one and prints the result.
