# 1. ScreenCaptureKit with a custom selection overlay

Date: 2026-06-15

## Status

Accepted

## Context

A Capture needs both a pixel source and a way for the user to choose region/window/screen.
Options for the pixel source: shell out to `/usr/sbin/screencapture`, or use ScreenCaptureKit
(`SCScreenshotManager`). Options for selection: the free crosshair UI from the
`screencapture` CLI, or a custom overlay.

The CLI gives a working selection UI for free but no control over its look or behavior, no
path to live magnifier/dimension chrome, and no clean path to video later.

## Decision

Use **ScreenCaptureKit** (`SCScreenshotManager.captureImage`) for pixels, and a **custom
borderless overlay** (`SelectionOverlay`) spanning all displays for selection.

## Consequences

- Full control over capture UX (crosshair, dimensions, window highlight), matching the
  CleanShotX feel.
- Requires the Screen Recording (TCC) permission and handling its prompt.
- The same engine extends to video/scrolling capture later without a rewrite.
- More code than shelling out to the CLI; coordinate-system conversions (AppKit global ↔
  CoreGraphics global ↔ display-local pixels) must be handled carefully.
