# PlaylistAI LXC Installer

PlaylistAI is a Flask API that curates playlists using [Music Assistant](https://music-assistant.io/) and an LLM.  
It runs inside a lightweight Debian 12 LXC container on Proxmox VE.

---

## ✨ Features
- Interactive prompts for:
  - Music Assistant API URL
  - LLM API URL
  - Home Assistant Long‑Lived Access Token
  - Host music folder path
- Generates a Flask app inside the container
- Binds your host music folder into `/data/music` inside the container
- Starts a systemd service at:  
  `http://<CT_IP>:5000/generate`

---

## 📦 Default Container Settings
- **OS:** Debian 12  
- **Type:** Unprivileged  
- **Disk:** 4 GB  
- **CPU:** 2 cores  
- **RAM:** 1024 MiB  

---

## 🚀 Installation

Run the following command on your Proxmox host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Hoosier-IT/playlistai/main/ct/playlistai.sh)"
