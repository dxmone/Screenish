# 4. Windows client: a WPF mirror of the macOS app, shipped as an MSI

Date: 2026-09-17

## Status

Accepted

## Context

Screenish should run on Windows with the same features as the macOS client (ADR 1–3):
hotkey capture, the floating Stack with drag-out, the non-destructive editor, beautify,
settings, crash logs. The macOS code is AppKit/SwiftUI/ScreenCaptureKit and cannot be
shared, and the result must install "for real" from an MSI.

## Decision

- The repo holds one client per platform: `macos/` (unchanged Xcode project) and
  `windows/`. They share no code, but the Windows client **mirrors the macOS one file by
  file** (`Capture/`, `Core/`, `Editor/`, `Stack/`, `Settings/`, `Background/`), with the
  same names, constants and behaviour, so a change on one side has an obvious place on
  the other. The English UI strings are the localization keys on both sides.
- **C# / .NET 8 / WPF**, UI built in code. Self-contained publish, so the target PC needs
  no .NET install. WinForms is referenced only for `NotifyIcon` (tray) and `Screen`.
- **Capture freezes the desktop first** (GDI copy of the virtual screen, our own windows
  hidden from it via `SetWindowDisplayAffinity`), then shows one overlay window per
  monitor over the frozen pixels and crops the selection out of that grab. Window
  captures prefer `PrintWindow` (complete even when covered) and fall back to the frozen
  pixels. Everything is in physical pixels; the process is per-monitor-DPI aware.
- **One renderer for canvas and export**, like ADR 3: `AnnotationDrawer` draws into a
  WPF `DrawingContext` in image-pixel space. WPF has no blend modes or reliable software
  filters, so blur, pixelate, the highlight's multiply blend and the beautify drop shadow
  are computed on raw pixels (`Core/Pixels.cs`).
- **Drag-out writes a real file** and drags it as `CF_HDROP` (works in Explorer,
  terminals and Electron apps), with a click-through thumbnail window following the cursor.
- Settings live in `%APPDATA%\Screenish\settings.json` with the macOS `UserDefaults` keys
  and the same beautify JSON, so presets are portable. Logs: `%LOCALAPPDATA%\Screenish\Logs`.
- **MSI via WiX 5** (`windows/Installer`), per-machine into Program Files, in-place
  upgrades keyed on a fixed UpgradeCode. `windows/scripts/export-release.ps1` is the
  counterpart of `macos/scripts/export-release.sh`.

## Consequences

- Both clients carry the same version number; a feature is not done until it exists in both.
- Windows-only niceties, because a tray icon can hide in the overflow: the very first
  launch opens Settings once, and launching the app while it is already running brings
  up Settings instead of doing nothing.
- Platform differences that remain: no Screen Recording permission step on Windows; the
  "Rounded" text styles fall back to the closest installed rounded font; native crashes
  are not collected (managed exceptions are logged with full stack traces); an unsigned
  MSI triggers SmartScreen the way an unnotarized app triggers Gatekeeper.
- `Screenish.exe --render-test <dir>` and `--smoke-test` verify rendering and the capture
  pipeline without user input.
