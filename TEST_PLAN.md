# URLBouncer v2 Manual Testing Checklist

## Phase 1-2: Config & Openers

### Config Parsing ✅
- [x] v2 config format (ProfileTarget enum) parses correctly
- [x] All four profile types (browser/app/executable/app+path) parse
- [x] alertOnError field recognized
- [ ] Backwards compatibility: Can v1 config still work? (TBD - need to test)

### Browser Openers
- [ ] Chrome with profile: Opens correct profile
- [ ] Chrome without profile: Opens Chrome (any window)
- [ ] Firefox with profile: Opens Firefox with `-P ProfileName`
- [ ] Firefox without profile: Opens Firefox (default)
- [ ] Safari (profile ignored): Opens Safari
- [ ] Opera with profile: Opens with `--user-data-dir=/path`
- [ ] Opera without profile: Opens Opera

### App Launcher
- [ ] App by name: `open -a AppName URL` works
- [ ] App by path: Opens `/path/to/App.app` with URL
- [ ] Error handling: Missing app shows alert + logs

### Script Executor
- [ ] Script with ${url} substitution works
- [ ] Script with ${sourceApp} substitution works
- [ ] Script with alertOnError: true shows alert on error
- [ ] Script with alertOnError: false/missing logs but no alert
- [ ] Exit code captured and logged
- [ ] Output/stderr captured and logged

### Error Handling
- [ ] Missing Chrome: Alert + Log
- [ ] Missing Firefox: Alert + Log
- [ ] Missing Safari: Alert + Log
- [ ] Missing Opera: Alert + Log
- [ ] Invalid URL: Alert + Log

### Logging
- [ ] URL logging disabled: URLs not logged
- [ ] URL logging enabled: URLs logged
- [ ] Errors logged regardless of URL logging setting
- [ ] URL redacted in error messages unless URL logging enabled

## Phase 3: Profile Discovery

### Chrome Profiles
- [ ] listChromeProfiles() finds all profiles
- [ ] Profile info extracted: dir, name, email

### Firefox Profiles
- [ ] listFirefoxProfiles() finds all profiles
- [ ] Profile info extracted: dir, name

### Opera Profiles
- [ ] listOperaProfiles() finds all profiles
- [ ] Profile info extracted: path, name

### Manage Profiles Popup
- [ ] Popup displays all three browsers' profiles
- [ ] Formatting is clear and aligned
- [ ] Browser sections clearly separated
- [ ] "Copy Profiles Block" button present
- [ ] Copy button generates valid JSON
- [ ] Copy button copies to clipboard
- [ ] "Copied!" confirmation alert shown

## Phase 4: Menu & URL Handlers

### Menu Item
- [ ] "Manage Profiles" item renamed from "Chrome Profiles"
- [ ] Clicking opens new popup

### URL Routing
- [ ] URL matched to rule → correct ProfileTarget selected
- [ ] No rule matched → default profile used
- [ ] Profile name resolved to ProfileTarget correctly

### URL Event Handlers
- [ ] handleGetURL opens correct profile
- [ ] application(_:openFile:) opens correct profile

## Phase 5: Documentation

- [ ] config.json example updated to v2 format
- [ ] README.md documents all new profile types
- [ ] README explains profile discovery
- [ ] README explains script substitution
- [ ] Example rules cover all profile types

## Overall

- [ ] App builds without errors
- [ ] App launches without crashing
- [ ] All features can be tested in isolation
