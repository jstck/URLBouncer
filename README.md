# URLBouncer

A macOS menu bar app that intercepts every link you click in any application (Slack, Mail, etc.) and opens it in the right Google Chrome profile based on configurable rules.

## What's the point of this?

By default when opening a link from some other application (such as Slack), Chrome will open that in whatever window was last active. With this, clearly work-related things can be kept to the "work profile", and obviously non-work things in another profile. Helps to keep cookies and logins and history separate between them, and not having to first choose the right browser window before clicking links elsewhere.

## Who made this?
Mostly Claude, with managerial direction from Stäck.

## Requirements

- macOS 15 (Sequoia) or later
- Xcode Command Line Tools (`xcode-select --install`)
- Google Chrome

## Install

```bash
make install
```

This compiles the app, copies it to `/Applications/`, and registers it with macOS. Note that this also signs the installed binary.

Then launch it once:

```bash
open /Applications/URLBouncer.app
```

A branch icon will appear in your menu bar.

## Set as default browser

Click the menu bar icon → **Set as Default Browser**. This registers URLBouncer directly with macOS via the Launch Services API.

From this point on, every link clicked in any app will go through URLBouncer before reaching Chrome.

> **Note:** System Settings → Desktop & Dock will continue to show "Safari" (or whatever you had before) rather than URLBouncer — this is a display quirk because URLBouncer isn't in Apple's pre-approved browser list. The routing still works correctly; you can verify via the log. You can change the default browser via System Settings to disable URLBouncer, and select **Set as Default Browser** again to reenable it.

## Configure rules

Your config file lives at `~/.config/urlbouncer/config.json`. The easiest way to open it is via the menu bar: **→ Open Config**.

```json
{
  "profiles": {
    "work":     "Profile 1",
    "personal": "Profile 2"
  },
  "rules": [
    {"match": "github.com",                              "profile": "work"},
    {"match": "docs.google.com", "sourceApp": "Slack",   "profile": "work"},
    {"sourceApp": "WhatsApp",                            "profile": "personal"},
    {"match": "youtube.com",                             "profile": "personal"}
  ],
  "defaultProfile": null
}
```

Set `"profile": null` (or `"defaultProfile": null`) to open URLs in Chrome without specifying a profile — Chrome will use whatever window was last active.

The `profiles` map is optional and just for convenient friendly names for the profiles. You can still write `"profile": "Profile 1"` directly in rules if you prefer.

Rules are matched top-to-bottom; the first match wins. No restart is needed after editing — the config is re-read on every link click.

### Match syntax

| Example | Matches against |
|---------|----------------|
| `"github.com"` | Hostname (case-insensitive substring) |
| `"github.com/myorg/"` | Full URL (pattern contains `/`) |
| `"re:^https://meet\\.google\\.com/"` | Full URL regex (prefix `re:`) |
| omitted or `null` | Any URL (useful combined with `sourceApp`) |

### Source app filtering

Add `"sourceApp"` to any rule to only match URLs opened from a specific app. The value is a case-insensitive substring matched against the app's bundle identifier or display name:

```json
{"match": "docs.google.com", "sourceApp": "Slack",                        "profile": "Profile 1"},
{"match": "docs.google.com", "sourceApp": "com.tinyspeck.slackmacgap",    "profile": "Profile 1"},
{"match": "docs.google.com", "sourceApp": "Telegram",                     "profile": "Profile 2"}
```

Rules without `sourceApp` match links from any app. To discover an app's bundle ID, enable **Log URLs** in the menu bar and click a link — the log will show `from: AppName [com.bundle.id]`.

### Finding your profile directory names

Click the menu bar icon → **Chrome Profiles** to see a dialog like this:

![Chrome Profiles dialog](profiles.png)

The left column (`Profile 1`, `Profile 2`, etc.) is what you put in the config. The right side shows the account name and email so you can tell them apart.

## Menu bar options

| Item | What it does |
|------|-------------|
| Set as Default Browser | Registers URLBouncer as the default browser with macOS |
| Open Config | Opens `~/.config/urlbouncer/config.json` in your default text editor |
| Reload Config | Confirms how many rules are loaded (config is always live) |
| Chrome Profiles | Shows all detected Chrome profiles with names and emails |
| Show Log | Opens the log in Console.app (`~/Library/Logs/URLBouncer/urlbouncer.log`) |
| Log URLs | Toggle: when on, logs every received URL and routing decision. For privacy reasons this is off by default, and only stays on until next time URLBouncer is restarted (or option is unchecked) |
| Quit URLBouncer | Exits the app |

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
This is not usually needed, as the registered default browser will get launched whenever a URL is opened.

## Updating after config or code changes

If you only edited `~/.config/urlbouncer/config.json`, no action is needed — changes are live immediately.

If you changed `src/main.swift`, rebuild and relaunch:

```bash
make install
open /Applications/URLBouncer.app
```

Running `make install` will not overwrite your config.
