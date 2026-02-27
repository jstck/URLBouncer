import json
import logging
import subprocess
from pathlib import Path

CHROME_DATA = Path.home() / "Library" / "Application Support" / "Google" / "Chrome"


def open_in_profile(url: str, profile_dir: str):
    """Open url in a specific Chrome profile directory (e.g. 'Profile 1', 'Default')."""
    subprocess.run(
        ["open", "-na", "Google Chrome", "--args",
         f"--profile-directory={profile_dir}", url],
        check=True,
        timeout=10,
    )
    logging.info(f"Opened {url!r} in Chrome profile {profile_dir!r}")


def list_profiles() -> dict[str, dict]:
    """Return {directory_name: {name, email}} for all Chrome profiles."""
    profiles = {}
    for prefs_file in sorted(CHROME_DATA.glob("*/Preferences")):
        try:
            data = json.loads(prefs_file.read_text(encoding="utf-8"))
            profile = data.get("profile", {})
            accounts = data.get("account_info", [])
            account = accounts[0] if accounts else {}
            name = account.get("full_name") or account.get("given_name") or profile.get("name", prefs_file.parent.name)
            email = account.get("email", "")
            profiles[prefs_file.parent.name] = {"name": name, "email": email}
        except Exception as e:
            logging.warning(f"Could not read Chrome profile at {prefs_file}: {e}")
    return profiles
