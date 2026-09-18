# URLBouncer v2 Manual Testing Guide

**Automated Testing Status**: ✅ All automated checks passed
- Build: Clean compilation ✓
- Config parsing: v2 format with all 4 profile types ✓
- Profile discovery: Chrome, Firefox profiles detected ✓
- Script execution: Parameter substitution working ✓
- URL pattern matching: Hostname extraction correct ✓
- Logging infrastructure: File creation and writing ✓

**Manual Testing Required**: UI interactions, browser/app launching, real-world routing

---

## Setup

### 1. Prepare a Test Config

Create `~/.config/urlbouncer/config.json`:

```json
{
  "profiles": {
    "work_chrome": {
      "browser": "chrome",
      "browserProfile": "Default"
    },
    "firefox_test": {
      "browser": "firefox",
      "browserProfile": "6xj08e6k.default"
    },
    "safari_default": {
      "browser": "safari"
    },
    "test_script": {
      "executable": "/tmp/urlbouncer_test/test_handler.sh ${url} ${sourceApp}",
      "alertOnError": false
    }
  },
  "rules": [
    {"match": "github.com", "profile": "work_chrome"},
    {"match": "youtube.com", "profile": "firefox_test"},
    {"match": "example.com", "profile": "test_script"},
    {"match": "docs.google.com", "sourceApp": "Slack", "profile": "work_chrome"},
    {"sourceApp": "Mail", "profile": "safari_default"}
  ],
  "defaultProfile": "safari_default"
}
```

### 2. Create a Test Script

```bash
mkdir -p /tmp/urlbouncer_test
cat > /tmp/urlbouncer_test/test_handler.sh << 'SCRIPT'
#!/bin/bash
URL="$1"
SOURCE_APP="$2"

echo "[$(date)] Script called with URL=$URL, SOURCE_APP=$SOURCE_APP" >> /tmp/urlbouncer_test/script.log
# Add any custom logic here

exit 0
SCRIPT
chmod +x /tmp/urlbouncer_test/test_handler.sh
```

### 3. Launch URLBouncer

```bash
make install
# Then open /Applications/URLBouncer.app or click the menu bar icon
```

---

## Test Cases

### Test 1: Menu Bar UI

- [ ] **Menu appears** in top-right corner
- [ ] **Click menu icon** → dropdown shows options:
  - [ ] Set as Default Browser
  - [ ] Open Config
  - [ ] Reload Config
  - [ ] Manage Profiles
  - [ ] Show Log
  - [ ] Log URLs (unchecked initially)
  - [ ] Quit URLBouncer

### Test 2: Config Management

- [ ] **Click "Open Config"** → config.json opens in text editor
- [ ] **Edit config** (e.g., add a new profile), save
- [ ] **Click "Reload Config"** → alert shows updated rule count (should match your config)
- [ ] Close and reopen menu → config changes persist

### Test 3: Manage Profiles Dialog

- [ ] **Click "Manage Profiles"** → popup appears
- [ ] **Dialog shows:**
  - [ ] Chrome profiles (should list "Default")
  - [ ] Firefox profiles (should list at least one)
  - [ ] Opera profiles (empty if Opera not installed)
- [ ] **"Copy Profiles Block" button** → copies JSON to clipboard:
  ```
  "profiles": {
    "chrome_default": {"browser": "chrome"},
    "firefox_6xj08e6k": {"browser": "firefox", "browserProfile": "6xj08e6k.default"},
    ...
  }
  ```
- [ ] Paste into a text editor and verify JSON syntax

### Test 4: Test Direct URL Sending (No Default Browser)

Before setting URLBouncer as default, test it with explicit Apple Event:

```bash
osascript -e 'tell application "URLBouncer" to open location "https://github.com"'
osascript -e 'tell application "URLBouncer" to open location "https://youtube.com"'
osascript -e 'tell application "URLBouncer" to open location "https://example.com"'
```

- [ ] **github.com** → Opens in Chrome
- [ ] **youtube.com** → Opens in Firefox
- [ ] **example.com** → Test script runs (check `/tmp/urlbouncer_test/script.log`)

### Test 5: Browser Routing

- [ ] **Test Chrome with profile:**
  - Run: `osascript -e 'tell application "URLBouncer" to open location "https://github.com/user/repo"'`
  - Chrome should open (verify it's using "Default" profile by checking open windows)

- [ ] **Test Firefox routing:**
  - Run: `osascript -e 'tell application "URLBouncer" to open location "https://youtube.com/watch?v=123"'`
  - Firefox should open (verify by watching window activate)

- [ ] **Test Safari (default profile):**
  - Edit config: change defaultProfile to `"safari_default"`
  - Run: `osascript -e 'tell application "URLBouncer" to open location "https://nonmatch.test"'`
  - Safari should open

### Test 6: URL Pattern Matching

Test different pattern types:

- [ ] **Hostname matching:** `github.com` matches github.com/anything
- [ ] **Path matching:** Add rule with pattern `"docs.google.com/presentation"` (with slash)
  - Should match `docs.google.com/presentation/d/123`
  - Should NOT match `docs.google.com/document/d/456`
- [ ] **Regex matching:** Add rule with pattern `"re:.*\\.edu$"` (URLs from .edu domains)
  - Run: `osascript -e 'tell application "URLBouncer" to open location "https://stanford.edu"'`
  - Should match the regex rule

### Test 7: Source App Filtering

- [ ] **Open a URL from Mail:**
  ```bash
  # Mail normally opens http:// links, but we can test with a rule like:
  # {"match": "example.com", "sourceApp": "Mail", "profile": "work_chrome"}
  osascript -e 'tell application "Mail" to activate'
  # Then Command+Click a link in an email, or simulate with:
  osascript -e 'tell application "URLBouncer" to open location "https://example.com"'
  ```
  - Should route according to sourceApp rule

### Test 8: Script Execution with Parameters

- [ ] **Run:** `osascript -e 'tell application "URLBouncer" to open location "https://example.com?test=123"'`
- [ ] **Check log:** `tail -5 /tmp/urlbouncer_test/script.log`
- [ ] **Verify output:** Should show:
  ```
  [2026-04-28 ...] Script called with URL=https://example.com?test=123, SOURCE_APP=URLBouncer
  ```
- [ ] **Test with alertOnError:**
  - Modify test script to `exit 1` (failure)
  - Modify config: set `"alertOnError": true`
  - Run URL → alert should appear with error message

### Test 9: Default Profile Fallback

- [ ] **Set defaultProfile** to `"safari_default"` in config
- [ ] **Click "Reload Config"**
- [ ] **Test non-matching URL:** Run `osascript -e 'tell application "URLBouncer" to open location "https://randomsite123.test"'`
- [ ] **Result:** Should open in Safari (the default profile)

### Test 10: Logging

#### Enable URL Logging

- [ ] **Click menu → Log URLs** (should show checkmark)
- [ ] **Click menu → Show Log** → Console.app opens
- [ ] **Filter:** Type "URLBouncer" in search
- [ ] **Run a URL:** `osascript -e 'tell application "URLBouncer" to open location "https://github.com"'`
- [ ] **Verify logs** show:
  ```
  URL received: https://github.com
  Rule 'github.com' matched https://github.com → work_chrome
  ```

#### Disable URL Logging

- [ ] **Click menu → Log URLs** (checkmark should disappear)
- [ ] **Run another URL**
- [ ] **Verify logs** no longer show the sensitive URL (should only log the routing decision)

### Test 11: Error Handling

- [ ] **Modify config:** Add a profile that opens a non-existent app:
  ```json
  "broken_app": {"app": "NonExistentApp"}
  ```
- [ ] **Route a URL to it:** `osascript -e 'tell application "URLBouncer" to open location "https://broken.test"'`
- [ ] **Expected:** Alert appears with error message, log shows the failure

### Test 12: Set as Default Browser

Once satisfied with manual tests:

- [ ] **Click menu → Set as Default Browser**
- [ ] **Test with actual browser links:**
  - Click a link in Mail, Slack, or web content
  - Should route through URLBouncer to the correct target
- [ ] **Verify System Preferences:**
  - System Preferences → General → Default web browser → Should show "URLBouncer"

### Test 13: Quit and Restart

- [ ] **Click menu → Quit URLBouncer**
- [ ] **Close all browsers** (or note which are open)
- [ ] **Click a link** from Mail or another app
- [ ] **URLBouncer should auto-launch** and route the URL (if set as default)
- [ ] **Check menu → Reload Config** → should still show correct profile count

### Test 14: Config Reload (No Restart)

- [ ] **Edit** `~/.config/urlbouncer/config.json` (add a new rule)
- [ ] **Click menu → Reload Config** → alert confirms updated count
- [ ] **Test the new rule** → should work without restarting URLBouncer
- [ ] Verify this works multiple times

---

## Regression Tests

After all features pass:

### Core Functionality

- [ ] **App launches** without crashing on startup
- [ ] **Menu bar icon** is always visible
- [ ] **Clicking icon** opens menu reliably
- [ ] **Closing menu** doesn't crash app (click elsewhere)
- [ ] **Multiple config reloads** work without memory leaks

### Browser Compatibility

- [ ] **Chrome** launches and loads URL
- [ ] **Firefox** launches and loads URL
- [ ] **Safari** launches and loads URL
- [ ] **Multiple browser launches** in sequence work correctly

### Edge Cases

- [ ] **Empty URL** passed to URLBouncer → logged, no crash
- [ ] **Malformed config JSON** → error alert, app continues
- [ ] **Very long URLs** (1000+ chars) → handled correctly
- [ ] **Unicode in URLs** → encoded correctly, not mangled
- [ ] **URL with special characters** (`&`, `?`, `#`, etc.) → passed correctly to opener
- [ ] **Script not found** in executable profile → alert with error details

---

## Sign-Off

When all tests pass:

```bash
# Verify app is code-signed
codesign -vv /Applications/URLBouncer.app

# Check for any lingering issues
make clean && make all
```

**Tests Completed By:** _______________  
**Date:** _______________  
**Notes:** _______________  

---

## Quick Debug Commands

If you encounter issues:

```bash
# View full log
tail -100 ~/Library/Logs/URLBouncer/urlbouncer.log

# Check if URLBouncer is running
ps aux | grep URLBouncer

# View active application
log show --predicate 'eventMessage contains "URLBouncer"' --last 1h

# Test direct invocation
osascript -e 'tell application "URLBouncer" to open location "https://test.com"'

# Verify config syntax
plutil -lint ~/.config/urlbouncer/config.json

# Check if set as default browser
duti -q http
```
