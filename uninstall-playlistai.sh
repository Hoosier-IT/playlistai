#!/usr/bin/env bash
# PlaylistAI LXC Uninstaller
# Description: Removes the PlaylistAI container and its resources
# Author: (Hoosier-IT)
# License: MIT
# Version: 1.0

set -Eeuo pipefail

APP="PlaylistAI"
read -rp "🧠 Enter the CTID of the $APP container to remove: " CTID

if pct status "$CTID" &>/dev/null; then
  echo "🧹 Stopping and destroying CT $CTID..."
  pct stop "$CTID"
  pct destroy "$CTID"
  echo "✅ $APP container $CTID removed successfully."
else
  echo "⚠️ CTID $CTID does not exist or is already removed."
fi
