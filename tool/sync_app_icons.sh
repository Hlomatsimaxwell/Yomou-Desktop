#!/usr/bin/env bash
# Copy the icon-kitchen exports under icons/<variant>/ into the Flutter asset
# folder, where the app discovers them as `variant_<id>.png`.
#
# Usage:
#   ./tool/sync_app_icons.sh
#
# Drop a new folder in `icons/` (for example `icons/emerald/`) containing
# AppIcon512.png and run this script. No Dart changes are needed: the picker
# reads the variant list from the asset manifest at runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/icons"
DEST="$ROOT/assets/app_icons"

[ -d "$SRC" ] || {
  echo "error: $SRC does not exist" >&2
  exit 1
}
mkdir -p "$DEST"

shopt -s nullglob
found=0
for dir in "$SRC"/*/; do
  name="$(basename "$dir")"
  id="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//')"

  source=""
  for candidate in AppIcon512.png AppIcon1024.png AppIcon256.png; do
    if [ -f "$dir/$candidate" ]; then
      source="$dir/$candidate"
      break
    fi
  done

  if [ -z "$source" ]; then
    echo "skip $name: no AppIcon512.png/AppIcon1024.png" >&2
    continue
  fi

  cp "$source" "$DEST/variant_$id.png"
  echo "synced $name -> assets/app_icons/variant_$id.png"
  found=$((found + 1))
done

if [ "$found" -eq 0 ]; then
  echo "error: no icon variants found under $SRC" >&2
  exit 1
fi
