# Events Progress

## Status: Complete (base types) — propagation model pending

### Done
- Event union type (`src/events/event.zig`) — MouseEvent, KeyEvent, ResizeEvent, ScrollEvent, all variants
- Modifiers struct (shift/ctrl/alt/super)
- Unit tests passing

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Event propagation model (bubble/capture) — requires widget tree abstraction
- Standalone event queue module (ring buffer, no heap allocation)
