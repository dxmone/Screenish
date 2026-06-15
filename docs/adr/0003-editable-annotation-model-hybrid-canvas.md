# 3. Editable annotation model on a hybrid AppKit canvas

Date: 2026-06-15

## Status

Accepted (forward-looking — implemented in Phase 2)

## Context

The Editor must let users add arrows, boxes, text, blur, etc. Two representations are
possible: an immediate-mode raster (bake each stroke into the bitmap) or an editable object
model (each Annotation is a retained object with position/style/z-order). The raster path is
simpler but prevents moving or restyling an Annotation after it is drawn.

The drawing surface can be pure SwiftUI `Canvas`, pure AppKit `NSView`, or a hybrid.
Hit-testing many objects, drag-handles, and live CoreImage blur/pixelate are awkward in pure
SwiftUI.

## Decision

Use an **editable object model**: the captured bitmap is the base layer; each Annotation is
an object that can be selected, moved, restyled, reordered, and undone; export composites
all layers to a CGImage.

Build the Editor as a **hybrid**: SwiftUI for chrome (toolbar, inspector, settings) and a
custom AppKit `NSView` (via `NSViewRepresentable`) for the drawing surface.

## Consequences

- Annotations remain editable after creation (CleanShotX-like UX).
- Mature hit-testing, drag-handles, and `CIFilter` live blur/pixelate on the canvas.
- Two UI paradigms coexist; the AppKit canvas needs an explicit bridge to SwiftUI state.
- Export logic is shared with Phase 1 (`ImageExport`).
