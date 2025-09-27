#!/usr/bin/env bash
# PlaylistAI Installer Script
# Runs inside the LXC container
# Author: Michael (Hoosier-IT)

set -e

echo "⚙️  Installing PlaylistAI dependencies..."

# Update and install base packages
apt-get update
apt-get install -y python3 python3-pip python3-venv git curl

# Create app directory
mkdir -p /opt/playlistai
cd /opt/playlistai

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install --upgrade pip
pip install flask music-assistant-client requests

# Write systemd service
cat <<EOF >/etc/systemd/system/playlistai.service
[Unit]
Description=PlaylistAI Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/playlistai
ExecStart=/opt/playlistai/venv/bin/python /opt/playlistai/app.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable playlistai

echo "✅ PlaylistAI installer finished. Place your app.py in /opt/playlistai and start with: systemctl start playlistai"
