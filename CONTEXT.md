# Screenish — Context & Glossary

Screenish is a macOS menu-bar app for screenshots: a blend of Xnapper and CleanShotX.
Capture via global hotkeys, a floating thumbnail stack with drag-out, an annotation
editor, and Xnapper-style backgrounds/beautify.

This file is a **glossary only** — no implementation details. See `docs/adr/` for decisions.

## Ubiquitous language

- **Capture** — the act of grabbing pixels from the screen. Comes in three modes:
  *region*, *window*, *screen*.
- **Shot** — a captured image; the artifact a Capture produces. A Shot lives first in a
  temp file and is *saved* or *dragged out* on demand.
- **Stack** (a.k.a. Quick Access) — the floating, non-activating panel pinned to the
  bottom-left of the main screen where Shots pile up newest-first. *Drag-out* from the
  Stack copies a Shot's file to the drop target.
- **Editor** — the annotation window opened for a Shot. *(Phase 2)*
- **Annotation** / **Layer** — an editable object placed on a Shot's base bitmap (Arrow,
  Box, Ellipse, Line, Text, Highlight, Blur, Pixelate). Editable after creation. *(Phase 2)*
- **Beautify** / **Background** — the inspector panel in the Editor controlling padding,
  background, corner radius, shadow, and aspect ratio. *(Phase 3)*
- **Tray** — the menu-bar status item (`MenuBarExtra`). The app has no Dock icon.
- **Save location** — the user's chosen default folder for saved Shots.
