# Layout Progress

## Status: Complete (M3)

### Done
- Geometry types: Point, Size, Rect, Margin (`src/layout/geometry.zig`)
- BoxLayout (`src/layout/box.zig`) — Direction.vertical/horizontal, spacing, padding, compute(), measure()
- GridLayout (`src/layout/grid.zig`) — configurable cols/rows/gap/padding, compute(bounds, out), measure(cell)
- GridLayout validated live: 2×2 grid with 4 colored cells in M3 demo

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Flow layout (wrap to new line when row is full)
- Constraint / stretch factor system
