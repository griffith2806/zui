# Core Progress

## Status: In Progress

### Done
- Application struct (`src/core/app.zig`) — wires platform + renderer, comptime OS dispatch

### In Progress
- Application comptime-parametrized by backend type (currently hardcoded to win32 + software)

### Blocked
_(nothing)_

### Up Next
- Refactor Application to use `Application(Platform, Renderer)` comptime pattern
- Timer and deferred-callback primitives
- Event loop: configurable frame-rate cap
