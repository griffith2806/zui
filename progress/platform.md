# Platform Progress

## Status: Win32 Complete; X11 Stub (M13 + gap-close)

### Done
- Win32 platform backend (`src/platform/win32/window.zig`) — fully working
  - Window creation, message loop, WndProc → zui Events
  - Mouse/keyboard/resize/close, clipboard, modifier tracking
- X11 stub (`src/platform/x11/window.zig`) — interface mirrors Win32; methods panic at runtime
  - File structure exists; `app.zig` comptime-dispatches to it on Linux

### In Progress
_(nothing)_

### Blocked
- X11 real implementation needs a Linux build environment

### Up Next
- X11 real implementation (XOpenDisplay, XCreateWindow, XPutImage, XNextEvent)
- Cocoa backend (macOS) — not started
