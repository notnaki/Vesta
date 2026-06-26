#!/bin/sh
# Build halo (release) and copy the binaries onto PATH so `halo` works from
# anywhere — independent of the build directory.
# Usage: ./install.sh [DEST_DIR]   (default /usr/local/bin)
set -e
cd "$(dirname "$0")"
swift build -c release
SRC="$(pwd)/.build/release"
DEST="${1:-/usr/local/bin}"
mkdir -p "$DEST" 2>/dev/null || true
# Copy all three so `halo` finds its halod/halo-attach siblings next to it
# (a symlink into .build breaks if the build dir is cleaned or moved). Re-run
# after a rebuild to update the installed copies.
if ! cp -f "$SRC/halo" "$SRC/halod" "$SRC/halo-attach" "$DEST/" 2>/dev/null; then
  echo "could not write to $DEST — try: sudo ./install.sh   (or ./install.sh ~/bin)" >&2
  exit 1
fi
echo "installed halo, halod, halo-attach -> $DEST"
echo "try: halo help"
