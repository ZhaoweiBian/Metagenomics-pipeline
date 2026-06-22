"""本地配置读写。"""
import json
import os
from pathlib import Path

CONFIG_DIR = Path.home() / ".metagenomics_desktop"
CONFIG_FILE = CONFIG_DIR / "settings.json"

DEFAULTS = {
    "host": "",
    "port": 22,
    "username": "",
    "auth_method": "key",  # key | password
    "private_key": str(Path.home() / ".ssh" / "id_rsa"),
    "password": "",
    "remote_script_dir": "/data1/bianzw/metagenomics/script",
    "project_root": "/data1/bianzw/hlbw",
    "enable_email": False,
    "run_mode": "phase",
    "step_id": "7.3",
    "from_step": "7.3",
    "to_step": "7.4",
    "phase": "mag_function",
    "local_samplelist": "",
    "queue_stop_on_error": True,
}


def load_settings():
    if not CONFIG_FILE.exists():
        return dict(DEFAULTS)
    with open(CONFIG_FILE, encoding="utf-8") as f:
        data = json.load(f)
    merged = dict(DEFAULTS)
    merged.update(data)
    return merged


def save_settings(data):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    to_save = dict(DEFAULTS)
    to_save.update(data)
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(to_save, f, indent=2, ensure_ascii=False)
