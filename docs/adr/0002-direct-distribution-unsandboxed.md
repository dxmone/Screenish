# 2. Direct distribution, unsandboxed

Date: 2026-06-15

## Status

Accepted

## Context

The app needs to write Shots to an arbitrary user-chosen Save location, expose a clean
drag-out to Finder/other apps, and capture the screen. Distribution channels: the Mac App
Store (requires App Sandbox) or direct distribution (Developer ID + notarization).

App Sandbox forces security-scoped bookmarks for the Save location, adds friction, and
constrains some capture/drag behaviors.

## Decision

Distribute **directly** (Developer ID-signed, notarized DMG), **not sandboxed**
(`ENABLE_APP_SANDBOX = NO`), Hardened Runtime on. Same model as CleanShotX/Xnapper.

## Consequences

- Free filesystem access: the Save location is a plain path, no bookmark plumbing.
- Cleaner drag-out and screen-recording behavior.
- Not eligible for the Mac App Store without revisiting sandboxing.
- Must keep Hardened Runtime + notarization for Gatekeeper.
