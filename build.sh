#!/bin/bash
set -e

# Define directories
BUILD_DIR="build"
APP_NAME="ScreenHighlighter"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
MACOS_DIR="${APP_BUNDLE}/Contents/MacOS"
RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"

echo "=== Building Screen Highlighter in Release Mode ==="
# Compile using SPM
swift build -c release

echo "=== Packaging Application Bundle ==="
# Recreate app bundle directories
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Find binary path
BINARY_PATH=".build/release/${APP_NAME}"
if [ ! -f "${BINARY_PATH}" ]; then
    echo "Error: Binary not found at ${BINARY_PATH}"
    exit 1
fi

# Copy binary and configuration
cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Set executable permissions
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "=== Successfully built: ${APP_BUNDLE} ==="
echo "To run the app, you can launch it using:"
echo "open ${APP_BUNDLE}"
