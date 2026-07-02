#!/usr/bin/env bash
# Reverses install.sh — removes everything it copied/linked.
set -euo pipefail

rm -rf "$HOME/.local/share/strata"
rm -f "$HOME/.local/bin/strata"
rm -f "$HOME/.local/share/icons/hicolor/256x256/apps/io.github.strata.Strata.png"
rm -f "$HOME/.local/share/applications/io.github.strata.Strata.desktop"

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

echo "Uninstalled."
