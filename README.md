# Screenish

A macOS menu-bar screenshot app, inspired by Xnapper and CleanShotX.

## Features

- **Capture** region / window / full screen via global hotkeys (ScreenCaptureKit).
- **Floating stack** of recent shots (bottom-left), with drag-out to any app and
  a collapsing pile when there are many.
- **Annotation editor** — arrow, line, rectangle, ellipse, highlight, text, blur,
  pixelate, crop; non-destructive (re-editable), undo/redo.
- **Beautify** — padding, background (gradient presets), corner radius, shadow,
  aspect ratio; remembered as the default for new captures.
- Menu-bar agent (no Dock icon), Swedish + English localization.

## Requirements

- macOS 26+
- Xcode 26+

## Build

```sh
xcodebuild -project Screenish.xcodeproj -scheme Screenish build
```
