#!/bin/bash
# build.sh — Compile StatusBarApp into a macOS .app bundle
#
# Usage:
#   chmod +x build.sh
#   ./build.sh                           # Dev build (arm64 only, fast)
#   ./build.sh --release                 # Universal binary (arm64 + x86_64) + ZIP
#   ./build.sh --release --version v1.0  # Release build with version injected
#   ./build.sh --sparkle                 # Build with Sparkle auto-update framework
#
# Environment variables:
#   CODESIGN_IDENTITY  — Developer ID for signing (omit for ad-hoc)
#   NOTARIZE_PROFILE   — Keychain profile for notarytool (requires CODESIGN_IDENTITY)
#
# After building, the app will be at ./build/StatusBar.app
# You can double-click it or run: open ./build/StatusBar.app

set -euo pipefail

APP_NAME="StatusBar"
BUILD_DIR="./build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

RELEASE=false
VERSION=""
SPARKLE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            RELEASE=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --sparkle)
            SPARKLE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "🔨 Building ${APP_NAME}..."

# Clean
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

SWIFT_FLAGS=(
    Sources/*.swift
    -parse-as-library
    -framework SwiftUI
    -framework AppKit
    -framework UserNotifications
    -framework Carbon
    -O
)

# Sparkle auto-update framework (optional)
if [ "$SPARKLE" = true ] && [ -d "Vendor/Sparkle.framework" ]; then
    echo "  Including Sparkle.framework..."
    SWIFT_FLAGS+=(-F Vendor -framework Sparkle)
    SWIFT_FLAGS+=(-Xlinker -rpath -Xlinker @executable_path/../Frameworks)
fi

if [ "$RELEASE" = true ]; then
    echo "📦 Release build (universal binary)..."

    # Compile arm64
    echo "  Compiling arm64..."
    swiftc "${SWIFT_FLAGS[@]}" \
        -target arm64-apple-macosx14.0 \
        -o "${BUILD_DIR}/${APP_NAME}-arm64"

    # Compile x86_64
    echo "  Compiling x86_64..."
    swiftc "${SWIFT_FLAGS[@]}" \
        -target x86_64-apple-macosx14.0 \
        -o "${BUILD_DIR}/${APP_NAME}-x86_64"

    # Merge into universal binary
    echo "  Creating universal binary..."
    lipo -create \
        "${BUILD_DIR}/${APP_NAME}-arm64" \
        "${BUILD_DIR}/${APP_NAME}-x86_64" \
        -output "${MACOS}/${APP_NAME}"

    # Clean up arch-specific binaries
    rm "${BUILD_DIR}/${APP_NAME}-arm64" "${BUILD_DIR}/${APP_NAME}-x86_64"
else
    # Dev build — arm64 only (fast)
    swiftc "${SWIFT_FLAGS[@]}" \
        -target arm64-apple-macosx14.0 \
        -o "${MACOS}/${APP_NAME}"
fi

# Copy Info.plist
cp Info.plist "${CONTENTS}/Info.plist"

# Determine version: explicit --version flag > latest git tag > Info.plist default
if [ -z "$VERSION" ]; then
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null || true)
fi

# Inject version into the copied Info.plist (source file untouched)
if [ -n "$VERSION" ]; then
    # Strip leading 'v' if present (v1.0.0 → 1.0.0)
    CLEAN_VERSION="${VERSION#v}"
    echo "  Setting version to ${CLEAN_VERSION}..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${CLEAN_VERSION}" "${CONTENTS}/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${CLEAN_VERSION}" "${CONTENTS}/Info.plist"
fi

# Copy app icon if it exists
if [ -f "${APP_NAME}.icns" ]; then
    cp "${APP_NAME}.icns" "${RESOURCES}/"
fi

# Copy bundled images
for img in *.png; do
    [ -f "$img" ] && [ "$img" != "icon.png" ] && cp "$img" "${RESOURCES}/"
done

# Copy Sparkle.framework into the app bundle if enabled
if [ "$SPARKLE" = true ] && [ -d "Vendor/Sparkle.framework" ]; then
    mkdir -p "${CONTENTS}/Frameworks"
    cp -R Vendor/Sparkle.framework "${CONTENTS}/Frameworks/"
fi

# Code signing
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "🔏 Signing with identity: ${CODESIGN_IDENTITY}..."

    # Sign embedded frameworks first
    if [ -d "${CONTENTS}/Frameworks/Sparkle.framework" ]; then
        codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp \
            "${CONTENTS}/Frameworks/Sparkle.framework"
    fi

    codesign --force --sign "$CODESIGN_IDENTITY" --options runtime \
        --entitlements StatusBar.entitlements --timestamp "${APP_BUNDLE}"
else
    # Ad-hoc signing (local development)
    codesign --force --sign - --entitlements StatusBar.entitlements "${APP_BUNDLE}"
fi

echo "✅ Built successfully: ${APP_BUNDLE}"

if [ "$RELEASE" = true ]; then
    lipo -info "${MACOS}/${APP_NAME}"

    # Create ZIP preserving macOS extended attributes and code signatures
    ZIP_NAME="${APP_NAME}-${VERSION:-universal}.zip"
    echo "📦 Creating ${ZIP_NAME}..."
    ditto -c -k --keepParent "${APP_BUNDLE}" "${BUILD_DIR}/${ZIP_NAME}"
    echo "✅ Archive: ${BUILD_DIR}/${ZIP_NAME}"

    # Notarize if profile is configured
    if [ -n "${CODESIGN_IDENTITY:-}" ] && [ -n "${NOTARIZE_PROFILE:-}" ]; then
        echo "📋 Notarizing..."
        xcrun notarytool submit "${BUILD_DIR}/${ZIP_NAME}" \
            --keychain-profile "$NOTARIZE_PROFILE" --wait
        xcrun stapler staple "${APP_BUNDLE}"
        # Re-create ZIP with stapled app
        rm "${BUILD_DIR}/${ZIP_NAME}"
        ditto -c -k --keepParent "${APP_BUNDLE}" "${BUILD_DIR}/${ZIP_NAME}"
        echo "✅ Notarized and stapled"
    fi
else
    echo ""
    echo "Run with:  open ${APP_BUNDLE}"
    echo "Or:        ${MACOS}/${APP_NAME}"
fi
