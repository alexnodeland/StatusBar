# Makefile `install` Target Signing Fix — Recovery Notes

## Problem

The `install` target copies the unsigned build to `/Applications/` without codesigning. This causes the widget extension to not be discovered by macOS (widgets require sandbox entitlements, which need signing).

## Broken Version (current on `main`)

```makefile
install: build ## Build and copy .app to /Applications
	@cp -R $(DERIVED_DATA)/Build/Products/Debug/StatusBar.app /Applications/
	@echo "Installed to /Applications/StatusBar.app"
```

## Fixed Version

```makefile
install: build ## Build, sign, and copy .app to /Applications
	@codesign --force --sign "Apple Development" \
		$(DERIVED_DATA)/Build/Products/Debug/StatusBar.app/Contents/PlugIns/StatusBarWidget.appex 2>/dev/null || \
		codesign --force --sign - \
		$(DERIVED_DATA)/Build/Products/Debug/StatusBar.app/Contents/PlugIns/StatusBarWidget.appex
	@codesign --force --sign "Apple Development" \
		$(DERIVED_DATA)/Build/Products/Debug/StatusBar.app 2>/dev/null || \
		codesign --force --sign - \
		$(DERIVED_DATA)/Build/Products/Debug/StatusBar.app
	@cp -R $(DERIVED_DATA)/Build/Products/Debug/StatusBar.app /Applications/
	@echo "Installed to /Applications/StatusBar.app"
```

## Key Details

- Signs the widget extension **first**, then the main app (inside-out signing order)
- Tries `Apple Development` certificate first, falls back to ad-hoc (`-`) if no cert available
- Matches the signing approach used by `make dev`
- Without signing, `/Applications/StatusBar.app` has `Signature=adhoc, TeamIdentifier=not set` and widgets don't appear in the gallery
