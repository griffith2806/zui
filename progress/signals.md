# Signals Progress

## Status: Complete (+ slot safety)

### Done
- Signal(T) generic type (`src/signals/signal.zig`) — comptime payload type
- connect(alloc, ctx, comptime func) → Connection — returns generation-stamped handle
- Connection{ gen: u32, ctx: *anyopaque } — safe disconnect via disconnectHandle()
- disconnectHandle(handle) — no-op if handle is stale (generation mismatch); safe to call twice
- disconnect(ctx) — removes all slots matching ctx pointer regardless of generation
- emit(value) — synchronous dispatch to all connected slots
- deinit — cleanup via ArrayListUnmanaged

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Queued/deferred emit (post to next-frame queue)
- Comptime connection verification enhancements
