import struct
import subprocess
import sys
import logging
from pathlib import Path

# Configure logging before any framework imports
_log_dir = Path.home() / "Library" / "Logs" / "URLBouncer"
_log_dir.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(_log_dir / "urlbouncer.log"),
        logging.StreamHandler(sys.stderr),
    ],
)

import objc
import rumps
from AppKit import NSObject
from Foundation import NSAppleEventManager

from browser import list_profiles, open_in_profile
from config import CONFIG_FILE, load_config
from router import route_url


def _fourcc(code: bytes) -> int:
    return struct.unpack(">i", code)[0]


kInternetEventClass = _fourcc(b"GURL")
kAEGetURL = _fourcc(b"GURL")
keyDirectObject = _fourcc(b"----")


class URLEventHandler(NSObject):
    """
    Standalone NSObject registered with NSAppleEventManager.
    Kept separate from rumps' NSApplication delegate to avoid conflicts.
    app_ref must be set to the URLBouncerApp instance before the run loop starts.
    """

    app_ref = None

    @objc.typedSelector(b"v@:@@")
    def handleGetURL_withReplyEvent_(self, event, reply):
        desc = event.paramDescriptorForKeyword_(keyDirectObject)
        if desc is None:
            logging.warning("GetURL event: no direct object descriptor")
            return
        url = desc.stringValue()
        if not url:
            logging.warning("GetURL event: empty URL string")
            return
        if self.app_ref is not None:
            self.app_ref.dispatch(url)


class URLBouncerApp(rumps.App):

    def __init__(self):
        super().__init__("URLBouncer", title="[↗]", quit_button="Quit URLBouncer")
        self._handler = None  # strong reference — NSAppleEventManager does not retain

        self.menu = [
            rumps.MenuItem("Open Config", callback=self._open_config),
            rumps.MenuItem("Reload Config", callback=self._reload_config),
            None,
            rumps.MenuItem("Chrome Profiles", callback=self._show_profiles),
            None,
            rumps.MenuItem("Show Log", callback=self._show_log),
        ]

    def run(self):
        # Register Apple Event handler BEFORE the run loop starts.
        # Cold-launch URL events (app not yet running when user clicks a link) fire
        # between applicationWillFinishLaunching and applicationDidFinishLaunching.
        # Registering here (before super().run() calls NSApplication.run()) ensures
        # we never miss the first URL.
        self._handler = URLEventHandler.alloc().init()
        self._handler.app_ref = self
        mgr = NSAppleEventManager.sharedAppleEventManager()
        # NOTE: selector string must use ObjC colon notation, not Python underscores.
        mgr.setEventHandler_andSelector_forEventClass_andEventID_(
            self._handler,
            "handleGetURL:withReplyEvent:",
            kInternetEventClass,
            kAEGetURL,
        )
        logging.info("Apple Event handler registered; starting run loop")
        super().run()

    def dispatch(self, url: str):
        config = load_config()
        profile = route_url(url, config)
        try:
            open_in_profile(url, profile)
        except subprocess.CalledProcessError as e:
            msg = e.stderr.decode("utf-8", errors="replace") if e.stderr else str(e)
            logging.error(f"Failed to open {url!r} in profile {profile!r}: {msg}")
            rumps.notification(
                "URLBouncer",
                f"Could not open in Chrome ({profile})",
                f"{url}\n{msg}",
            )
        except subprocess.TimeoutExpired:
            logging.error(f"Timeout opening {url!r} in profile {profile!r}")

    def _open_config(self, _):
        from config import ensure_config_exists
        ensure_config_exists()
        subprocess.run(["open", "-t", str(CONFIG_FILE)])

    def _reload_config(self, _):
        try:
            config = load_config()
            count = len(config.get("rules", []))
            default = config.get("default_profile", "Default")
            rumps.notification(
                "URLBouncer",
                "Config reloaded",
                f"{count} rule(s) • default profile: {default}",
            )
        except Exception as e:
            rumps.notification("URLBouncer", "Config error", str(e))

    def _show_profiles(self, _):
        profiles = list_profiles()
        if not profiles:
            rumps.alert("Chrome Profiles", "No profiles found.")
            return
        lines = []
        for d, info in sorted(profiles.items()):
            label = f"{d}  →  {info['name']}"
            if info["email"]:
                label += f"  ({info['email']})"
            lines.append(label)
        rumps.alert("Chrome Profiles", "\n".join(lines))

    def _show_log(self, _):
        log_path = _log_dir / "urlbouncer.log"
        subprocess.run(["open", "-a", "Console", str(log_path)])


def main():
    app = URLBouncerApp()
    app.run()


if __name__ == "__main__":
    main()
