#!/usr/bin/env bash
# PlaylistAI LXC Installer (Adaptive + Robust)
# Description: Deploys a Debian LXC running PlaylistAI (Flask API with Music Assistant + LLM integration)
# Author: Michael (Hoosier-IT)
# License: MIT
# Version: 3.0

set -Eeuo pipefail

# ===== Input prompts =====
read -rp "🔗 Enter your Music Assistant API URL: " MA_API
read -rp "🧠 Enter your LLM API URL: " LLM_API
read -rp "🔐 Enter your Home Assistant token: " TOKEN
read -rp "🎵 Enter your music folder path on Proxmox host (e.g., /mnt/music): " MUSIC_PATH

APP="PlaylistAI"
CTID=$(pvesh get /cluster/nextid)
DISK_SIZE="4"       # GB
MEMORY="1024"       # MB
CORE_COUNT="2"

die() { echo "❌ $1" >&2; exit 1; }

# ===== Ensure music path exists =====
[ -d "$MUSIC_PATH" ] || { echo "📁 Creating $MUSIC_PATH"; mkdir -p "$MUSIC_PATH"; }

# ===== Detect bridge =====
BRIDGES=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^vmbr[0-9]+')
if grep -q '^vmbr0$' <<<"$BRIDGES"; then
  BRIDGE="vmbr0"
elif [ "$(wc -w <<<"$BRIDGES")" -gt 1 ]; then
  echo "🌉 Multiple bridges detected: $BRIDGES"
  read -rp "Select bridge to use: " BRIDGE
else
  BRIDGE="$BRIDGES"
fi
[ -n "$BRIDGE" ] || die "No vmbr bridge found."

# ===== Detect storage =====
STORAGES=$(pvesm status | awk 'NR>1 {print $1}')
