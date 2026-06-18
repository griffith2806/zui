# zui

A Qt/WPF-inspired UI framework for Zig 0.16. Build native desktop apps with widgets, layouts, signals, and smooth animations — no hidden allocations, no runtime surprises.

```zig
const zui = @import("zui");

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    var app = try zui.Application.init(alloc, .{ .title = "Hello", .width = 400, .height = 300 });
    defer app.deinit();

    var btn = zui.Button{ .label = "Click me" };
    defer btn.deinit(alloc);
    try btn.clicked.connect(alloc, &btn, struct {
        fn f(b: *zui.Button, _: void) void { b.label = "Clicked!"; }
    }.f);

    while (!app.window.should_close) {
        const dt = app.deltaSeconds();
        while (app.pollEvent()) |ev| {
            switch (ev) {
                .close => app.window.should_close = true,
                else   => {},
            }
            _ = btn.handleEvent(ev, zui.Rect.init(150, 130, 100, 36));
        }
        app.syncSize();
        btn.update(dt);
        app.renderer.clear(zui.Color.rgb(20, 20, 22));
        btn.draw(&app.renderer, zui.Rect.init(150, 130, 100, 36));
        app.present();
        app.capFps(60);
    }
}
```

---

## Features

- **Widgets** — Button, Label, TextField, Checkbox, Slider, Container
- **Layouts** — BoxLayout (vertical/horizontal), GridLayout (N×M)
- **Signals** — typed, comptime-verified observer pattern (`Signal(T)`)
- **Animations** — exponential-decay tweens, per-widget hover fades
- **Typography** — Segoe UI Variable via GDI (ClearType, 6 size scales)
- **Theming** — dark/light presets, runtime toggle
- **Rendering** — software (DIB) or OpenGL 3.3 core, switched at compile time
- **Platform** — Win32 native (no third-party dependencies)
- **No hidden allocations** — every allocating call takes an explicit `std.mem.Allocator`

---

## Requirements

- Zig **0.16.0**
- Windows (Win32 backend; Linux/macOS backends planned)

---

## Quick start

### 1. Add as a dependency

In your `build.zig.zon`:

```zig
.dependencies = .{
    .zui = .{ .path = "../zui" },  // local path
},
```

Or from a URL once published:

```zig
.zui = .{
    .url  = "https://github.com/griffith2806/zui/archive/<commit>.tar.gz",
    .hash = "...",
},
```

### 2. Wire it into `build.zig`

```zig
const zui_dep = b.dependency("zui", .{ .target = target, .optimize = optimize });
const zui_mod = zui_dep.module("zui");

const exe = b.addExecutable(.{
    .name = "my-app",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target   = target,
        .optimize = optimize,
        .imports  = &.{ .{ .name = "zui", .module = zui_mod } },
    }),
});
b.installArtifact(exe);
```

### 3. Import and use

```zig
const zui = @import("zui");
```

Everything public is re-exported from the single `zui` import: `Application`, `Renderer`, `Color`, `Theme`, `Rect`, all widgets, all layouts, `Signal`, `Tween`, `Event`, `KeyCode`.

---

## Widgets

Every widget follows the same three-call pattern:

```zig
// 1. handle input (inside event loop)
_ = widget.handleEvent(event, rect);

// 2. advance animations (once per frame)
widget.update(dt_seconds);

// 3. draw (in the draw section)
widget.draw(&app.renderer, rect);
```

| Widget | Allocates? | Event coords |
|--------|-----------|--------------|
| `Button` | yes (`deinit`) | `Rect` |
| `TextField` | yes (`deinit`) | `Rect` |
| `Checkbox` | yes (`deinit`) | `x: i32, y: i32` |
| `Slider` | yes (`deinit`) | `Rect` |
| `Container` | no | visual only |
| `Label` | no | `x: i32, y: i32` |

Widgets that allocate store signal slots and/or a text buffer. Call `widget.deinit(alloc)` (or use `defer`) to free them.

---

## Layouts

### BoxLayout

Stacks children vertically or horizontally with spacing and padding.

```zig
const layout = zui.BoxLayout{
    .direction = .vertical,
    .spacing   = 8,
    .padding   = .{ .top = 12, .left = 12, .right = 12, .bottom = 12 },
};
const sizes = [_]zui.Size{ .{ .width = 200, .height = 34 }, .{ .width = 200, .height = 34 } };
var rects: [2]zui.Rect = undefined;
layout.compute(bounds, &sizes, &rects);
// rects[0] and rects[1] now hold the computed positions
```

### GridLayout

Fills a bounding rect with an N×M grid of equal cells.

```zig
const grid = zui.GridLayout{ .cols = 3, .rows = 1, .gap = 12 };
var cells: [3]zui.Rect = undefined;
grid.compute(bounds, &cells);
```

---

## Signals

Typed observer connections, verified at compile time. No string dispatch.

```zig
// Connect
try button.clicked.connect(alloc, &my_var,
    struct { fn f(p: *MyType, _: void) void { p.* = ...; } }.f);

// Emit (called internally by widgets)
signal.emit(value);
```

`Signal(void)` — Button clicks, toggle events  
`Signal(bool)` — Checkbox changed  
`Signal(f32)` — Slider value changed

---

## Rendering

The renderer is obtained from `app.renderer`. Drawing calls are clipped to the window.

```zig
r.clear(color)
r.fillRect(rect, color)
r.fillRoundRect(rect, radius, color)           // alpha-blended corners
r.drawText(text, x, y, color)                  // 14px Segoe UI
r.drawTextScaled(text, x, y, color, scale)     // scale 1–6 (14→80px)
r.textWidth(text) u32
r.textWidthScaled(text, scale) u32
```

### Backend

Switch the renderer at build time — no source changes needed:

```sh
zig build                       # software (default)
zig build -Dbackend=opengl      # OpenGL 3.3 core
```

---

## Build commands

```sh
zig build              # build library + demo
zig build run          # build and run the component gallery
zig build test         # run all tests
zig build -Doptimize=ReleaseFast   # production build (~900 KB, ~5% CPU)
```

---

## Project layout

```
src/
  root.zig        ← everything re-exported here
  main.zig        ← component gallery demo
  core/           ← Application, animation
  widgets/        ← Button, Label, TextField, Checkbox, Slider, Container
  layout/         ← Rect, BoxLayout, GridLayout
  style/          ← Color, Theme
  events/         ← Event, KeyCode
  signals/        ← Signal(T)
  platform/win32/ ← window, clipboard
  graphics/       ← software + OpenGL renderers
docs/
  API.md          ← full API reference (types, signatures, gotchas)
  ROADMAP.md      ← milestone history and upcoming work
```

---

## Roadmap

- ScrollArea widget
- Tab / panel switcher
- Linux (X11) backend
- macOS (Cocoa) backend
- Vulkan renderer
