#!/usr/bin/env bash
# PlaylistAI LXC Installer
# Description: AI-powered playlist generator using Music Assistant + local LLM
# Author: (Hoosier-IT)
# License: MIT
# Version: 1.1

set -Eeuo pipefail

# Interactive prompts
read -rp "🔗 Enter your Music Assistant API URL: " MA_API
read -rp "🧠 Enter your LLM API URL: " LLM_API
read -rp "🔐 Enter your Home Assistant token: " TOKEN
read -rp "🎵 Enter your music folder path on Proxmox host (e.g., /mnt/music): " MUSIC_PATH

# Constants
APP="PlaylistAI"
CTID=$(pvesh get /cluster/nextid)
DISK_SIZE="4"
MEMORY="1024"
CORE_COUNT="2"
BRIDGE="vmbr0"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"

# Detect storage type
if pvesm status | grep -q 'local-lvm'; then
  STORAGE="local-lvm"
  ROOTFS="--rootfs $STORAGE:${DISK_SIZE}G"
else
  STORAGE="local"
  ROOTFS="--rootfs $STORAGE,volume=${APP}-root,size=${DISK_SIZE}G"
fi

echo "🧠 Creating $APP container (CT $CTID)..."
pct create $CTID local:vztmpl/$TEMPLATE \
  --hostname playlistai \
  --cores $CORE_COUNT \
  --memory $MEMORY \
  --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  --ostype debian \
  $ROOTFS \
  --features nesting=1 \
  --unprivileged 1 \
  --mp0 ${MUSIC_PATH},mp=/data/music \
  --start 1

echo "📦 Installing Python and dependencies..."
pct exec $CTID -- bash -c "
  apt update &&
  apt install -y python3 python3-pip &&
  pip3 install flask requests python-dotenv
"

echo "📁 Creating PlaylistAI app files..."
pct exec $CTID -- bash -c "mkdir -p /opt/playlistai"

# app.py
pct exec $CTID -- bash -c "cat << 'EOF' > /opt/playlistai/app.py
import os
import json
import requests
from flask import Flask, request, jsonify
from dotenv import load_dotenv

load_dotenv()
app = Flask(__name__)

MA_API = os.getenv('MA_API')
LLM_API = os.getenv('LLM_API')
TOKEN = os.getenv('TOKEN')

def fetch_library():
    headers = {'Authorization': f'Bearer {TOKEN}'}
    response = requests.get(f'{MA_API}/media/library', headers=headers)
    return response.json()

def query_llm(library_json, prompt):
    payload = {
        'messages': [
            {'role': 'system', 'content': 'You are a music curator.'},
            {'role': 'user', 'content': f'{prompt}\\n\\n{json.dumps(library_json)}'}
        ]
    }
    response = requests.post(LLM_API, json=payload)
    return response.json()['choices'][0]['message']['content']

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
pct exec $CTID -- bash -c "cat << 'EOF' > /opt/playlistai/requirements.txt
flask
requests
python-dotenv
EOF"

# config.env
pct exec $CTID -- bash -c "cat << EOF > /opt/playlistai/config.env
MA_API=$MA_API
LLM_API=$LLM_API
TOKEN=$TOKEN
EOF"

echo "🚀 Starting PlaylistAI..."
pct exec $CTID -- bash -c "
  cd /opt/playlistai &&
  nohup python3 app.py &
"

IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
echo "✅ $APP is running at http://$IP:5000"
