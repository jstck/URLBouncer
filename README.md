# URLBouncer

A macOS menu bar app that intercepts every link you click in any application (Slack, Mail, Discord, etc.) and routes it to the right browser profile, application, or custom script based on configurable rules.

Originally designed for Chrome profile routing, URLBouncer now supports **Firefox profiles**, **Safari**, **Opera**, **arbitrary applications**, and **custom shell scripts**.

## What's the point of this?

By default when opening a link from some other application (such as Slack), macOS will open that in whatever window was last active. With this, you can:

- Route work-related links (slack, github, corporate systems and whatever your work may entail) to your Chrome work profile (keeping cookies/logins separate)
- Route personal links (social media, news sites and such) to your Firefox personal profile
- Route documentation to Safari (or any other app)
- Route URLs to arbitrary apps or scripts for custom handling
- Avoid having to manually choose the right browser/app before clicking links

## Requirements

- macOS 15 (Sequoia) or later
- Xcode Command Line Tools (`xcode-select --install`)

### Optional (depending on what you want to route to)
- **Chrome** — for Chrome profile routing
- **Firefox** — for Firefox profile routing (profiles: `~/.config/firefox/Profiles/`)
- **Safari** — for Safari routing (note: Safari doesn't support CLI profile switching, so all Safari opens use the default)
- **Opera** — for Opera profile routing (specify profiles by full path)

## Install

```bash
make install
```

This compiles the app, copies it to `/Applications/`, and signs the binary.

Then launch it once:

```bash
open /Applications/URLBouncer.app
```

A branch icon will appear in your menu bar. This launch is also what registers URLBouncer with macOS's Launch Services (as a handler for `http`/`https` URLs) — no separate registration step is needed.

## Set as default browser

Click the menu bar icon → **Set as Default Browser**. This registers URLBouncer directly with macOS via the Launch Services API.

From this point on, every link clicked in any app will go through URLBouncer before reaching Chrome.

> **Note:** System Settings → Desktop & Dock will continue to show "Safari" (or whatever you had before) rather than URLBouncer — this is a display quirk because URLBouncer isn't in Apple's pre-approved browser list. The routing still works correctly; you can verify via the log. You can change the default browser via System Settings to disable URLBouncer, and select **Set as Default Browser** again to reenable it.

## Configure rules

Your config file lives at `~/.config/urlbouncer/config.json`. The easiest way to open it is via the menu bar: **→ Open Config**.

URLBouncer has "profiles". Each profile specifies **how** to open a link: in a browser (with optional profile), in an application, or via a custom script. In a typical plain use-case, URLBouncer profiles correlate with browser profiles.
These are defined in the `"profiles"` object. Each profile can be one of three types:

#### 1. Browser Profile

Open a URL in a specific browser with an optional profile:

```json
{
  "profiles": {
    "chrome_work": {
      "browser": "chrome",
      "browserProfile": "Profile 1"
    },
    "firefox_personal": {
      "browser": "firefox",
      "browserProfile": "personal"
    },
    "safari_default": {
      "browser": "safari"
    },
    "opera_work": {
      "browser": "opera",
      "browserProfile": "/Users/john/Library/Application Support/com.operasoftware.Opera/work"
    },
    "chrome_work_private": {
      "browser": "chrome",
      "browserProfile": "Profile 1",
      "private": true
    }
  }
}
```

**Supported browsers:**
- `"chrome"` — Opens in Chrome with optional `browserProfile` (e.g., "Profile 1", "Profile 2")
- `"firefox"` — Opens in Firefox with optional `browserProfile` (e.g., "default", "personal")
- `"safari"` — Opens in Safari (note: `browserProfile` is ignored; Safari doesn't support CLI profile selection)
- `"opera"` — Opens in Opera with optional `browserProfile` (full path to profile directory)

**`"private"`** (optional, default `false`) — opens a private/incognito window instead of a normal one. Supported for Chrome, Firefox, and Opera (ignored for Safari, which has no such option). Can be combined with `browserProfile` — see [BROWSERS.md](BROWSERS.md#private-browsing) for what that combination actually means.

#### 2. Application Profile

Open a URL with a specific macOS application:

```json
{
  "profiles": {
    "open_notes": {
      "app": "Notes"
    },
    "open_finder": {
      "app": "Finder",
      "appPath": "/System/Library/CoreServices/Finder.app"
    }
  }
}
```

- `"app"` (required) — App name (e.g., "Notes", "Mail") or bundle ID
- `"appPath"` (optional) — Full path to `.app` bundle; if omitted, macOS searches PATH

#### 3. Script/Executable Profile

Execute a custom script or command with URL and source app substitution:

```json
{
  "profiles": {
    "my_handler": {
      "executable": "/usr/local/bin/handle_url.sh ${url} ${sourceApp}",
      "alertOnError": true
    }
  }
}
```

- `"executable"` (required) — Path to script/binary; supports two placeholders:
  - `${url}` — Replaced with the full URL
  - `${sourceApp}` — Replaced with the source application name (or empty if unknown)
- `"alertOnError"` (optional, default: false) — If `true`, shows alert when script exits with non-zero code

**Example script:**
```bash
#!/bin/bash
URL="$1"
SOURCE_APP="$2"
# Do something with $URL and $SOURCE_APP
```

### Complete Example Config

[`example-config.json`](example-config.json) in this repo is a single config exercising all the profile types and match styles below — every browser, a generic app (by name and by path), a script, hostname/path/regex matching, `sourceApp`-only rules, and a `defaultProfile` fallback. It's a reference, not a starting point — see the next section for what a fresh install actually starts with.

### What a fresh install starts with

The first time URLBouncer runs with no `~/.config/urlbouncer/config.json` yet, it generates one with **no rules at all** — every link falls straight through to a `"default"` profile pointing at whatever browser was already your system default, so nothing about your browsing changes until you add rules yourself. If that browser has more than one profile, each one is also listed under `"profiles"` (named `chrome_<profile>`, `firefox_<profile>`, or `opera_<profile>`) as a starting point for writing rules against.

### Rules

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

### Finding your browser profiles

Click the menu bar icon → **Manage Profiles** to see a dialog listing all detected browser profiles. You can use the **Copy Profiles Block** button to generate a ready-to-paste JSON profiles block for your config.

For exactly how each browser is launched (especially with a profile) and how profile discovery works under the hood — including a couple of non-obvious per-browser quirks (Chrome/Opera want different things for `browserProfile`, Firefox's display name can differ from its directory name) — see [BROWSERS.md](BROWSERS.md).

## Menu bar options

| Item | What it does |
|------|-------------|
| Set as Default Browser | Registers URLBouncer as the default browser with macOS |
| Open Config | Opens `~/.config/urlbouncer/config.json` in your default text editor |
| Reload Config | Confirms how many rules are loaded and the default profile (config is always live) |
| Manage Profiles | Shows all detected browser profiles (Chrome, Firefox, Opera) and offers a "Copy Profiles Block" button to generate JSON for your config |
| Show Log | Opens the log in Console.app (`~/Library/Logs/URLBouncer/urlbouncer.log`) |
| Log URLs | Toggle: when on, logs every received URL and routing decision. Includes sensitive URL info. For privacy, this is off by default and resets when URLBouncer restarts |
| Quit URLBouncer | Exits the app |

## Error Handling & Logging

### Application Errors

If an application (browser, script, etc.) fails to launch:
- **Always logged** to `~/Library/Logs/URLBouncer/urlbouncer.log` with error details
- **Always shows alert** to notify you something went wrong
- URLs are **redacted in logs** unless "Log URLs" is enabled in the menu

### Script Execution Errors

When executing a custom script:
- **Always logged** with: full command line, exit code, stdout, and stderr (first 500 chars)
- **Alert shown only if** `"alertOnError": true` is set in that profile's config
- URLs are **redacted in logs** unless "Log URLs" is enabled

### Debugging

To see detailed routing and execution information:
1. Click menu → **Log URLs** to enable detailed logging
2. Click menu → **Show Log** to open the log viewer
3. Perform the action you're debugging
4. Watch the real-time log output in Console.app

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

## Troubleshooting

### Check which app macOS thinks is the default browser

```bash
defaults read com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers | grep -B2 -A3 'LSHandlerURLScheme = http\b\|LSHandlerURLScheme = https'
```

Look for `LSHandlerRoleAll = "com.local.urlbouncer";` next to `LSHandlerURLScheme = http` and `https`. This is the actual state macOS uses for routing — it's independent of what System Settings → Default web browser happens to display (see the note under "Set as default browser" above).

### Confirm URLBouncer is registered with Launch Services

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -A 15 "com.local.urlbouncer"
```

Shows the bundle path, version, and URL types Launch Services has on file. If this points at a stale path (e.g. after moving the app), just launch it again (`open /Applications/URLBouncer.app`) — launching is what registers it, there's no separate registration step.

### "Set as Default Browser" doesn't seem to do anything

- Make sure you approve the system confirmation dialog macOS shows when you click the menu item — the change only takes effect once you approve it there.
- Then re-check with the `defaults read` command above; the change is real even though System Settings' picker won't reflect it.
- Still nothing? Quit and relaunch URLBouncer, then try again.

### Switching back to another browser

URLBouncer being your default doesn't remove Chrome/Firefox/Safari/Opera from System Settings → Default web browser — open that dropdown and pick one of them directly; unlike URLBouncer, they're all still regular, picker-eligible apps.

### Uninstalling

```bash
# 1. Switch your default browser back to something else first (see above)

# 2. Quit the app
osascript -e 'tell application "URLBouncer" to quit' 2>/dev/null || killall URLBouncer

# 3. Unregister it from Launch Services, then remove it
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/URLBouncer.app
rm -rf /Applications/URLBouncer.app

# 4. Remove its config, log, and state
rm -rf ~/.config/urlbouncer
rm -rf ~/Library/Logs/URLBouncer
```

If you added URLBouncer to Login Items, also remove it via System Settings → General → Login Items.

## Updating after config or code changes

If you only edited `~/.config/urlbouncer/config.json`, no action is needed — changes are live immediately.

If you changed the app, rebuild and relaunch:

```bash
make install
open /Applications/URLBouncer.app
```

Running `make install` will not overwrite your config.

## License

[MIT](LICENSE)
