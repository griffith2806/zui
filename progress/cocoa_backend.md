# Cocoa Backend Progress

## Status: In Progress (skeleton complete, implementation not started)

### Done
- `src/platform/cocoa/window.zig` — stub `Window` struct matching win32/window.zig interface
  - All required fields: `pixels`, `width`, `height`, `size_changed`, `dpi_scale`,
    `should_close`, `nswindow`, `nsview`, `dc_mem` (compat alias), `hwnd` (compat alias)
  - All required methods: `create`, `deinit`, `pollEvent`, `present`, `releasePresent`,
    `resizeDIB`, `initUia`, `deinitUia`, `updateAccessibility`
  - Comptime guard: `if (builtin.os.tag != .macos) @compileError(...)`
  - Runtime guard: all unimplemented methods `@panic("Cocoa backend not yet implemented")`
  - Accessibility no-ops (initUia / deinitUia / updateAccessibility compile cleanly)
- `src/platform/cocoa/event_loop.zig` — stub `EventLoop` struct
  - `init(window)`, `poll()`, `run()`, `deinit()` — all stubbed with `@panic`
- `src/platform/cocoa/platform.zig` — re-exports `Window` and `EventLoop`
- `src/core/app.zig` — added `.macos` branch to the Window comptime switch
  - Extracted `getTickMs()` / `sleepMs()` helpers to eliminate bare `extern "kernel32"`
    declarations at module scope (they live inside a comptime-guarded inner struct now)
- `build.zig` — added `.macos` branch to the platform library linkage block
  - Links `Cocoa.framework`, `Foundation.framework`, `CoreGraphics.framework`
  - Sets `link_libc = true`
- `docs/API.md` — noted macOS backend skeleton under Platform Backends section

### In Progress
_(nothing)_

### Blocked
_(nothing — skeleton is complete)_

### Up Next
- Validate on a macOS machine (cross-compilation from Windows is possible with
  `zig build -Dtarget=aarch64-macos` but requires macOS SDK sysroot)
- Implement `Window.create`:
  - `[NSApplication sharedApplication]`
  - `[NSWindow initWithContentRect:styleMask:backing:defer:]`
  - Allocate pixel buffer (CGBitmapContext or IOSurface for Retina)
  - Install NSWindowDelegate for resize / close callbacks
- Implement `Window.pollEvent`:
  - `[NSApp nextEventMatchingMask:untilDate:inMode:dequeue:]` polling loop
  - Map NSEvent key codes → `zui.KeyCode`
  - Map NSEvent mouse events → `zui.Event`
- Implement `Window.present` (software backend):
  - Wrap pixel buffer in `CGDataProviderCreateWithData`
  - Create `CGImageRef` and draw into `NSView` via `CGContextDrawImage`
- Wire up NSAccessibility for `updateAccessibility`
