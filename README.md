# KCode

A native macOS wrapper for the Kimi Code web interface, built with [Nativefier](https://github.com/nativefier/nativefier).

![Icon](assets/icon.svg)

## What it does

KCode turns your local Kimi Code web UI into a standalone `.app` with its own Dock icon, menu bar, and window. The access token is embedded as a URL fragment so you are signed in automatically on launch.

## Download

Grab the latest release from the [Releases](https://github.com/kaindrs/KCode/releases) page.

## Build from source

### Requirements

- macOS
- Node.js 18+
- npm

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

| Variable         | Default                         | Description                                      |
|------------------|---------------------------------|--------------------------------------------------|
| `KCODE_URL`      | `http://127.0.0.1:58627`        | Base URL of the Kimi Code web interface          |
| `KCODE_TOKEN`    | —                               | Access token appended as a URL fragment          |
| `KCODE_NAME`     | `KCode`                         | App display name                                 |
| `KCODE_BUNDLE_ID`| `ai.kimi.code.kmac`             | macOS bundle identifier                          |
| `KCODE_ICON`     | `./assets/icon.png`             | Path to a 1024×1024 PNG or SVG icon              |
| `KCODE_OUTPUT`   | `./build`                       | Directory for the built `.app`                   |
| `KCODE_ARCH`     | `arm64`                         | Target architecture: `arm64`, `x64`              |
| `KCODE_INSTALL`  | `0`                             | Set to `1` to copy the app to `~/Applications`   |

### Example with a token

```bash
KCODE_TOKEN="your-token-here" KCODE_INSTALL=1 npm run build
```

This produces `~/Applications/KCode.app` pointing to `http://127.0.0.1:58627/#token=your-token-here`.

## First launch

The app is ad-hoc signed. If macOS shows a security warning, right-click the app and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine ~/Applications/KCode.app
```

## CI / Releases

A GitHub Actions workflow builds the app on every push and pull request. Pushing a tag like `v1.0.0` creates a GitHub Release with a zipped `.app` artifact.

To configure CI builds with your own Kimi Code instance, add these repository secrets in GitHub:

- `KCODE_URL`
- `KCODE_TOKEN`

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
