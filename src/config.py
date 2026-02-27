import shutil
import logging
from pathlib import Path

import yaml

CONFIG_DIR = Path.home() / ".config" / "urlbouncer"
CONFIG_FILE = CONFIG_DIR / "config.yaml"
_BUNDLE_DEFAULT = Path(__file__).parent.parent / "config.yaml"

DEFAULT_CONFIG = {
    "rules": [],
    "default_profile": "Default",
}


def ensure_config_exists():
    if not CONFIG_FILE.exists():
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        if _BUNDLE_DEFAULT.exists():
            shutil.copy(_BUNDLE_DEFAULT, CONFIG_FILE)
        else:
            with open(CONFIG_FILE, "w") as f:
                yaml.dump(DEFAULT_CONFIG, f, default_flow_style=False)
        logging.info(f"Created default config at {CONFIG_FILE}")


def load_config() -> dict:
    ensure_config_exists()
    try:
        with open(CONFIG_FILE) as f:
            config = yaml.safe_load(f) or {}
        config.setdefault("rules", [])
        config.setdefault("default_profile", DEFAULT_CONFIG["default_profile"])
        return config
    except Exception as e:
        logging.error(f"Failed to load config: {e}")
        return DEFAULT_CONFIG.copy()
