# Widget Debugging — Recovery Notes

## Widget Recovery Procedure

When widgets disappear or show stale data:

1. Delete `/Applications/StatusBar.app` (stale unsigned copy from `make install`)
2. Kill any lingering StatusBar processes: `killall StatusBar`
3. `make clean` — wipe DerivedData for full rebuild
4. `make dev` — fresh build, codesign, launch
5. Wait ~10 seconds for `chronod` to discover the new widget extension
6. Open widget gallery to verify widgets appear
7. If widgets still missing: `killall NotificationCenter` then recheck

## Safe vs Unsafe Operations

| Operation | Safe? | Notes |
|-----------|-------|-------|
| `killall NotificationCenter` | SAFE | Restarts NC UI, forces widget gallery refresh |
| `killall chronod` | DANGEROUS | Widget scheduling daemon. Killing breaks widget discovery |
| Delete `/Applications/StatusBar.app` | SAFE | Removes stale copy |
| `make clean` | SAFE | Wipes project DerivedData |

## Multiple App Copies Problem

A common confusion during debugging: macOS may load widget extensions from the **wrong** app copy. Discovered scenario:

- `/Applications/StatusBar.app` (from `make install`) — stale, unsigned
- Xcode's DerivedData: `~/Library/Developer/Xcode/DerivedData/StatusBar-<hash>/...` — old cached build

macOS loaded the widget from Xcode's DerivedData, not the project's DerivedData. **Solution:** remove all stale copies, only use `make dev`.

Check for multiple copies:
```bash
# Find all StatusBar.app instances
mdfind "kMDItemFSName == 'StatusBar.app'"

# Find running StatusBar processes
pgrep -la StatusBar
```

## macOS Widget Caching Behavior

- macOS **aggressively caches** widget metadata
- After switching from `StaticConfiguration` to `AppIntentConfiguration`, macOS kept showing old widget description text
- Stale copies in `/Applications/` and Xcode's DerivedData take precedence over project DerivedData builds
- Must remove widgets from desktop and re-add when switching configuration types
- AppIntents metadata stored in: `StatusBarWidget.appex/Contents/Resources/Metadata.appintents/extract.actionsdata`

## Signing Requirements for Widget Discovery

- Widget extensions **MUST** be sandboxed to appear in the widget gallery
- `make build` uses ad-hoc signing (`CODE_SIGN_IDENTITY=-`) — no real signing
- `make dev` adds post-build codesigning with `Apple Development` certificate (falls back to ad-hoc)
- `make install` (broken) had NO codesigning — just `build` + `cp`
- `ENABLE_APP_SANDBOX=YES` in `project.yml` controls sandboxing
- In Xcode 15+, `ENABLE_APP_SANDBOX=YES` can embed the sandbox entitlement at **link time** rather than at signing time — this may explain why widgets work even with `CODE_SIGNING_ALLOWED=NO`

## Entitlements Notes

- `StatusBarWidget.debug.entitlements` has `com.apple.security.application-groups` but NOT `com.apple.security.app-sandbox`
- Sandbox is controlled by `ENABLE_APP_SANDBOX: YES` build setting, not the entitlements file
- Post-build `codesign --force --sign "Apple Development"` **without** `--entitlements` flag may strip previously embedded entitlements — be careful
