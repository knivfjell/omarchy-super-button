#!/usr/bin/env bash
# Stamp the plugin's identity from a GitHub handle.
#
# The marketplace convention is io.github.<handle>.<name>, and that id is load
# bearing in more places than the manifest: the QML reads its settings from
# shell.json by moduleName, the engine checks for its own plugin directory to
# know whether it has been orphaned, and kseat finds the bar widget by id.
# Every one of those is silent when wrong — a widget with no settings, an engine
# that thinks it is uninstalled, a kseat that finds nothing. Two such bugs got
# as far as a commit before this script covered them all.
#
# It rewrites any id it finds rather than one specific old string, so running it
# twice, or after a partial edit, converges instead of drifting.
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: ./set-identity.sh <github-handle>" >&2; exit 2; }
handle=$1
[[ $handle =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || { echo "not a GitHub handle: $handle" >&2; exit 2; }

here=$(cd "$(dirname "$0")" && pwd)

python3 - "$here" "$handle" <<'PY'
import json, pathlib, re, sys

here, handle = sys.argv[1], sys.argv[2]
root = pathlib.Path(here)
new = f"io.github.{handle.lower()}.super-button"

# Any id this project has ever carried, in dotted or dashed form.
ID = re.compile(r"(?:io\.github\.[A-Za-z0-9-]+|[A-Za-z0-9-]+)\.super-button")

manifest = root / "manifest.json"
m = json.loads(manifest.read_text())
old = m["id"]
m["id"] = new
m["author"] = handle
manifest.write_text(json.dumps(m, indent=2) + "\n")

for rel in ("engine/remote-seat.lua", "RemoteSeat.qml", "bin/kseat", "README.md"):
    p = root / rel
    p.write_text(ID.sub(new, p.read_text()))

readme = root / "README.md"
readme.write_text(re.sub(r"https://github\.com/[A-Za-z0-9<>-]+/omarchy-super-button\.git",
                         f"https://github.com/{handle}/omarchy-super-button.git",
                         readme.read_text()))

# Fail loudly rather than ship a half-stamped tree.
stale = []
for p in root.rglob("*"):
    if not p.is_file() or ".git" in p.parts or p.suffix == ".png" or p.name == "set-identity.sh":
        continue
    for found in ID.findall(p.read_text(errors="ignore")):
        if found != new:
            stale.append(f"{p.relative_to(root)}: {found}")
if stale:
    sys.exit("set-identity: id left un-stamped:\n  " + "\n  ".join(stale))

print(f"id:     {old} -> {new}")
print(f"author: {handle}")
PY
