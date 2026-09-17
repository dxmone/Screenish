# Screenish

A screenshot app for macOS and Windows, inspired by Xnapper and CleanShotX.
Created by Thomas Strömberg with AI coding.

| Client  | Folder      | Stack                                   | Ships as         |
|---------|-------------|-----------------------------------------|------------------|
| macOS   | `macos/`    | Swift, SwiftUI/AppKit, ScreenCaptureKit | notarized `.zip` |
| Windows | `windows/`  | C#, .NET 8, WPF                         | `.msi` (WiX)     |

The two clients mirror each other feature for feature and file for file
(see `docs/adr/0004-windows-client-wpf-mirror.md`).

## Download & install

Grab the latest build from the [Releases page](https://github.com/dxmone/Screenish/releases/latest).

- **Windows** — download `Screenish-<version>-b<build>.msi` and run it. It installs into
  `Program FilesScreenish`, adds a Start menu shortcut and upgrades older versions in
  place. No .NET install is needed. Builds marked `-unsigned` are not code-signed, so
  SmartScreen shows "Windows protected your PC" — choose **More info → Run anyway**.
  Silent install for managed PCs: `msiexec /i Screenish-<version>-b<build>.msi /qn`.
- **macOS** — download `Screenish-<version>-b<build>.zip`, unzip and move `Screenish.app`
  to Applications. Grant Screen Recording permission on the first capture.

After launch Screenish lives in the notification area (Windows) or the menu bar (macOS):
press Ctrl+Shift+1 / 2 / 3 to capture an area, a window or the full screen.

## Features

- **Capture** region / window / full screen via global hotkeys
  (Ctrl+Shift+1/2/3, rebindable); every capture is copied to the clipboard immediately.
- **Floating stack** of recent shots, pinned to the primary screen, with uniform
  cards, a collapsing pile when there are many, and drag-out to any app (Finder/Explorer,
  terminals, chat/Electron apps). Right-click a card for Save to Folder, Copy,
  Copy and Remove, or Remove.
- **Annotation editor** — arrow, line, rectangle, ellipse, highlight, text, blur,
  pixelate, spotlight, counter, pencil, crop; non-destructive (re-editable),
  undo/redo. Scroll or pinch to zoom the canvas (1x–8x) for precise annotation —
  the export is always the full screenshot.
- **Beautify** — padding, background (gradient presets), corner radius, shadow,
  aspect ratio; savable presets, remembered as the default for new captures.
- **Settings** — save location, open-editor-after-capture, compress to JPG,
  remove-after-drag, remove-after-save, launch at login, language (Swedish + English),
  and an About tab. Crash logs land in `~/Library/Logs/Screenish` (macOS) or
  `%LOCALAPPDATA%\Screenish\Logs` (Windows) — "Reveal Crash Logs" in the tray menu.
- Menu-bar / notification-area agent (no Dock icon, no taskbar button).

## macOS

Requirements: macOS 26+, Xcode 26+.

```sh
xcodebuild -project macos/Screenish.xcodeproj -scheme Screenish build
./macos/scripts/export-release.sh   # Release build → ~/Downloads/Screenish-<version>-b<build>.zip
```

## Windows

Requirements: Windows 10 2004+ (x64), .NET 8 SDK to build. The installed app is
self-contained — no .NET needed on the target PC.

```powershell
dotnet build windows\Screenish\Screenish.csproj          # debug build
dotnet run --project windows\Screenish                   # run from source
.\windows\scripts\export-release.ps1                     # Release → ~\Downloads\Screenish-<version>-b<build>.msi
```

The MSI installs per-machine into `Program Files\Screenish`, adds a Start menu
shortcut, upgrades in place, and can be deployed silently:
`msiexec /i Screenish-<version>-b<build>.msi /qn`.

Checks that need no user input:

```powershell
Screenish.exe --render-test C:\temp\out   # renders annotations / beautify / editor UI to PNGs
Screenish.exe --smoke-test                # capture → stack → editor → overlay; exit code = failures
```

## Versioning

Both clients carry the same semver app version, bumped by hand before each release
(`MARKETING_VERSION` on macOS, `<Version>` in `Screenish.csproj` on Windows); the build
number is the git commit count, injected at build time. See `CLAUDE.md` for the full rules.

## Privacy

Screenish makes no network connections and collects no analytics. Screenshots
stay on your computer: working copies live in per-user temp/cache directories
(swept at launch and cleaned on quit) and are otherwise only where
you put them — the clipboard, a saved folder, or a drag destination.
