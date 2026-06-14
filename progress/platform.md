# Platform Progress

## Status: Complete (Win32, M13)

### Done
- Win32 platform backend (`src/platform/win32/window.zig`)
  - Window creation (RegisterClassExW, CreateWindowExW)
  - DIB section for software rendering pixel buffer
  - Message loop (PeekMessage, DispatchMessage)
  - WndProc translating Win32 messages → zui Events
  - Mouse press/release/move/wheel, keyboard (full VK mapping), resize, close
  - present() via BitBlt
  - **M9**: resizeDIB correct GDI deletion order (select new bitmap before deleting old)
  - **M13**: WM_KEYDOWN/WM_KEYUP with modifier tracking (Shift/Ctrl/Alt via GetKeyState i16→u16 bitcast)
  - **M13**: Clipboard support (`src/platform/win32/clipboard.zig`) — CF_UNICODETEXT, GlobalAlloc/Lock/Unlock

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Platform interface / vtable or comptime trait design
- x11 backend (Linux)
- Cocoa backend (macOS) — stub
