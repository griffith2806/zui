# Layout Progress

## Status: Complete (M3 + M13 + gap-close + resize constraints)

### Done
- Geometry types: Point, Size, Rect, Margin (`src/layout/geometry.zig`)
- BoxLayout (`src/layout/box.zig`) — Direction.vertical/horizontal, spacing, padding, compute(), measure()
- BoxLayout.computeWithFlex() — proportional flex distribution among items with flex[i] > 0 (M13)
- BoxLayout.computeConstrained() — per-item min/max clamps, backward-compat; `ItemConstraint` struct exported from root.zig
- GridLayout (`src/layout/grid.zig`) — configurable cols/rows/gap/padding, compute(bounds, out), measure(cell)
- FlowLayout (`src/layout/flow.zig`) — wraps items to next row, gap_x/gap_y/padding, compute(), measure() — exported from root.zig (M13)
- Minimum window size enforced via WM_GETMINMAXINFO (900×600 logical px, DPI-scaled) in `src/platform/win32/window.zig`
- nav_rects recomputed each frame inside the main loop — nav clicks correct after resize
- ScrollArea wired into About, Colors, Layout pages — content scrolls when taller than viewport
- Fixed pre-existing `scroll_area.zig` Point type-inference bug (anonymous struct → explicit `Point{}`)

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Absolute/anchor layout
