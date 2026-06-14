# Core Progress

## Status: Complete (M11/M13 + gap-close)

### Done
- Application struct (`src/core/app.zig`) — wires platform + renderer, comptime OS dispatch
- Linux path added: `.linux => x11/window.zig`; GDI calls guarded by `comptime builtin.os.tag == .windows`
- `deltaSeconds()` using Win32 `GetTickCount64`, capped at 0.1s per frame
- `syncSize()` — propagates resize to renderer after event loop
- `animation.zig` — `Tween` struct (exponential decay), `easeOut` helper
- `focus.zig` — FocusManager: monotonic ID handles, tab/shift-tab traversal, hasFocus(id)

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Refactor Application to use `Application(Platform, Renderer)` comptime pattern
- Animation timeline / keyframes
- Event loop: configurable frame-rate cap
