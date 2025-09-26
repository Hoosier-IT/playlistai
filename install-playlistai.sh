#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Metadata
APP="PlaylistAI"
var_os="debian"
var_version="12"
var_cpu="2"
var_ram="1024"
var_disk="4"
var_unprivileged="1"
var_tags="music;llm;flask"

NEXTID=$(pvesh get /cluster/nextid)
CTID=${var_ctid:-$NEXTID}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  read -rp "🔗 Enter your Music Assistant API URL: " MA_API
  read -rp "🧠 Enter your LLM API URL: " LLM_API
  read -rp "🔐 Enter your Home Assistant token: " TOKEN

  msg_info "Installing Python and dependencies"
  pct exec "$CTID" -- bash -c "
    apt update &&
    apt install -y python3 python3-pip python3-venv ca-certificates curl &&
    python3 -m venv /opt/playlistai/venv
  "
  msg_ok "Python installed"

  msg_info "Creating PlaylistAI app files"
  pct exec "$CTID" -- bash -c "mkdir -p /opt/playlistai"

  # app.py
  pct exec "$CTID" -- bash -c "cat << 'EOF' > /opt/playlistai/app.py
import os, json, requests
from flask import Flask, request, jsonify
from dotenv import load_dotenv

load_dotenv()
app = Flask(__name__)
MA_API, LLM_API, TOKEN = os.getenv('MA_API'), os.getenv('LLM_API'), os.getenv('TOKEN')

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
    if 'choices' in data: return data['choices'][0]['message']['content']
    if 'message' in data: return data['message']
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

  # requirements.txt
  pct exec "$CTID" -- bash -c "cat << 'EOF' > /opt/playlistai/requirements.txt
flask
requests
python-dotenv
EOF"

  # config.env
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

  pct exec "$CTID" -- bash -c "
    . /opt/playlistai/venv/bin/activate &&
    pip install -r /opt/playlistai/requirements.txt &&
    systemctl enable playlistai &&
    systemctl start playlistai
  "

  IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
  echo -e "\n✅ PlaylistAI is running at http://${IP}:5000"
  echo -e "🗒️ View logs with: pct exec $CTID -- journalctl -u playlistai -f"
}

start
description
msg_ok "Completed Successfully!"
