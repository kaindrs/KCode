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
#   KCODE_INSTALL          Set to "1" to also copy the app to ~/Applications
#   KCODE_FROM_KIMI_WEB    Set to "1" to start `kimi web` and derive URL/token from its output
#   KCODE_KIMI_WEB_PORT    Port to use when starting `kimi web` (default: 58627)
#   KCODE_KIMI_WEB_TIMEOUT Seconds to wait for `kimi web` to print its Local URL (default: 30)

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
KCODE_FROM_KIMI_WEB="${KCODE_FROM_KIMI_WEB:-0}"
KCODE_KIMI_WEB_PORT="${KCODE_KIMI_WEB_PORT:-58627}"
KCODE_KIMI_WEB_TIMEOUT="${KCODE_KIMI_WEB_TIMEOUT:-30}"

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

# Start `kimi web` and parse its Local URL / token.
derive_from_kimi_web() {
    if ! command -v kimi >/dev/null 2>&1; then
        die "kimi CLI not found in PATH. Install it first: https://kimi-code.com/"
    fi

    # Check whether a Kimi server is already running on the chosen port.
    if curl -s "http://127.0.0.1:${KCODE_KIMI_WEB_PORT}/" >/dev/null 2>&1; then
        die "A Kimi server is already running on port ${KCODE_KIMI_WEB_PORT}. Stop it first so we can capture a fresh token."
    fi

    local logfile
    logfile="$(mktemp /tmp/kcode-kimi-web.XXXXXX)"
    log "Starting 'kimi web' on port ${KCODE_KIMI_WEB_PORT} to capture URL and token..."

    # Start `kimi web` in the background and redirect output to the log file.
    (kimi web --port "${KCODE_KIMI_WEB_PORT}" >"${logfile}" 2>&1) &
    local kimi_pid=$!

    # Wait for the "Local:" line.
    local elapsed=0
    local local_line=""
    while [[ ${elapsed} -lt ${KCODE_KIMI_WEB_TIMEOUT} ]]; do
        if [[ -f "${logfile}" ]]; then
            local_line="$(grep -E '^\s*Local:' "${logfile}" | head -n 1 || true)"
            if [[ -n "${local_line}" ]]; then
                break
            fi
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    if [[ -z "${local_line}" ]]; then
        # Clean up the background process if it never printed the URL.
        kill "${kimi_pid}" >/dev/null 2>&1 || true
        wait "${kimi_pid}" >/dev/null 2>&1 || true
        die "Timed out waiting for 'kimi web' to print its Local URL."
    fi

    # Extract URL and token from e.g.:
    # Local:    http://127.0.0.1:58627/#token=7d7j1A7efJxMMJK6ERsn-kbJwweEKSR12k3-xd1q1mI
    local raw_url
    raw_url="$(echo "${local_line}" | sed -E 's/^.*Local:[[:space:]]+//' | tr -d '[:space:]')"

    KCODE_URL="${raw_url%%#token=*}"
    if [[ "${raw_url}" == *"#token="* ]]; then
        KCODE_TOKEN="${raw_url##*#token=}"
    fi

    log "Derived URL and token from 'kimi web'. Server left running (PID ${kimi_pid})."
    log "  URL:   ${KCODE_URL}"
}

if [[ "${KCODE_FROM_KIMI_WEB}" == "1" ]]; then
    derive_from_kimi_web
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
