# URLBouncer

A macOS menu bar app that intercepts every link you click in any application (Slack, Mail, etc.) and opens it in the right Google Chrome profile based on configurable rules.

## What's the point of this?

By default when opening a link from some other application (such as Slack), Chrome will open that in whatever window was last active. With this, clearly work-related things can be kept to the "work profile", and obviously non-work things in another profile. Helps to keep
cookies and logins and history separate between them.

100% vibe coded, I have no business doing Swift things dealing with MacOS specifics myself.

## Requirements

- macOS 12+
- Xcode Command Line Tools (`xcode-select --install`)
- Google Chrome

## Install

```bash
make install
```

This compiles the app, copies it to `/Applications/`, and registers it with macOS.

Then launch it once:

```bash
open /Applications/URLBouncer.app
```

A branch icon will appear in your menu bar.

## Set as default browser

Click the menu bar icon → **Set as Default Browser**. This registers URLBouncer directly with macOS via the Launch Services API.

From this point on, every link clicked in any app will go through URLBouncer before reaching Chrome.

> **Note:** System Settings → Desktop & Dock will continue to show "Safari" (or whatever you had before) rather than URLBouncer — this is a display quirk because URLBouncer isn't in Apple's pre-approved browser list. The routing still works correctly; you can verify via the log. If you ever accidentally change the default browser via System Settings, just click **Set as Default Browser** again.

## Configure rules

Your config file lives at `~/.config/urlbouncer/config.json`. The easiest way to open it is via the menu bar: **→ Open Config**.

```json
{
  "rules": [
    {"match": "github.com",  "profile": "Profile 1"},
    {"match": "youtube.com", "profile": "Profile 2"}
  ],
  "defaultProfile": "Profile 2"
}
```

Rules are matched top-to-bottom; the first match wins. No restart is needed after editing — the config is re-read on every link click.

### Match syntax

| Example | Matches against |
|---------|----------------|
| `"github.com"` | Hostname (case-insensitive substring) |
| `"github.com/myorg/"` | Full URL (pattern contains `/`) |
| `"re:^https://meet\\.google\\.com/"` | Full URL regex (prefix `re:`) |

### Finding your profile directory names

Click the menu bar icon → **Chrome Profiles** to see a dialog like this:

![Chrome Profiles dialog](profiles.png)

The left column (`Profile 1`, `Profile 2`, etc.) is what you put in the config. The right side shows the account name and email so you can tell them apart.

## Menu bar options

| Item | What it does |
|------|-------------|
| Open Config | Opens `~/.config/urlbouncer/config.json` in your default text editor |
| Reload Config | Confirms how many rules are loaded (config is always live) |
| Chrome Profiles | Shows all detected Chrome profiles with names and emails |
| Show Log | Opens the log in Console.app (`~/Library/Logs/URLBouncer/urlbouncer.log`) |
| Quit URLBouncer | Exits the app (links will stop working until you relaunch) |

## Testing without setting as default browser

You can test the app before changing your default browser by sending it a URL directly:

```bash
osascript -e 'tell application "URLBouncer" to open location "https://github.com/test"'
```

Watch what happens in real time:

```bash
tail -f ~/Library/Logs/URLBouncer/urlbouncer.log
```

## Auto-start on login

Go to **System Settings → General → Login Items** and add `/Applications/URLBouncer.app`.

## Updating after config or code changes

If you only edited `~/.config/urlbouncer/config.json`, no action is needed — changes are live immediately.

If you changed `src/main.swift`, rebuild and relaunch:

```bash
make install
open /Applications/URLBouncer.app
```
