#!/usr/bin/env bash
set -euo pipefail

# KCode macOS app builder
# Wraps the Kimi Code web interface into a single native macOS .app bundle.
# The executable is a thin launcher that starts `kimi web` if it is not already
# running, captures its one-time Local URL (including the bearer token), rewrites
# the bundled Nativefier config, and then execs the real Electron binary.
#
# Because everything happens inside one app bundle, only one Dock icon appears.
#
# Configuration (all optional):
#   KCODE_NAME             App display name (default: KCode)
#   KCODE_BUNDLE_ID        macOS bundle identifier (default: ai.kimi.code.kmac)
#   KCODE_ICON             Path to a 1024x1024 PNG/SVG icon (default: ./assets/icon.png)
#   KCODE_OUTPUT           Where to place the built .app (default: ./build)
#   KCODE_ARCH             Target architecture: arm64, x64 (default: arm64)
#   KCODE_INSTALL          Set to "1" to also copy the app to ~/Applications
#   KCODE_KIMI_WEB_PORT    Port kimi web listens on (default: 58627)
#   KCODE_KIMI_WEB_TIMEOUT Seconds to wait for a fresh kimi web to print its URL (default: 30)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KCODE_NAME="${KCODE_NAME:-KCode}"
KCODE_BUNDLE_ID="${KCODE_BUNDLE_ID:-ai.kimi.code.kmac}"
KCODE_ICON="${KCODE_ICON:-${PROJECT_ROOT}/assets/icon.png}"
KCODE_OUTPUT="${KCODE_OUTPUT:-${PROJECT_ROOT}/build}"
KCODE_ARCH="${KCODE_ARCH:-arm64}"
KCODE_INSTALL="${KCODE_INSTALL:-0}"
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

log "Building ${KCODE_NAME}.app"
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

# Run Nativefier to build the webview app.
# The URL is only a placeholder; the launcher rewrites nativefier.json at runtime.
log "Running Nativefier..."
"${NATIVIER_CMD}" \
    "http://127.0.0.1:${KCODE_KIMI_WEB_PORT}/" \
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

# Ensure the bundle displays as "KCode" in the Dock / menu bar, regardless of
# the internal executable name.
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${KCODE_NAME}" \
    "${GENERATED_APP}/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ${KCODE_NAME}" \
        "${GENERATED_APP}/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleName ${KCODE_NAME}" \
    "${GENERATED_APP}/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleName string ${KCODE_NAME}" \
        "${GENERATED_APP}/Contents/Info.plist"

# Fix helper bundle IDs
while IFS= read -r helper_plist; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${KCODE_BUNDLE_ID}.helper" \
        "${helper_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${KCODE_NAME}" \
        "${helper_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleName ${KCODE_NAME}" \
        "${helper_plist}" 2>/dev/null || true
done < <(find "${GENERATED_APP}/Contents/Frameworks" -path "*Helper*.app/Contents/Info.plist" 2>/dev/null)

# Wrap the executable: rename the real binary and install a launcher script.
log "Installing runtime launcher wrapper..."
MACOS_DIR="${GENERATED_APP}/Contents/MacOS"
REAL_BIN="${MACOS_DIR}/${KCODE_NAME}"
WRAPPED_BIN="${MACOS_DIR}/${KCODE_NAME}.real"

if [[ ! -f "${REAL_BIN}" ]]; then
    die "Expected Nativefier executable not found: ${REAL_BIN}"
fi

mv "${REAL_BIN}" "${WRAPPED_BIN}"

# Write the launcher wrapper. It must be a POSIX-friendly shell script because
# it is the bundle's CFBundleExecutable.
cat > "${REAL_BIN}" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

# KCode launcher — starts `kimi web` if it is not already running, captures
# its one-time Local URL (including the bearer token), rewrites the bundled
# Nativefier config, and execs the real Electron binary.

KCODE_PORT="${KCODE_PORT:-58627}"
KCODE_TIMEOUT="${KCODE_TIMEOUT:-30}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESOURCES_DIR="${APP_ROOT}/Contents/Resources"
NATIVIER_JSON="${RESOURCES_DIR}/app/nativefier.json"
HOME_DIR="${HOME:-$(eval echo ~"$(whoami)")}"

log() {
    echo "[KCode] $1" >&2
}

die() {
    osascript -e "display alert \"KCode\" message \"$1\" as critical" >/dev/null 2>&1 || true
    echo "Error: $1" >&2
    exit 1
}

# Discover the coding-agent CLI: prefer upstream kimi, then AXIOM acode.
resolve_cli() {
    for bin in kimi acode; do
        if command -v "$bin" >/dev/null 2>&1; then
            echo "$bin"
            return 0
        fi
    done
    return 1
}

# Parse the Local URL line printed by `kimi web` / `acode web`:
#   Local:    http://127.0.0.1:58627/#token=...
parse_local_url() {
    local line="$1"
    line="$(echo "$line" | sed -E 's/^.*Local:[[:space:]]+//' | tr -d '[:space:]')"
    if [[ "$line" == http://* || "$line" == https://* ]]; then
        echo "$line"
    fi
}

# Resolve the Kimi Code config directory.
resolve_kimi_home() {
    if [[ -n "${KIMI_CODE_HOME:-}" ]]; then
        echo "${KIMI_CODE_HOME}"
    elif [[ -d "${HOME_DIR}/.kimi-code" ]]; then
        echo "${HOME_DIR}/.kimi-code"
    else
        echo "${HOME_DIR}/.config/kimi-code"
    fi
}

# Read the bearer token written by a running `kimi web` / `acode web` instance.
read_server_token() {
    local token_file="$(resolve_kimi_home)/server.token"
    if [[ -f "$token_file" ]]; then
        tr -d '[:space:]' < "$token_file"
    fi
}

# Ensure a server is running and we have a URL for it.
ensure_server() {
    # If a server is already responding, reuse it. The token is read from the
    # server's server.token file so we can still authenticate automatically.
    if curl -s "http://127.0.0.1:${KCODE_PORT}/" >/dev/null 2>&1; then
        local token
        token="$(read_server_token)"
        if [[ -n "$token" ]]; then
            log "Using existing Kimi server on port ${KCODE_PORT} (token found)."
            echo "http://127.0.0.1:${KCODE_PORT}/#token=${token}"
        else
            log "Using existing Kimi server on port ${KCODE_PORT} (no token file)."
            echo "http://127.0.0.1:${KCODE_PORT}/"
        fi
        return 0
    fi

    local cli
    cli="$(resolve_cli)" || die "No coding-agent CLI found (tried kimi, acode)."

    local logfile
    logfile="$(mktemp /tmp/kcode-kimi-web.XXXXXX)"
    log "Starting '${cli} web' on port ${KCODE_PORT}..."
    ("$cli" web --port "${KCODE_PORT}" >"${logfile}" 2>&1) &
    local pid=$!

    local url=""
    for ((i=0; i<KCODE_TIMEOUT; i++)); do
        if [[ -f "$logfile" ]]; then
            local line
            line="$(grep -E '^\s*Local:' "$logfile" | head -n 1 || true)"
            url="$(parse_local_url "$line")"
            if [[ -n "$url" ]]; then
                break
            fi
        fi
        sleep 1
    done

    if [[ -z "$url" ]]; then
        kill "$pid" >/dev/null 2>&1 || true
        die "Timed out waiting for '${cli} web' to print its Local URL."
    fi

    log "Server ready: ${url%%#token=*}"
    echo "$url"
}

# Clear stale Electron caches so a previous bad load state cannot cause a
# blank page on launch.
clear_app_cache() {
    local app_support="${HOME_DIR}/Library/Application Support"
    [[ -d "$app_support" ]] || return 0
    for d in "${app_support}"/*nativefier-*; do
        if [[ -d "$d" ]]; then
            rm -rf "${d}/Cache" "${d}/Code Cache" "${d}/GPUCache" "${d}/Service Worker" 2>/dev/null || true
        fi
    done
}

# Main
TARGET_URL="$(ensure_server)"

if [[ ! -f "$NATIVIER_JSON" ]]; then
    die "Bundled web app config not found: $NATIVIER_JSON"
fi

python3 - <<PY
import json, sys
path = "$NATIVIER_JSON"
with open(path, "r") as f:
    cfg = json.load(f)
cfg["targetUrl"] = "$TARGET_URL"
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
PY

clear_app_cache

# Re-sign the bundle after modifying its config. Ad-hoc signing is sufficient
# for local distribution; Gatekeeper will still need the user to allow the app
# on first launch.
codesign --sign - --force --deep "$APP_ROOT" >/dev/null 2>&1 || true

# Hand off to the real Electron binary. `exec` keeps the same PID/Dock entry.
exec "${SCRIPT_DIR}/$(basename "$0").real"
LAUNCHER

chmod +x "${REAL_BIN}"

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
