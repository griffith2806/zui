# Layout Progress

## Status: Complete (M3 + M13 + gap-close)

### Done
- Geometry types: Point, Size, Rect, Margin (`src/layout/geometry.zig`)
- BoxLayout (`src/layout/box.zig`) — Direction.vertical/horizontal, spacing, padding, compute(), measure()
- BoxLayout.computeWithFlex() — proportional flex distribution among items with flex[i] > 0 (M13)
- GridLayout (`src/layout/grid.zig`) — configurable cols/rows/gap/padding, compute(bounds, out), measure(cell)
- FlowLayout (`src/layout/flow.zig`) — wraps items to next row, gap_x/gap_y/padding, compute(), measure() — exported from root.zig (M13)

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Constraint system (min/max size per item)
- Absolute/anchor layout
