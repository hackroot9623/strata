#!/usr/bin/env bash
# Installs the release bundle for the current user (no sudo, no system dirs).
# Run ../packaging/install.sh from anywhere after `flutter build linux --release`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
APP_DIR="$HOME/.local/share/strata"
BIN_DIR="$HOME/.local/bin"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
APPS_DIR="$HOME/.local/share/applications"

if [ ! -x "$BUNDLE/gnome_weather" ]; then
  echo "Release bundle not found — run 'flutter build linux --release' first." >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR" "$BIN_DIR" "$ICON_DIR" "$APPS_DIR"
cp -r "$BUNDLE"/. "$APP_DIR"/

ln -sf "$APP_DIR/gnome_weather" "$BIN_DIR/strata"
cp "$ROOT/packaging/io.github.strata.Strata.png" "$ICON_DIR/"
cp "$ROOT/packaging/io.github.strata.Strata.desktop" "$APPS_DIR/"

update-desktop-database "$APPS_DIR" 2>/dev/null || true
gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

echo "Installed to $APP_DIR"
echo "Launch: strata  (if ~/.local/bin is on PATH), or find Strata in your app grid."
echo "Uninstall: ${BASH_SOURCE[0]%/*}/uninstall.sh"
