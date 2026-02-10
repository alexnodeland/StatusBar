#!/bin/bash
# test.sh — Build and run unit tests for StatusBar
#
# Compiles all Sources/*.swift (except StatusBarApp.swift) + Tests/*.swift
# as a test bundle, then runs via xctest.
#
# Usage:
#   chmod +x test.sh
#   ./test.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/.build-tests"
BUNDLE_NAME="StatusBarTests.xctest"
BUNDLE_DIR="${BUILD_DIR}/${BUNDLE_NAME}"
BUNDLE_EXEC="${BUNDLE_DIR}/Contents/MacOS/StatusBarTests"
FIXTURES_DIR="${PROJECT_DIR}/Tests/Fixtures"

echo "🧪 Building StatusBar tests..."

# Clean
rm -rf "${BUILD_DIR}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"

# Collect source files (exclude StatusBarApp.swift which has @main,
# and HotkeyManager.swift which requires Carbon event loop at runtime)
SOURCE_FILES=()
for f in "${PROJECT_DIR}"/Sources/*.swift; do
    case "$(basename "$f")" in
        StatusBarApp.swift|HotkeyManager.swift) continue ;;
        *) SOURCE_FILES+=("$f") ;;
    esac
done

# Collect test files
TEST_FILES=("${PROJECT_DIR}"/Tests/*.swift)

# Find Xcode paths
XCODE_DEV="$(xcode-select -p)"
PLATFORM_DIR="${XCODE_DEV}/Platforms/MacOSX.platform/Developer"
SDK_PATH="$(xcrun --show-sdk-path)"

# Compile as test bundle
swiftc \
    "${SOURCE_FILES[@]}" \
    "${TEST_FILES[@]}" \
    -framework SwiftUI \
    -framework AppKit \
    -framework UserNotifications \
    -framework XCTest \
    -F "${PLATFORM_DIR}/Library/Frameworks" \
    -I "${PLATFORM_DIR}/usr/lib" \
    -L "${PLATFORM_DIR}/usr/lib" \
    -sdk "${SDK_PATH}" \
    -target arm64-apple-macosx26.0 \
    -emit-executable \
    -o "${BUNDLE_EXEC}" \
    -Xlinker -bundle \
    -Xlinker -rpath -Xlinker "${PLATFORM_DIR}/Library/Frameworks"

echo "✅ Compiled successfully"
echo ""
echo "🏃 Running tests..."
echo ""

# Run tests with xctest
export FIXTURES_DIR
if xcrun xctest "${BUNDLE_DIR}"; then
    echo ""
    echo "✅ All tests passed!"
    EXIT_CODE=0
else
    echo ""
    echo "❌ Some tests failed."
    EXIT_CODE=1
fi

# Clean up
rm -rf "${BUILD_DIR}"

exit ${EXIT_CODE}
