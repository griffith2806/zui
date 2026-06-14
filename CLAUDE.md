# zui — Zig UI Framework

A Qt-inspired, cross-platform UI framework written in Zig. Provides widgets, layouts, an event system, a signal/slot mechanism, and platform/graphics backends — all with zero hidden allocations and comptime-driven ergonomics.

## Build Commands

```bash
zig build              # Build library + demo executable
zig build run          # Build and run demo
zig build test         # Run all tests (module + exe tests, in parallel)
zig build --help       # Full option menu
```

Minimum Zig version: **0.16.0**

## Repository Layout

```
src/
  root.zig             # Public API re-exports (library entry point)
  main.zig             # Demo executable entry point
  core/                # Event loop, allocator wrappers, runtime
  widgets/             # Button, Label, TextField, Container, …
  layout/              # Box, Grid, Flow layout engines
  style/               # Theme, Color, Font descriptors
  events/              # Event types and dispatch
  signals/             # Signal/slot mechanism
  platform/            # OS backends: win32/, x11/, cocoa/
  graphics/            # Renderer backends: software/, opengl/, vulkan/
docs/
  architecture.md      # High-level design decisions
  ROADMAP.md           # Feature roadmap and milestone tracking
progress/              # Per-subsystem progress files (see below)
```

## Progress Files — Required

This project is large and multi-subsystem. **Every non-trivial task must maintain a progress file** in `progress/`. This lets multiple agents work in parallel without stepping on each other and gives a clear snapshot of what is done, in-flight, and blocked.

### Convention

- One file per subsystem or major feature: `progress/core.md`, `progress/widgets.md`, `progress/layout.md`, etc.
- Each file uses this structure:

```markdown
# <Subsystem> Progress

## Status: [Not Started | In Progress | Blocked | Complete]

### Done
- [ item ]

### In Progress
- [ item ] — brief note on current state

### Blocked
- [ item ] — what is blocking it

### Up Next
- [ item ]
```

- Update the file **before starting** a task and **after completing** it.
- If you are blocked, write what is blocking you in the progress file and stop. Do not work around a blocker silently.

## Parallelism — Required

**Always use parallel agents for independent subsystems.** The codebase is structured so that `core`, `widgets`, `layout`, `style`, `events`, `signals`, `platform`, and `graphics` can be developed independently.

Rules:
- Before spawning work on any subsystem, check its progress file to avoid conflicts.
- Never have two agents edit the same file at the same time. Coordinate through progress files.
- Prefer launching agents with `isolation: "worktree"` for independent branches.
- When a subsystem depends on another (e.g. widgets depend on core), finish the dependency first or stub it with a clear interface.

## Architecture Decisions

- **No hidden allocations** — every function that allocates takes an `std.mem.Allocator`.
- **Comptime where possible** — widget trees and signal connections are resolved at comptime when types are known statically.
- **Backend-agnostic rendering** — the graphics backend is a comptime parameter, not a runtime dispatch.
- **Signal/slot** — typed, comptime-verified connections, no string-based lookup.
- **Cross-platform** — platform backends live in `src/platform/`; a single `Platform` interface is the only thing widgets ever see.

## Coding Conventions

- Zig 0.16 idioms; `std.debug.assert` for invariants, not error returns.
- All public types exported from `src/root.zig`.
- Tests live alongside source (`test "..." { ... }` blocks in the same file).
- No external C dependencies unless inside a `platform/` or `graphics/` backend.
