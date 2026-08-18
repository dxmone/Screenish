# Screenish

A macOS menu-bar screenshot app, inspired by Xnapper and CleanShotX.
Created by Thomas Strömberg with AI coding.

## Features

- **Capture** region / window / full screen via global hotkeys (ScreenCaptureKit);
  every capture is copied to the clipboard immediately.
- **Floating stack** of recent shots, pinned to the primary screen, with uniform
  cards, a collapsing pile when there are many, and drag-out to any app (Finder,
  Terminal, chat/Electron apps). Right-click a card for Save to Folder, Copy,
  Copy and Remove, or Remove.
- **Annotation editor** — arrow, line, rectangle, ellipse, highlight, text, blur,
  pixelate, spotlight, counter, pencil, crop; non-destructive (re-editable),
  undo/redo. Scroll or pinch to zoom the canvas (1x–8x) for precise annotation —
  the export is always the full screenshot.
- **Beautify** — padding, background (gradient presets), corner radius, shadow,
  aspect ratio; savable presets, remembered as the default for new captures.
- **Settings** — save location, open-editor-after-capture, compress to JPG,
  remove-after-drag, launch at login, language (Swedish + English), and an About
  tab. Crash logs land in `~/Library/Logs/Screenish` ("Reveal Crash Logs" in the
  tray menu).
- Menu-bar agent (no Dock icon).

## Requirements

- macOS 26+
- Xcode 26+

## Build

```sh
xcodebuild -project Screenish.xcodeproj -scheme Screenish build
```

## Release

Versioning: `MARKETING_VERSION` is the semver app version, bumped by hand before
each release; the build number is the git commit count, injected at build time.
See `CLAUDE.md` for the full rules.

```sh
./scripts/export-release.sh   # Release build → ~/Downloads/Screenish-<version>-b<build>.zip
```

## Privacy

Screenish makes no network connections and collects no analytics. Screenshots
stay on your Mac: working copies live in per-user temp/cache directories
(owner-only, swept at launch and cleaned on quit) and are otherwise only where
you put them — the clipboard, a saved folder, or a drag destination.
