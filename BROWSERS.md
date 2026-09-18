# Browser integration details

How URLBouncer actually launches each browser/app (especially with a profile), and how it discovers installed profiles for the "Manage Profiles" menu. Split out of the main README to keep that one shorter. The actual code lives in `Sources/URLBouncerCore/Openers.swift` (launching) and `Sources/URLBouncerCore/ProfileDiscovery.swift` (discovery).

**No profile specified, in general:** a profile with no `browserProfile` (or a rule with no matching profile at all, falling to a profile-less default) is deliberately given *no* profile-selection argument of any kind — not even a "use the default one" flag. It's handed to the browser exactly as if you'd clicked the link with URLBouncer out of the picture entirely: whatever's already running gets it, landing in whatever window was last active. This is true for all four browsers below; see each one's "No profile" note for the specific mechanics.

## Chrome

### Launching

With a profile:
```
open -na "Google Chrome" --args --profile-directory=<profile> <url>
```

`-na` (`-n` new instance, `-a` by app name) forces `open` to spawn a brand-new OS process for every request, carrying the launch arguments along with it. Chrome's own per-profile single-instance lock then decides what actually happens:

- If a Chrome process is already running for that *specific* `--profile-directory`, the new process hands the request off to it over IPC and exits — the URL lands in the existing window for that profile.
- If not, the new process becomes the persistent one, opening a fresh window for that profile.

Without `-n`, if Chrome is already running (under any profile) and macOS is asked to "open" it again, it just re-activates the existing process — the launch arguments, including `--profile-directory`, are silently dropped, and the URL opens under whatever profile happened to already be running instead of the one you asked for. That's exactly why the profile case needs `-n`.

**No profile:**
```
open -a "Google Chrome" <url>
```
No `-n` here — there's no `--profile-directory` to force-deliver, so there's nothing to gain from spawning a redundant process. This just hands the URL to whatever Chrome process is already running (or launches fresh if none is), landing in Chrome's own idea of the current/last-used profile and window — the same place a plain click would have landed it with no URLBouncer involved at all.

`browserProfile` is a **directory name** relative to `~/Library/Application Support/Google/Chrome/` (e.g. `Default`, `Profile 1`) — not a display name.

### Profile discovery

- Directory: `~/Library/Application Support/Google/Chrome/`
- A subdirectory counts as a profile only if it contains a readable `Preferences` file (valid JSON) — this is what excludes Chrome's own non-profile support directories (`Crash Reports`, caches, etc.) from being listed.
- Display name comes from, in order: `account_info[0].full_name`, `account_info[0].given_name`, `profile.name`, falling back to the directory name if none are present.
- Email (if any) comes from `account_info[0].email`.

## Firefox

### Launching

With a profile:
```
/Applications/Firefox.app/Contents/MacOS/firefox -P <profile> <url>
```

This launches the Firefox binary **directly** rather than via `open`. `-P <name>` is Firefox's own profile-selection flag, looked up by name against `profiles.ini` — not a path. Firefox has its own remote/singleton mechanism too (scoped per profile), so the same "reuses an existing window for that profile, otherwise starts a fresh one" behavior applies as with Chrome.

`browserProfile` is the profile's **name** as it appears in `profiles.ini` — which can differ from its directory name (see below).

**No profile:**
```
/Applications/Firefox.app/Contents/MacOS/firefox <url>
```
No `-P` at all, so Firefox falls back to its own default remoting behavior: send the URL to whatever instance is already running (any profile), landing in the current window, same as a plain click without URLBouncer.

### Profile discovery

- Directory: `~/Library/Application Support/Firefox/Profiles/`
- Display names come from `~/Library/Application Support/Firefox/profiles.ini`, parsed for each `[ProfileN]` section's `Name=`/`Path=` keys, matched against each profile directory's name.
- If `profiles.ini` is missing, unreadable, or has no matching section for a given directory (e.g. a manually-created profile), falls back to using the directory name itself as the display name.

## Opera

### Launching

With a profile:
```
open -na Opera --args --user-data-dir=<profile> <url>
```

Same reasoning as Chrome's `-na` above. **This was a real bug for a while**: Opera's opener originally didn't pass `-n`, so routing a link to an Opera profile that wasn't the currently-running one silently did nothing at all — no window opened, no error, nothing logged beyond the normal "opened" message (which fired regardless of whether anything actually happened). Fixed to match Chrome's approach.

`browserProfile` is a **full filesystem path** to the profile directory (unlike Chrome's bare directory name), passed straight through as Chromium's `--user-data-dir`.

**No profile:**
```
open -a Opera <url>
```
Same reasoning as Chrome's no-profile case — no `-n`, just hands off to whatever's already running.

### Profile discovery

- Directory: `~/Library/Application Support/com.operasoftware.Opera/` — **not** `~/Library/Application Support/Opera/Profiles/`, which doesn't exist on a standard install. Opera names its user-data-dir by bundle identifier, and (like Chrome, unlike Firefox) keeps profile directories directly inside it rather than under a nested `Profiles/` folder. This was also a real bug: profile discovery silently found nothing, so Opera never appeared in "Manage Profiles" even with a normal, working Opera install.
- Same detection rule as Chrome: a subdirectory counts as a profile only if it contains a `Preferences` file (excludes `Crash Reports`, `WidevineCdm`, and Opera's other support directories that live alongside real profiles).
- Display name is just the directory name (e.g. `Default`, `Profile 1`) — no attempt is made to read a friendlier name out of `Preferences` the way Chrome's discovery does.

## Safari

### Launching

```
open -a Safari <url>
```

No `-n`, no profile argument of any kind — Safari has no CLI mechanism for profile or window selection at all. A `browserProfile` value in config is accepted (so the same config shape works across browsers) but silently ignored. Links always land in whatever Safari window is currently active.

### Profile discovery

Not implemented — there's nothing to discover, and "Manage Profiles" never shows a Safari section.

## Generic apps (`"app"` profile type)

- By name: `open -a <appName> <url>`
- By path: `NSWorkspace.shared.open(url, withApplicationAt: appPath)` — not shelled out via `open` at all.
- No profile concept. `appPath` just picks a specific app bundle when more than one app shares the same name.

## Scripts (`"executable"` profile type)

Not a browser launch at all: runs `/bin/bash -c "<command>"`, where `<command>` is the configured `executable` string with `${url}` and `${sourceApp}` substituted in, each wrapped in single quotes with proper shell escaping (a literal `'` in either value becomes `'\''`, so injection via either placeholder isn't possible).
