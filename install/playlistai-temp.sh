#!/usr/bin/env bash
# Temporary installer wrapper for PlaylistAI
# Runs the local installer from this repo instead of community-scripts

set -e

echo "⚙️  Running PlaylistAI temporary installer from Hoosier-IT repo..."

bash -c "$(curl -fsSL https://raw.githubusercontent.com/Hoosier-IT/playlistai/main/install/playlistai-install.sh)"
