#!/usr/bin/env bash
# PlaylistAI LXC Installer (Final Adaptive Version)
# Author: (Hoosier-IT)
# License: MIT
# Version: 3.2

set -Eeuo pipefail

# ===== Input prompts with validation =====
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

APP="PlaylistAI"
CTID=$(pvesh get /cluster/nextid)
DISK_SIZE="4"       # GB
MEMORY="1024"       # MB
CORE_COUNT="2"

die() { echo "❌ $1" >&2; exit 1; }

# ===== Ensure music path exists =====
if [ ! -d "$MUSIC_PATH" ]; then
  echo "📁 Creating $MUSIC_PATH"
  mkdir -p "$MUSIC_PATH" || die "Failed to create $MUSIC_PATH"
fi

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

# ===== Detect storage (force local if lvmthin unusable) =====
STORAGES=$(pvesm status | awk 'NR>1 {print $1}')
CANDIDATES=()
for id in $STORAGES; do
  cfg=$(pvesm config "$id" 2>/dev/null || true)
  content=$(awk -F': ' '/^content:/{print $2}' <<<"$cfg")
  [[ "$content" =~ rootdir ]] && CANDIDATES+=("$id")
done
[ ${#CANDIDATES[@]} -gt 0 ] || die "No storage supports rootdir."

# Prefer local if available
if [[ " ${CANDIDATES[*]} " =~ " local " ]]; then
  ROOTSTORE="local"
elif [[ " ${CANDIDATES[*]} " =~ " local-lvm " ]]; then
  ROOTSTORE="local-lvm"
else
  ROOTSTORE="${CANDIDATES[0]}"
fi
ROOTFS="--rootfs ${ROOTSTORE}:${DISK_SIZE}G"

echo "💾 Using storage: $ROOTSTORE"
echo "🌉 Using bridge: $BRIDGE"

# ===== Detect template =====
TEMPLATE=$(pveam available | awk '/debian-12-standard/ {print $2}' | tail -n1)
[ -n "$TEMPLATE" ] || die "No Debian 12 template found in pveam."
if ! pveam list local | awk '{print $1}' | grep -q "$TEMPLATE"; then
  echo "📥 Downloading template $TEMPLATE..."
  pveam download local "$TEMPLATE"
fi

# ===== Create container =====
echo "🧠 Creating $APP container (CT $CTID)..."
pct create "$CTID" "local:vztmpl/$TEMPLATE" \
  --hostname playlistai \
  --cores "$CORE_COUNT" \
  --memory "$MEMORY" \
  --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  --ostype debian \
  $ROOTFS \
  --features nesting=1 \
  --unprivileged 1 \
  --mp0 "${MUSIC_PATH},mp=/data/music" \
  --start 1

# ===== Bootstrap app =====
echo "📦 Installing Python and dependencies..."
pct exec "$CTID" -- bash -c "
  apt update &&
  apt install -y python3 python3-pip python3-venv ca-certificates curl
  python3 -m venv /opt/playlistai/venv
"

echo "📁 Creating PlaylistAI app files..."
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
  . /opt/playlistai/venv/bin/activate
  pip install -r /opt/playlistai/requirements.txt
  systemctl enable playlistai
  systemctl start playlistai
"

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
echo "✅ $APP is running at http://$IP:5000"
echo "🗒️ View logs with: pct exec $CTID -- journalctl -u playlistai -f"
