# Events Progress

## Status: In Progress

### Done
- Event union type (`src/events/event.zig`) — MouseEvent, KeyEvent, ResizeEvent, ScrollEvent, all variants
- Unit tests passing (`zig build test`)

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Event queue (ring buffer, no heap allocation) — done in Win32 backend, needs standalone module
- Propagation model (bubble vs capture) — needed when widget tree exists
