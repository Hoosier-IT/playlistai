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
  local MA_API="" LLM_API="" TOKEN="" MUSIC_PATH="" HA_WS_URL=""

  while [ -z "$MA_API" ]; do
    read -rp "🔗 Enter your Music Assistant API URL (standalone, e.g. http://192.168.3.10:8095): " MA_API
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
  while [ -z "$HA_WS_URL" ]; do
    read -rp "🌐 Enter your HA WebSocket URL (e.g. ws://homeassistant.home:8123/api/websocket): " HA_WS_URL
  done

  msg_info "Installing Python and dependencies"
  apt update
  apt install -y python3 python3-pip python3-venv ca-certificates curl
  mkdir -p /opt/playlistai
  python3 -m venv /opt/playlistai/venv
  msg_ok "Python environment ready"

  msg_info "Creating PlaylistAI files"

  # app.py
  cat << 'EOF' > /opt/playlistai/app.py
import os
import json
import asyncio
import requests
import websockets
import logging
from flask import Flask, request, jsonify
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

app = Flask(__name__)

MA_API = os.getenv("MA_API")
LLM_API = os.getenv("LLM_API")
TOKEN = os.getenv("TOKEN")
HA_WS_URL = os.getenv("HA_WS_URL")

logger = logging.getLogger("playlistai")
logger.setLevel(logging.INFO)

_cached_mode = None  # "rest" or "ws"

def fetch_library():
    global _cached_mode
    if _cached_mode == "rest":
        return _fetch_library_rest()
    elif _cached_mode == "ws":
        return asyncio.run(fetch_library_ws())

    try:
        data = _fetch_library_rest()
        if data:
            _cached_mode = "rest"
            return data
    except Exception as e:
        logger.warning("PlaylistAI: REST API failed (%s), trying WebSocket", e)

    try:
        data = asyncio.run(fetch_library_ws())
        _cached_mode = "ws"
        return data
    except Exception as e:
        logger.error("PlaylistAI: Both REST and WebSocket failed (%s)", e)
        raise

def _fetch_library_rest():
    headers = {"Authorization": f"Bearer {TOKEN}"} if TOKEN else {}
    for path in ("/library", "/v1/library"):
        url = f"{MA_API.rstrip('/')}{path}"
        try:
            r = requests.get(url, headers=headers, timeout=10)
            if r.status_code == 200:
                logger.info("PlaylistAI: Using REST API at %s", url)
                return r.json()
        except Exception as e:
            logger.debug("PlaylistAI: REST attempt %s failed: %s", url, e)
    return None

async def fetch_library_ws():
    async with websockets.connect(HA_WS_URL) as ws:
        await ws.recv()
        await ws.send(json.dumps({
            "type": "auth",
            "access_token": TOKEN
        }))
        auth_result = await ws.recv()
        logger.info("PlaylistAI: WebSocket auth result: %s", auth_result)

        await ws.send(json.dumps({
            "id": 1,
            "type": "call_service",
            "domain": "music_assistant",
            "service": "get_library",
            "service_data": {}
        }))
        response = await ws.recv()
        logger.info("PlaylistAI: Using HA WebSocket API at %s", HA_WS_URL)
        return json.loads(response
