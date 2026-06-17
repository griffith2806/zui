# Drag and Drop Progress

## Status: Complete

### Done
- Added `DragPayload` and `DragPosition` types to `src/events/event.zig`
- Added `drag_enter`, `drag_over`, `drag_leave`, `drop` variants to the `Event` union
- Implemented `src/platform/win32/drop_target.zig`:
  - `IDropTarget` COM vtable (extern struct, vtable at offset 0 — same pattern as `uia.zig`)
  - `IUnknown`: QueryInterface, AddRef, Release (atomic ref count)
  - `IDropTarget`: DragEnter, DragOver, DragLeave, Drop
  - CF_HDROP extraction via `DragQueryFileW` → UTF-8 via `std.unicode.utf16LeToUtf8Alloc`
  - CF_UNICODETEXT extraction via GlobalLock/GlobalSize → UTF-8 conversion
  - Per-instance `ArenaAllocator` reset on each `DragEnter`; memory valid until next drag
  - `DROPEFFECT_COPY` returned when payload is non-empty, `DROPEFFECT_NONE` otherwise
  - Screen → client coordinate conversion via `ScreenToClient`
  - `OleInitialize` / `OleUninitialize` lifecycle managed in `create` / `destroy`
  - `RegisterDragDrop` / `RevokeDragDrop` in `create` / `destroy`
  - Type-erased `EventQueue` (fn-pointer pair) to avoid circular imports with `window.zig`
- Wired into `src/platform/win32/window.zig`:
  - `drop_target: ?*drop_mod.DropTarget` field added to `Window`
  - Created and registered in `Window.create` after `CreateWindowExW` (graceful — failure stores `null`)
  - Revoked and destroyed in `Window.deinit` before `DestroyWindow`
  - `windowPushEvent` trampoline function passes events into the ring buffer
- Linked `ole32` and `shell32` in `build.zig` (Windows-only guard)
- Updated `docs/API.md`: public API listing, full Event union, DragPayload/DragPosition types, drag-and-drop usage section with code examples and memory rules

### Blocked
- (none)

### Up Next
- (none — feature complete for Windows)
- Linux / macOS backends can implement drop via XDnD / NSPasteboard when those platforms are targeted
