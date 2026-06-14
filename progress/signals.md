# Signals Progress

## Status: Complete

### Done
- Signal(T) generic type (`src/signals/signal.zig`) — comptime payload type
- connect(alloc, ctx, comptime func) — type-erased slot using comptime wrapper
- emit(value) — synchronous dispatch to all connected slots
- disconnect_all / deinit — cleanup via ArrayListUnmanaged
- Validated live: btn.clicked Signal(void) connected to counter increment, reset, about toggle

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Weak-ref safety for slot lifetime (Milestone 3+)
- Comptime connection verification enhancements
