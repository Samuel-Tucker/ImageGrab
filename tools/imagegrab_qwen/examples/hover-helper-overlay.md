---
slug: hover-helper-overlay
kind: golden
files:
  - Sources/ImageGrab/ImageGrabPopoverView.swift
keywords: [hover, tooltip, helper text, overlay button, thumbnail action, caption, affordance]
---

# Example: Hover-help caption for thumbnail overlay icons

## Intent
The four overlay icons on a capture thumbnail (preview/copy-text/edit/delete) need a
visible helper label on hover, without adding permanent vertical clutter to the popover.

## Golden structure

1. Collapse separate `isPreviewHovered` / `isCopyTextHovered` / `isEditHovered` /
   `isDeleteHovered` `@State` bools into one optional enum:

   ```swift
   fileprivate enum ThumbnailAction: Hashable { case preview, copyText, edit, delete }
   @State private var hoveredOverlayAction: ThumbnailAction?
   ```

   Each strip button's `.onHover { setHoveredOverlayAction(.preview, hovering: $0) }`
   sets/clears its own case. This also fixes the cross-tinting bug where two buttons
   that share an `isXHovered` bool light up together.

2. Keep a SEPARATE `isFullWidthCopyTextHovered` for the full-width "Copy Text" button
   below the thumbnail — it must NOT share state with the strip's `text.viewfinder`
   icon.

3. Render the helper text as a small dark capsule inside the thumbnail's existing
   `ZStack`, gated on both `isCellHovered` and `hoveredOverlayAction != nil`:

   ```swift
   if let label = hoveredOverlayActionLabel {
       VStack {
           Spacer()
           Text(label)
               .font(.system(size: 10, weight: .semibold))
               .foregroundStyle(.white)
               .padding(.horizontal, 8).padding(.vertical, 3)
               .background(Capsule().fill(Color.black.opacity(0.78)))
               .padding(.bottom, 6)
       }
       .frame(maxWidth: .infinity)
       .allowsHitTesting(false)
       .transition(.opacity)
   }
   ```

4. Compute the label from `hoveredOverlayAction` + Copy-Text state ("Reading Text…",
   "Text Copied", "No Text Found", or "Copy Text" when idle).

## Don't
- Don't replace `.help(...)` tooltips; keep them as the accessibility fallback.
- Don't add the caption outside the thumbnail's `ZStack` — it would change the cell
  height and reflow the grid.
- Don't use a `.popover` or `.toolTip` for this; it must be in-thumbnail and silent.
