#!/usr/bin/env bash
# Stamp the plugin's identity from a GitHub handle.
#
# The marketplace convention is io.github.<handle>.<name>, and the id appears in
# more than the manifest: the engine checks for its own plugin directory by id
# to know whether it has been orphaned, and the README's install line carries
# the repo URL. One script so those cannot drift apart.
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: ./set-identity.sh <github-handle>" >&2; exit 2; }
handle=$1
[[ $handle =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || { echo "not a GitHub handle: $handle" >&2; exit 2; }

here=$(cd "$(dirname "$0")" && pwd)
old=$(python3 -c "import json;print(json.load(open('$here/manifest.json'))['id'])")
new="io.github.${handle,,}.remote-seat"

if [[ $old == "$new" ]]; then echo "already $new"; exit 0; fi

python3 - "$here" "$old" "$new" "$handle" <<'PY'
import json, pathlib, sys
here, old, new, handle = sys.argv[1:5]
root = pathlib.Path(here)

m = json.loads((root / "manifest.json").read_text())
m["id"] = new
m["author"] = handle
(root / "manifest.json").write_text(json.dumps(m, indent=2) + "\n")

for rel in ("engine/remote-seat.lua", "README.md"):
    p = root / rel
    p.write_text(p.read_text().replace(old, new))

readme = root / "README.md"
readme.write_text(readme.read_text().replace(
    "https://github.com/<you>/omarchy-remote-seat.git",
    f"https://github.com/{handle}/omarchy-remote-seat.git"))
PY

echo "id:     $old -> $new"
echo "author: $handle"
grep -c "$new" "$here/engine/remote-seat.lua" | sed 's/^/engine references updated: /'
