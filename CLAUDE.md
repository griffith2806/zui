# zui — Zig UI Framework

A Qt-inspired, cross-platform UI framework written in Zig. Provides widgets, layouts, an event system, a signal/slot mechanism, and platform/graphics backends — all with zero hidden allocations and comptime-driven ergonomics.

## Build Commands

```bash
zig build              # Build library + demo executable
zig build run          # Build and run demo
zig build test         # Run all tests (module + exe tests, in parallel)
zig build --help       # Full option menu
```

### Quick live testing (Claude sessions)

```powershell
.\launch.ps1           # Build + kill any old instance + launch fresh
.\launch.ps1 -NoBuild  # Launch last build without rebuilding (faster iteration)
```

Use `launch.ps1` before calling any `mcp__ui-automation__*` tool to get a clean, up-to-date app window. Combine with `zig build --watch` in a second terminal for continuous rebuild on save.

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

## Zig Std Source — Required for API Calls

Zig 0.16.0 std library is at:
```
c:\Users\danie\AppData\Roaming\Code\User\globalStorage\ziglang.vscode-zig\zig\x86_64-windows-0.16.0\lib\std\
```

**Before writing any `std.*` API call you are not 100% certain about, read the relevant source file to verify current signatures.** Zig's std API changes between releases; do not rely on training-data memory for function signatures, field names, or error sets.

Examples:
- Using `std.mem` → read `.../lib/std/mem.zig`
- Using `std.ArrayList` → read `.../lib/std/array_list.zig`
- Using `std.fmt` → read `.../lib/std/fmt.zig`
- Using build APIs → read `.../lib/std/Build.zig`

## Build Tips

- Use `zig build --watch` for continuous rebuild on file save during development.
- In `build.zig`, prefer `run_cmd.step.dependOn(&exe.step)` over `b.getInstallStep()` for the `run` step to skip the install copy on every run.

## UI Validation — Required

**After any visual change to a widget or page, validate it in the running app using the `ui-automation` MCP tools.** Do not rely on "it compiles" — always confirm the rendered output looks correct.

### Workflow

1. Launch the app: `zig build run` (use `Start-Process` so it runs in the background)
2. Wait ~3s for the window to appear: `mcp__ui-automation__wait { seconds: 3 }`
3. Focus and screenshot: `mcp__ui-automation__get_page_state { window_title: "zui" }`
4. Navigate to the relevant page with: `mcp__ui-automation__click_element { window_title: "zui", element_name: "Controls" }`
5. Compare to WPF UI Gallery as the visual reference: `mcp__ui-automation__screenshot_window { title: "WPF UI Gallery" }`

### Key tools

| Tool | When to use |
|------|-------------|
| `get_page_state` | Full visual + UIA dump in one call — use this first |
| `click_element` | Navigate by element name, no coordinates needed |
| `click_and_screenshot` | Click + immediate screenshot, fastest for navigation |
| `screenshot_window` | Annotated=true gives screen-coordinate grid for precise clicks |
| `get_ui_elements` | Lists all interactive elements with their screen-center coords |
| `scroll_in_window` | Scroll content area without needing coordinates |

### Coordinate system

- `screenshot_window` returns **window-relative** pixels (top-left = 0,0)
- `click` takes **absolute screen** pixels
- Use `screenshot_window annotated=true` or `get_ui_elements` to get real screen coords
- Prefer `click_element` / `click_and_screenshot` over raw coords — they never drift

### Reference app

WPF UI Gallery (`WPF UI Gallery` window title) is installed and is the visual reference for Fluent/WinUI design conventions. Use it to compare widget appearance, spacing, and interaction patterns.
