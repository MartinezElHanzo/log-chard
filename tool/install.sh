#!/bin/bash
# LogChard user-level installer for Linux.
# Usage: ./install.sh [prefix]   (default: ~/.local)
set -euo pipefail

PREFIX="${1:-$HOME/.local}"
SRC="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$PREFIX/bin" "$PREFIX/lib/log-chard" \
         "$PREFIX/share/icons/hicolor/256x256/apps" \
         "$PREFIX/share/applications"

# flutter bundle keeps its .so's + data next to the binary
cp -a "$SRC/lib" "$PREFIX/lib/log-chard/" 2>/dev/null || true
cp -a "$SRC/data" "$PREFIX/lib/log-chard/" 2>/dev/null || true
install -m755 "$SRC/log_chard" "$PREFIX/lib/log-chard/log_chard"
for exe in logchard logchard-mcp; do
  [ -f "$SRC/$exe" ] && install -m755 "$SRC/$exe" "$PREFIX/bin/$exe"
done
ln -sf "$PREFIX/lib/log-chard/log_chard" "$PREFIX/bin/log_chard"

install -m644 "$SRC/icon-256.png" \
  "$PREFIX/share/icons/hicolor/256x256/apps/log-chard.png"
install -m644 "$SRC/log-chard.desktop" \
  "$PREFIX/share/applications/log-chard.desktop"

# refresh caches when tools exist
command -v update-desktop-database >/dev/null && \
  update-desktop-database "$PREFIX/share/applications" || true
command -v gtk-update-icon-cache >/dev/null && \
  gtk-update-icon-cache -q "$PREFIX/share/icons/hicolor" || true

echo "Installed to $PREFIX — 'log_chard' on PATH, app-menu entry 'LogChard'."
