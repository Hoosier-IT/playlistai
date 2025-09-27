#!/usr/bin/env bash
# PlaylistAI Install Script (runs inside container)
# Author: Michael (Hoosier-IT)
# License: MIT

# Source the community-scripts install functions
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/install.func)

APP="PlaylistAI"

function install_script() {
  header_info

  # Prompt for inputs
  local MA_API="" LLM_API="" TOKEN="" MUSIC_PATH=""
  while [ -z "$MA_API" ]; do
    read -rp "🔗 Enter your Music Assistant API URL: " MA_API
  done
  while [ -z "$LLM_API" ]; do
    read -rp "🧠 Enter your LLM API URL: " LLM_API
  done
  while [ -z "$TOKEN" ]; do
    read -rp "🔐 Enter your Home Assistant token: " TOKEN
  done
  while [ -z "$MUSIC_PATH" ]; do
    read -rp "🎵 Enter your music folder path on Proxmox host (default: /mnt/music): " MUSIC_PATH
    MUSIC_PATH=${MUSIC_PATH:-/mnt/music}
  done

  msg_info "Installing Python and dependencies"
  apt update
  apt install -y python3 python3-pip python3-venv ca-certificates curl
  mkdir -p /opt/playlistai
  python3 -m venv /opt/playlistai/venv
  msg_ok "Python environment ready"

  msg_info "Creating PlaylistAI files"
  cat << 'EOF' > /opt/playlistai/app.py
# (Flask app code here — same as before)
EOF

  cat << 'EOF' > /opt/playlistai/requirements.txt
flask
requests
python-dotenv
EOF

  cat << EOF > /opt/playlistai/config.env
MA_API=$MA_API
LLM_API=$LLM_API
TOKEN=$TOKEN
EOF

  cat << 'EOF' > /etc/systemd/system/playlistai.service
[Unit]
Description=PlaylistAI Service
After=network.target

[Service]
WorkingDirectory=/opt/playlistai
EnvironmentFile=/opt/playlistai/config.env
ExecStart=/opt/playlistai/venv/bin/python /opt/playlistai/app.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  . /opt/playlistai/venv/bin/activate
  pip install -r /opt/playlistai/requirements.txt
  systemctl enable playlistai
  systemctl start playlistai
  msg_ok "PlaylistAI service started"
}

install_script
