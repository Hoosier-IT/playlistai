# PlaylistAI LXC Installer

AI-powered playlist generator using Music Assistant and local LLMs. Fully self-contained—no GitHub repo required.

## Features
- Interactive prompts for MA_API, LLM_API, Home Assistant Longlive TOKEN, and volume path
- Generates Flask app inside container
- Starts service at `http://<CT_IP>:5000`
- Includes uninstall script

## Usage

### Install
```bash
chmod +x install-playlistai.sh
./install-playlistai.sh
```
### Uninstall
```bash
chmod +x uninstall-playlistai.sh
./uninstall-playlistai.sh
