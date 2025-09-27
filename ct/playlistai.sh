#!/usr/bin/env bash
# PlaylistAI LXC Container Script
# Author: Michael (Hoosier-IT)
# License: MIT

# Source the community-scripts build functions
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="PlaylistAI"
var_os="debian"
var_version="12"
var_cpu="2"
var_ram="1024"
var_disk="4"
var_unprivileged="1"
var_tags="music;llm;flask"
var_hostname="playlistai"

header_info "$APP"
variables
color
catch_errors

function description() {
  echo -e "PlaylistAI: Flask API that curates playlists using Music Assistant and an LLM."
  echo -e "Binds your host music folder into /data/music inside the container."
}

function update_script() {
  header_info
  msg_info "Running PlaylistAI installation inside container $CTID"

  # ❌ Old line (causing issues):
  # pct exec "$CTID" -- bash -c "bash -s" < <(curl -fsSL https://raw.githubusercontent.com/Hoosier-IT/playlistai/main/install/playlistai-install.sh)

  # ✅ Corrected line:
  lxc-attach -n "$CTID" -- bash -c "$(curl -fsSL https://raw.githubusercontent.com/Hoosier-IT/playlistai/main/install/playlistai-install.sh)"

  msg_ok "PlaylistAI installation complete"
}

start
build_container
description
msg_ok "Completed Successfully!"
