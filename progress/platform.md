# Platform Progress

## Status: Win32 Complete; X11 M19 Implementation Written (untested on Linux)

### Done
- Win32 platform backend (`src/platform/win32/window.zig`) — fully working
  - Window creation, message loop, WndProc → zui Events
  - Mouse/keyboard/resize/close, clipboard, modifier tracking
  - DWM Mica title-bar compositing via `DWMSBT_MAINWINDOW` — Mica on title bar and window chrome
    (client-area Mica requires DirectComposition; `WS_EX_NOREDIRECTIONBITMAP` breaks GDI BitBlt)
- X11 backend (`src/platform/x11/window.zig`) — M19 full implementation written
  - XOpenDisplay / XCreateSimpleWindow / XMapWindow
  - Pixel buffer allocated with the Zig allocator; XImage + XPutImage for software blit
  - XNextEvent loop: key press/release with XLookupString (char_input), mouse
    press/release, mouse motion, scroll (Button4/Button5), resize (ConfigureNotify),
    Expose → paint event, FocusIn/FocusOut
  - WM_DELETE_WINDOW protocol for close-button handling
  - dpi_scale: detected via Xft.dpi resource, falls back to 1.0
  - Pixel buffer resized on ConfigureNotify
  - build.zig: `exe.linkSystemLibrary("X11")` + `linkLibC()` added for Linux targets
  - NOTE: untested on Linux — requires a Linux environment to validate

### In Progress
_(nothing)_

### Blocked
_(nothing — implementation complete, needs Linux runtime validation)_

### Up Next
- Validate X11 backend on a Linux machine or CI runner
- Cocoa backend (macOS) — not started
