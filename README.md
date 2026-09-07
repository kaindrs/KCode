# KCode

A native macOS wrapper for the Kimi Code web interface, built with [Nativefier](https://github.com/nativefier/nativefier).

![Icon](assets/icon.svg)

## What it does

KCode turns your local Kimi Code web UI into a single standalone `.app` with its own Dock icon, menu bar, and window.

On every launch KCode will:

1. Check whether `kimi web` (or AXIOM's fork-lifted `acode web`) is already running on port `58627`.
2. If not, start it automatically.
3. Capture the one-time Local URL including the bearer token.
4. Open the IDE, already authenticated, in its own window.

Because the URL and token are resolved at runtime, nothing secret is baked into the app bundle.

## Download

Grab the latest release from the [Releases](https://github.com/kaindrs/KCode/releases) page.

## Build from source

### Requirements

- macOS
- Node.js 18+
- npm
- `kimi` or `acode` CLI installed (only needed at runtime; the build itself does not start a server)

### Local build

```bash
git clone https://github.com/kaindrs/KCode.git
cd KCode
npm install
npm run build
```

The built app appears at `build/KCode.app`.

### Install to ~/Applications

```bash
KCODE_INSTALL=1 npm run build
```

## Configuration

All settings are controlled through environment variables:

| Variable                  | Default                         | Description                                                  |
|---------------------------|---------------------------------|--------------------------------------------------------------|
| `KCODE_NAME`              | `KCode`                         | App display name                                             |
| `KCODE_BUNDLE_ID`         | `ai.kimi.code.kmac`             | macOS bundle identifier                                      |
| `KCODE_ICON`              | `./assets/icon.png`             | Path to a 1024×1024 PNG or SVG icon                          |
| `KCODE_OUTPUT`            | `./build`                       | Directory for the built `.app`                               |
| `KCODE_ARCH`              | `arm64`                         | Target architecture: `arm64`, `x64`                          |
| `KCODE_INSTALL`           | `0`                             | Set to `1` to copy the app to `~/Applications`               |
| `KCODE_KIMI_WEB_PORT`     | `58627`                         | Port `kimi web` / `acode web` listens on                     |
| `KCODE_KIMI_WEB_TIMEOUT`  | `30`                            | Seconds to wait for a fresh server to print its Local URL    |

The launcher also respects `KIMI_CODE_HOME` if your Kimi Code config directory is not in the default `~/.kimi-code` location.

## First launch

The app is ad-hoc signed. If macOS shows a security warning, right-click the app and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine ~/Applications/KCode.app
```

## CI / Releases

A GitHub Actions workflow builds the app on every push and pull request. Pushing a tag like `v1.0.0` creates a GitHub Release with a zipped `.app` artifact.

No repository secrets are required: the built app resolves its own URL and token at runtime.

## Project structure

```
KCode/
├── assets/             # App icon (PNG + SVG source)
├── scripts/
│   └── build.sh        # Automated macOS build script
├── .github/workflows/
│   └── build.yml       # GitHub Actions CI/CD
├── package.json
├── README.md
└── LICENSE
```

## License

MIT © kaindrs
