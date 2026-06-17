# Virtual ListView Progress

## Status: Complete

### Done
- Added `DataSource` vtable struct to `src/widgets/list_view.zig` — zero-allocation, value type
- `DataSource.fromSlice()` wraps a `[]const []const u8` pointer for backward compatibility
- Replaced `items: []const []const u8` field with `source: DataSource` on `ListView`
- Added `ListView.fromSlice()` convenience constructor (backward-compat shorthand)
- `draw()` rewritten to calculate first/last visible row with 2-row overdraw buffer; only renders that range instead of iterating all items
- scroll_offset clamping unchanged; `contentHeight()` now delegates to `source.count()`
- All event handlers (`mouse_move`, `mouse_press`, `scroll`, `key_press`) updated to use `source.count()` instead of `items.len`
- `accessNode()` updated to read selected item label via `source.get()`
- `src/main.zig`: added `LANG_SLICE: []const []const u8 = &LANG_ITEMS;` and changed `InputsState.list_view` initializer to `zui.ListView.fromSlice(&LANG_SLICE)`
- `src/root.zig`: exported `DataSource` alongside `ListView`
- `zig build` passes with zero errors or warnings

### Blocked
- (none)

### Up Next
- (none — feature complete)
