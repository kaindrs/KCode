#!/usr/bin/env bash
set -euo pipefail

# KCode macOS app builder
# Wraps a Kimi Code web instance into a native macOS .app using Nativefier.
#
# Configuration (all optional except URL when not using the default):
#   KCODE_URL        Base URL of the Kimi Code web interface (default: http://127.0.0.1:58627)
#   KCODE_TOKEN      Access token appended as a URL fragment (default: empty)
#   KCODE_NAME       App display name (default: KCode)
#   KCODE_BUNDLE_ID  macOS bundle identifier (default: ai.kimi.code.kmac)
#   KCODE_ICON       Path to a 1024x1024 PNG/SVG icon (default: ./assets/icon.png)
#   KCODE_OUTPUT     Where to place the built .app (default: ./build)
#   KCODE_ARCH       Target architecture: arm64, x64, or universal (default: arm64)
#   KCODE_INSTALL    Set to "1" to also copy the app to ~/Applications

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KCODE_URL="${KCODE_URL:-http://127.0.0.1:58627}"
KCODE_TOKEN="${KCODE_TOKEN:-}"
KCODE_NAME="${KCODE_NAME:-KCode}"
KCODE_BUNDLE_ID="${KCODE_BUNDLE_ID:-ai.kimi.code.kmac}"
KCODE_ICON="${KCODE_ICON:-${PROJECT_ROOT}/assets/icon.png}"
KCODE_OUTPUT="${KCODE_OUTPUT:-${PROJECT_ROOT}/build}"
KCODE_ARCH="${KCODE_ARCH:-arm64}"
KCODE_INSTALL="${KCODE_INSTALL:-0}"

BUILD_DIR="${KCODE_OUTPUT}/.nativefier"
APP_BUNDLE="${KCODE_OUTPUT}/${KCODE_NAME}.app"

die() {
    echo "Error: $1" >&2
    exit 1
}

log() {
    echo "[KCode] $1"
}

# Validate platform
if [[ "$(uname -s)" != "Darwin" ]]; then
    die "This script must run on macOS."
fi

# Resolve target URL
TARGET_URL="${KCODE_URL}"
if [[ -n "${KCODE_TOKEN}" ]]; then
    TARGET_URL="${TARGET_URL}#token=${KCODE_TOKEN}"
fi

log "Building ${KCODE_NAME}.app"
log "  URL:        ${KCODE_URL}"
log "  Token:      $([[ -n ${KCODE_TOKEN} ]] && echo "set (hidden)" || echo "not set")"
log "  Bundle ID:  ${KCODE_BUNDLE_ID}"
log "  Icon:       ${KCODE_ICON}"
log "  Arch:       ${KCODE_ARCH}"
log "  Output:     ${KCODE_OUTPUT}"

# Ensure Node.js is available
if ! command -v node >/dev/null 2>&1; then
    die "Node.js is required but not found. Install it from https://nodejs.org/"
fi

# Ensure Nativefier is available (local or global)
NATIVIER_CMD=""
if command -v nativefier >/dev/null 2>&1; then
    NATIVIER_CMD="nativefier"
elif [[ -x "${PROJECT_ROOT}/node_modules/.bin/nativefier" ]]; then
    NATIVIER_CMD="${PROJECT_ROOT}/node_modules/.bin/nativefier"
else
    log "Nativefier not found. Installing local copy..."
    (cd "${PROJECT_ROOT}" && npm install)
    NATIVIER_CMD="${PROJECT_ROOT}/node_modules/.bin/nativefier"
fi

# Validate icon
if [[ ! -f "${KCODE_ICON}" ]]; then
    die "Icon not found: ${KCODE_ICON}"
fi

# Clean previous build
log "Cleaning previous build..."
rm -rf "${BUILD_DIR}" "${APP_BUNDLE}"
mkdir -p "${BUILD_DIR}" "${KCODE_OUTPUT}"

# Run Nativefier
log "Running Nativefier..."
"${NATIVIER_CMD}" \
    "${TARGET_URL}" \
    "${BUILD_DIR}" \
    --name "${KCODE_NAME}" \
    --icon "${KCODE_ICON}" \
    --platform osx \
    --arch "${KCODE_ARCH}" \
    --width 1400 \
    --height 900 \
    --show-menu-bar \
    --single-instance \
    --counter \
    --bounce \
    --internal-urls ".*"

# Locate generated app
GENERATED_APP=$(find "${BUILD_DIR}" -maxdepth 2 -name "${KCODE_NAME}.app" -type d | head -n 1)
if [[ -z "${GENERATED_APP}" ]]; then
    die "Nativefier did not produce ${KCODE_NAME}.app"
fi

# Fix main bundle ID
log "Setting bundle identifier to ${KCODE_BUNDLE_ID}..."
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${KCODE_BUNDLE_ID}" \
    "${GENERATED_APP}/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${KCODE_BUNDLE_ID}" \
        "${GENERATED_APP}/Contents/Info.plist"

# Fix helper bundle IDs
while IFS= read -r helper_plist; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${KCODE_BUNDLE_ID}.helper" \
        "${helper_plist}" 2>/dev/null || true
done < <(find "${GENERATED_APP}/Contents/Frameworks" -path "*Helper*.app/Contents/Info.plist" 2>/dev/null)

# Ad-hoc sign the app
log "Code signing app..."
codesign --sign - --force --deep "${GENERATED_APP}" >/dev/null

# Verify signature
if ! codesign --verify --deep --strict "${GENERATED_APP}" >/dev/null 2>&1; then
    die "Code signing verification failed"
fi

# Move to output directory
log "Moving app to ${APP_BUNDLE}..."
mv "${GENERATED_APP}" "${APP_BUNDLE}"

# Optional install to ~/Applications
if [[ "${KCODE_INSTALL}" == "1" ]]; then
    log "Installing to ~/Applications..."
    rm -rf "${HOME}/Applications/${KCODE_NAME}.app"
    cp -R "${APP_BUNDLE}" "${HOME}/Applications/${KCODE_NAME}.app"
fi

# Clean temporary Nativefier directory
rm -rf "${BUILD_DIR}"

log "Build complete: ${APP_BUNDLE}"
log "Bundle ID: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_BUNDLE}/Contents/Info.plist")"

if [[ "${KCODE_INSTALL}" != "1" ]]; then
    log "Run with KCODE_INSTALL=1 to copy the app to ~/Applications automatically."
fi
