#!/usr/bin/env bash
# PlaylistAI LXC Installer (TTeck Framework Compatible)
# Author: Michael (Hoosier-IT)
# License: MIT
# Version: 4.0

# Load TTeck/Community framework
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# ========= Metadata / Defaults =========
APP="PlaylistAI"
var_os="debian"          # OS family
var_version="12"         # Debian version
var_unprivileged="1"     # Unprivileged container
var_disk="4"             # GB
var_cpu="2"
var_ram="1024"           # MiB
var_tags="music;llm;flask"

# ========= Description shown post-install =========
function description() {
  echo -e "PlaylistAI: Flask API that curates playlists using Music Assistant and an LLM."
  echo -e "Binds your host music folder into /data/music inside the container."
}

# ========= Install steps run AFTER container is created =========
function install_script() {
  header_info

  # Prompt for inputs with validation (no empty inputs allowed)
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

  # Ensure host directory exists, then bind-mount into CT
  msg_info "Preparing host music directory"
  if [ ! -d "$MUSIC_PATH" ]; then
    mkdir -p "$MUSIC_PATH" || { msg_error "Failed to create $MUSIC_PATH"; exit 1; }
  fi
  pct set "$CTID" -mp0 "${MUSIC_PATH},mp=/data/music"
  msg_ok "Host music directory mounted to /data/music"

  # Install Python and create venv inside CT
  msg_info "Installing Python and dependencies in container $CTID"
  pct exec "$CTID" -- bash -c "
    set -Eeuo pipefail
    apt update
    apt install -y python3 python3-pip python3-venv ca-certificates curl
    mkdir -p /opt/playlistai
    python3 -m venv /opt/playlistai/venv
  "
  msg_ok "Python environment ready"

  # Write app files
  msg_info "Creating PlaylistAI application files"
  pct exec "$CTID" -- bash -c "cat << 'EOF' > /opt/playlistai/app.py
import os, json, requests
from flask import Flask, request, jsonify
from dotenv import load_dotenv

load_dotenv()
app = Flask(__name__)
MA_API = os.getenv('MA_API')
LLM_API = os.getenv('LLM_API')
TOKEN = os.getenv('TOKEN')

def fetch_library():
    headers = {'Authorization': f'Bearer {TOKEN}'}
    r = requests.get(f'{MA_API}/media/library', headers=headers, timeout=15)
    r.raise_for_status()
    return r.json()

def query_llm(library_json, prompt):
    payload = {'messages': [
        {'role': 'system', 'content': 'You are a music curator.'},
        {'role': 'user', 'content': f'{prompt}\\n\\n{json.dumps(library_json)}'}
    ]}
    r = requests.post(LLM_API, json=payload, timeout=30)
    r.raise_for_status()
    data = r.json()
    if isinstance(data, dict):
        if 'choices' in data:
            return data['choices'][0]['message']['content']
        if 'message' in data:
            return data['message']
    return json.dumps(data)

@app.route('/generate', methods=['POST'])
def generate_playlist():
    prompt = request.json.get('prompt', '')
    library = fetch_library()
    playlist = query_llm(library, prompt)
    return jsonify({'playlist': playlist})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF"

  pct exec "$CTID" -- bash -c "cat << 'EOF' > /opt/playlistai/requirements.txt
flask
requests
python-dotenv
EOF"

  pct exec "$CTID" -- bash -c "cat << EOF > /opt/playlistai/config.env
MA_API=$MA_API
LLM_API=$LLM_API
TOKEN=$TOKEN
EOF"

  # systemd service
  pct exec "$CTID" -- bash -c "cat << 'EOF' > /etc/systemd/system/playlistai.service
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
EOF"

  # Install Python deps and start service
  msg_info "Installing Python dependencies and enabling service"
  pct exec "$CTID" -- bash -c "
    set -Eeuo pipefail
    . /opt/playlistai/venv/bin/activate
    pip install -r /opt/playlistai/requirements.txt
    systemctl enable playlistai
    systemctl start playlistai
  "
  msg_ok "PlaylistAI service started"

  # Show IP and logging hint
  IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
  echo -e "\n✅ PlaylistAI is running at http://${IP}:5000"
  echo -e "🗒️ View logs with: pct exec $CTID -- journalctl -u playlistai -f"
}

# ========= Kick off build using framework =========
start
description
msg_ok "Completed Successfully!"
