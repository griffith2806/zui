# Platform Progress

## Status: In Progress

### Done
- Win32 platform backend (`src/platform/win32/window.zig`)
  - Window creation (RegisterClassExW, CreateWindowExW)
  - DIB section for software rendering pixel buffer
  - Message loop (PeekMessage, DispatchMessage)
  - WndProc translating Win32 messages → zui Events
  - Mouse press/release/move, keyboard (full VK mapping), resize, close
  - present() via BitBlt
- `zig build` passes, `zig build run` opens a window (Milestone 1 ✓)

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Platform interface / vtable or comptime trait design
- x11 backend (Linux)
- Cocoa backend (macOS) — stub
- Clipboard and cursor APIs
