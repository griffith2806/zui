# Data Binding Progress

## Status: Complete

### Done
- `Property(T)` generic type (`src/signals/property.zig`)
  - `init(initial: T) Property(T)` — no allocation
  - `get() T` — no allocation, returns cached value
  - `set(new_val: T) void` — emits `changed` only when value differs
  - `bind(alloc, *Property(T)) !void` — one-directional binding via Signal slot
  - `deinit(alloc) void` — frees slot list
  - Equality check: `std.mem.eql` for slices, `==` for scalars (comptime dispatch)
  - 5 unit tests covering: scalar get/set, signal firing, equal-write silence, bind propagation, slice equality
- `Computed(T)` generic type (`src/signals/computed.zig`)
  - `init(*anyopaque, *const fn(*anyopaque) T) Computed(T)` — calls compute immediately; no allocation
  - `get() T` — returns cached value, recomputes if dirty; no allocation
  - `invalidate() void` — manually mark dirty; no allocation
  - `addSource(alloc, *Property(S)) !void` — wire any Property type as a source; allocates one Signal slot
  - `deinit(alloc) void` — cleans up source list
  - 3 unit tests: basic derive, cache-hit counting, manual invalidate
- Exports added to `src/root.zig`:
  - `pub fn Property(comptime T: type) type`
  - `pub fn Computed(comptime T: type) type`
- `docs/API.md` updated with full Property(T) and Computed(T) reference sections

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Two-way bind helper (bidirectional `Property.bindBoth`)
- Queued/deferred emit support (post changes to next-frame queue, avoid re-entrancy issues)
- Widget integration: TextField exposes `text_prop: Property([]const u8)` for model binding
