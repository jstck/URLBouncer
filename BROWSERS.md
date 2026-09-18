# Browser details

For each browser: what to put in `browserProfile`, what happens if you leave it out, and where profiles come from for the **Manage Profiles** menu.

**If you don't specify a profile** (or a rule's target profile isn't found), the link opens in whatever window is currently active for that browser — the same place it would land if you'd clicked it normally, with URLBouncer out of the picture entirely. This holds for every browser below.

## Chrome

- `browserProfile`: the profile's **directory name** (e.g. `Default`, `Profile 1`) — find yours via **Manage Profiles** in the menu bar.
- Profile discovery lists whatever profiles Chrome itself knows about (under `~/Library/Application Support/Google/Chrome/`), showing the account name/email when Chrome has one on file.

## Firefox

- `browserProfile`: the profile's **name**, which isn't always the same as its folder name — find yours via **Manage Profiles**, or Firefox's own `about:profiles` page.
- Profile discovery reads names the way Firefox itself does. If a profile doesn't show a friendly name, it was probably created manually rather than through Firefox's own profile manager — its raw folder name is shown instead, and that's still fine to use as-is.

## Opera

- `browserProfile`: the **full path** to the profile directory (not just a name — this is different from Chrome and Firefox). Find it via **Manage Profiles**.
- Profile discovery lists Opera's own profile folders. If a profile you know exists doesn't show up, make sure you've actually opened a tab in it at least once — an unused profile folder isn't detected yet.

## Safari

- `browserProfile` is accepted (so the same config shape works everywhere) but ignored — Safari has no way to select a profile from outside the app. Links always open in whatever Safari window is currently active.
- Not listed in **Manage Profiles**, since there's nothing to detect.

## Apps other than a browser

Use the `"app"` profile type with just an app name (and, if more than one app shares that name, a full path to disambiguate). No profile support — it's a plain "open this app" launch.

## Scripts / custom commands

Use the `"executable"` profile type to run any command instead of opening a browser — see the README's "Script/Executable Profile" section for the format and the `${url}`/`${sourceApp}` placeholders.

## Browsers not listed above (Brave, Edge, Vivaldi, Opera GX, ...)

Not built in, but you can add any of them yourself with the `"executable"` profile type, since it can run any command line. The pattern:

- **With a profile:** `open -na "<App Name>" --args --profile-directory=<name> ${url}` for Brave/Edge/Vivaldi, or `open -na "<App Name>" --args --user-data-dir=<full path> ${url}` for Opera GX.
- **No profile:** `open -a "<App Name>" ${url}`

Example, adding two Brave profiles:

```json
{
  "profiles": {
    "brave_work": {
      "executable": "open -na \"Brave Browser\" --args --profile-directory=\"Profile 1\" ${url}"
    },
    "brave_personal": {
      "executable": "open -na \"Brave Browser\" --args --profile-directory=\"Default\" ${url}"
    }
  }
}
```

Starting points for a few common ones — double-check against your own install before relying on these, since none have been tested here:

| Browser | App name | Profile flag | Profile directory |
|---|---|---|---|
| Brave | `Brave Browser` | `--profile-directory=<name>` | `~/Library/Application Support/BraveSoftware/Brave-Browser/` |
| Microsoft Edge | `Microsoft Edge` | `--profile-directory=<name>` | `~/Library/Application Support/Microsoft Edge/` |
| Vivaldi | `Vivaldi` | `--profile-directory=<name>` | `~/Library/Application Support/Vivaldi/` |
| Opera GX | `Opera GX` | `--user-data-dir=<full path>` | `~/Library/Application Support/com.operasoftware.OperaGX/` |

To find your actual profile names, open the browser and check its own version/about page (e.g. `brave://version`, `edge://version`, `vivaldi://about`) for the "Profile Path," or look inside the profile directory listed above.

If Edge's profile switching doesn't seem to work, that's a known quirk on macOS reported by other users, not something specific to this setup.
