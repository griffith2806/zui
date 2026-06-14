# Core Progress

## Status: Complete (M11/M13)

### Done
- Application struct (`src/core/app.zig`) — wires platform + renderer, comptime OS dispatch
- `deltaSeconds()` using Win32 `GetTickCount64`, capped at 0.1s per frame
- `syncSize()` — propagates resize to renderer after event loop
- `initGdi` wired in `Application.init` for software backend (passes `dc_mem`)
- `animation.zig` — `Tween` struct (exponential decay), `easeOut` helper

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Refactor Application to use `Application(Platform, Renderer)` comptime pattern
- Event loop: configurable frame-rate cap
