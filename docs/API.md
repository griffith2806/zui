# zui API Reference

Developer and LLM reference for the zui framework. Read this instead of re-reading every source file.

---

## Package setup

zui exposes a single module named `"zui"` from `src/root.zig`.

### As a local path dependency (`build.zig.zon`)

```zig
.dependencies = .{
    .zui = .{ .path = "../zui" },
},
```

### Consumer `build.zig`

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
```

`backend` option defaults to `.software`. Pass `.backend = "opengl"` to the dependency call for GPU rendering.

---

## Public API (`@import("zui")`)

```zig
// Core
zui.Application       // app init/deinit/event loop
zui.Renderer          // drawing primitives (obtained from app.renderer)
// Style
zui.Color             // RGBA color type
zui.Theme             // dark/light preset, runtime toggle
// Layout
zui.Rect              // i32 x/y, u32 width/height
zui.Point             // i32 x/y
zui.Size              // u32 width/height
zui.Margin            // u32 top/right/bottom/left
zui.BoxLayout         // vertical/horizontal, spacing, padding
zui.Direction         // .vertical | .horizontal
zui.GridLayout        // N×M grid, gap, padding
// Widgets
zui.Button            // clickable button with hover animation
zui.ButtonStyle       // bg/bg_hover/bg_press/fg/radius/pad_x/pad_y
zui.Label             // text display
zui.TextField         // text input with cursor, clipboard
zui.Container         // titled panel
zui.Checkbox          // toggle with animated checkmark
zui.Slider            // 0..1 drag input
// Signals
zui.Signal(T)         // typed comptime-verified observer
// Events
zui.Event             // union of all input events
zui.KeyCode           // keyboard keys enum
// Animation
zui.Tween             // exponential-decay lerp
```

---

## Application

```zig
pub const Config = struct {
    title:  []const u8 = "zui",
    width:  u32 = 800,
    height: u32 = 600,
};

// Init
var app = try zui.Application.init(alloc, .{
    .title = "My App", .width = 800, .height = 600,
});
defer app.deinit();

// Fields
app.window.should_close  // bool — set true to quit
app.window.width         // u32 — current client width (updated by syncSize)
app.window.height        // u32 — current client height
app.renderer             // zui.Renderer — draw calls go here

// Methods
app.pollEvent() ?Event        // drain the OS message queue; call in a while loop
app.deltaSeconds() f32        // seconds since last call, capped at 0.1s; call once per frame
app.syncSize()                // propagate resize to renderer; call after event loop, before drawing
app.present()                 // blit rendered frame to screen
app.capFps(target_fps: u32)   // sleep remainder of frame slot; call after present()
```

### Canonical main loop

```zig
pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    var app = try zui.Application.init(alloc, .{ .title = "App", .width = 800, .height = 600 });
    defer app.deinit();

    while (!app.window.should_close) {
        const dt_s = app.deltaSeconds();   // ← must be first in loop

        while (app.pollEvent()) |ev| {
            switch (ev) {
                .close     => app.window.should_close = true,
                .key_press => |k| { if (k.key == .escape) app.window.should_close = true; },
                else => {},
            }
            // forward ev to widgets here
        }

        app.syncSize();                    // ← after events, before draw
        // update W/H from app.window.width / app.window.height if you track size

        // animate widgets
        // draw widgets

        app.present();
        app.capFps(60);
    }
}
```

---

## Renderer (drawing primitives)

All coordinates: `x: i32, y: i32`; all sizes: `u32`. Clipped to window bounds.

```zig
r.clear(color: Color)
r.fillRect(rect: Rect, color: Color)
r.fillRoundRect(rect: Rect, radius: u32, color: Color)   // alpha-blended corners
r.drawText(text: []const u8, x: i32, y: i32, color: Color)           // scale 1 (≈14px)
r.drawTextScaled(text: []const u8, x: i32, y: i32, color: Color, scale: u8)
    // scale 1→14px  2→22px  3→32px  4→44px  5→60px  6→80px
    // Uses GDI Segoe UI Variable (ClearType) on Windows
r.textWidth(text: []const u8) u32
r.textWidthScaled(text: []const u8, scale: u8) u32
```

`fillRoundRect` draws a semi-transparent rounded rectangle. Call it twice (border + inset) for bordered cards:
```zig
r.fillRoundRect(rect, 8, border_color);
r.fillRoundRect(Rect.init(rect.x+1, rect.y+1, rect.width-2, rect.height-2), 7, fill_color);
```

---

## Rect

```zig
pub const Rect = struct {
    x: i32, y: i32, width: u32, height: u32,

    pub fn init(x: i32, y: i32, width: u32, height: u32) Rect
    pub fn right(self: Rect) i32          // x + width
    pub fn bottom(self: Rect) i32         // y + height
    pub fn contains(self: Rect, pt: Point) bool
};
```

**Type gotcha**: `width` and `height` are `u32`; `x` and `y` are `i32`. Use `@intCast` when computing widths from signed arithmetic.

---

## Color

```zig
pub const Color = struct {
    r: u8, g: u8, b: u8, a: u8,

    pub fn rgb(r: u8, g: u8, b: u8) Color    // a = 255
    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color
    pub fn lerp(self: Color, other: Color, t: f32) Color  // t in 0..1

    pub const white = Color.rgb(255, 255, 255);
    pub const black = Color.rgb(0, 0, 0);
    pub const transparent = Color.rgba(0, 0, 0, 0);
};
```

---

## Theme

```zig
pub const Theme = struct {
    bg: Color, fg: Color,
    btn_bg: Color, btn_hover: Color, btn_press: Color,
    input_bg: Color, input_border: Color, input_border_focused: Color, input_hint: Color,

    pub const dark:  Theme = .{ ... };
    pub const light: Theme = .{ ... };
};
```

Pass `theme` to `TextField.draw` and `Container.draw`. Use for consistent colors across widgets.

---

## Widgets

All widgets follow the same three-call pattern:

```
widget.handleEvent(ev, ...)   // in event loop
widget.update(dt_s)           // once per frame, for animations
widget.draw(r, ...)           // in draw section
```

Some widgets need `deinit(alloc)` because they allocate (Signal slots or text buffer).

---

### Button

```zig
pub const Button = struct {
    label:   []const u8,
    style:   ButtonStyle = .{},   // see ButtonStyle
    hovered: bool = false,        // read-only: set by handleEvent
    pressed: bool = false,        // read-only
    clicked: Signal(void) = .{},  // connect a slot here
    hover_t: Tween = .{},

    pub fn deinit(self: *Button, alloc: Allocator) void
    pub fn update(self: *Button, dt_s: f32) void
    pub fn draw(self: *const Button, r: *Renderer, rect: Rect) void
    pub fn handleEvent(self: *Button, event: Event, rect: Rect) bool
    pub fn preferredSize(self: *const Button, r: *const Renderer) Size
};

pub const ButtonStyle = struct {
    bg:       Color = Color.rgb(45, 45, 48),
    bg_hover: Color = Color.rgb(62, 62, 66),
    bg_press: Color = Color.rgb(28, 28, 28),
    fg:       Color = Color.white,
    radius:   u32   = 6,
    pad_x:    u32   = 16,
    pad_y:    u32   = 8,
};
```

**Signal connection**:
```zig
try btn.clicked.connect(alloc, &my_state,
    struct { fn f(p: *MyState, _: void) void { p.* = ...; } }.f);
```

`handleEvent` returns `true` on click (mouse_release inside rect). You can check the return value instead of connecting a signal for simple cases.

---

### TextField

```zig
pub const TextField = struct {
    text:    std.ArrayListUnmanaged(u8) = .empty,
    cursor:  usize = 0,
    focused: bool  = false,
    hovered: bool  = false,

    pub fn deinit(self: *TextField, alloc: Allocator) void
    pub fn draw(self: *const TextField, r: *Renderer, rect: Rect, theme: Theme) void
    pub fn handleEvent(self: *TextField, event: Event, rect: Rect, alloc: Allocator) bool
    pub fn preferredSize(_: *const TextField) Size   // returns 200×34
};
```

Handled keys: `Backspace`, `Delete`, `Left`, `Right`, `Home`, `End`, `Escape`/`Tab` (defocus), `Ctrl+A` (cursor to end), `Ctrl+C` (copy), `Ctrl+V` (paste).

**Enter key is NOT handled** — detect it in the event loop:
```zig
.key_press => |k| {
    if (k.key == .enter and field.focused and field.text.items.len > 0) {
        // submit
    }
},
```

Clear the field after submit:
```zig
field.text.clearRetainingCapacity();
field.cursor = 0;
```

Read text: `field.text.items` (`[]u8`).

---

### Checkbox

```zig
pub const Checkbox = struct {
    checked:  bool  = false,
    hovered:  bool  = false,
    label:    []const u8 = "",    // drawn to the right of the box; "" = no label
    style:    CheckboxStyle = .{},
    check_t:  Tween = .{ .speed = 12.0 },
    changed:  Signal(bool) = .{},

    pub fn deinit(self: *Checkbox, alloc: Allocator) void
    pub fn update(self: *Checkbox, dt_s: f32) void
    pub fn draw(self: *const Checkbox, r: *Renderer, x: i32, y: i32) void
    pub fn handleEvent(self: *Checkbox, event: Event, x: i32, y: i32) bool
};
```

**Coordinates** are `(x, y)` integers — not a `Rect`. The hit box is a 20×20 square at `(x, y)`.

`checked` is the authoritative state. After `handleEvent`, read `cb.checked` directly.

---

### Slider

```zig
pub const Slider = struct {
    value:   f32 = 0.0,    // 0.0 .. 1.0
    dragging: bool = false,
    style:   SliderStyle = .{},
    changed: Signal(f32) = .{},

    pub fn deinit(self: *Slider, alloc: Allocator) void
    pub fn draw(self: *const Slider, r: *Renderer, rect: Rect) void
    pub fn handleEvent(self: *Slider, event: Event, rect: Rect) bool
};
```

**Coordinates** take a `Rect` (unlike Checkbox). `value` is updated in-place by drag.

---

### Container

```zig
pub const Container = struct {
    title: []const u8 = "",

    pub fn draw(self: *const Container, r: *Renderer, rect: Rect, theme: Theme) void
    pub fn contentRect(self: *const Container, rect: Rect) Rect
        // returns rect inset by border and title bar (use this for child layout)
};
```

No event handling — Container is a visual grouping only.

---

### Label

```zig
pub const Label = struct {
    text:  []const u8,
    color: Color = Color.white,
    scale: u8    = 1,

    pub fn draw(self: *const Label, r: *Renderer, x: i32, y: i32) void
    pub fn preferredSize(self: *const Label, r: *const Renderer) Size
};
```

---

## Layouts

### BoxLayout

```zig
pub const BoxLayout = struct {
    direction: Direction = .vertical,
    spacing:   u32       = 8,
    padding:   Margin    = .{},

    pub fn compute(self: BoxLayout, bounds: Rect, sizes: []const Size, out: []Rect) void
    pub fn measure(self: BoxLayout, sizes: []const Size) Size
};

pub const Direction = enum { vertical, horizontal };
pub const Margin = struct { top: u32 = 0, right: u32 = 0, bottom: u32 = 0, left: u32 = 0 };
```

`sizes` and `out` must have the same length. Items are packed from top-left with `spacing` between them.

### GridLayout

```zig
pub const GridLayout = struct {
    cols:    u32 = 2,
    rows:    u32 = 2,
    gap:     u32 = 8,
    padding: u32 = 0,

    pub fn compute(self: GridLayout, bounds: Rect, out: []Rect) void
    pub fn measure(self: GridLayout, cell: Size) Size
};
```

`out` length must equal `cols * rows`. Cells are filled left-to-right, top-to-bottom.

---

## Signal(T)

```zig
pub fn Signal(comptime T: type) type {
    return struct {
        pub fn connect(
            self: *Self,
            alloc: Allocator,
            ctx: anytype,
            comptime func: fn(@TypeOf(ctx), T) void,
        ) !void

        pub fn emit(self: *Self, value: T) void
        pub fn deinit(self: *Self, alloc: Allocator) void
    };
}
```

`T = void` for signals with no payload (Button.clicked). Emit with `signal.emit({})`.

**Inline slot pattern** (avoids needing a named function):
```zig
try widget.signal.connect(alloc, &my_var,
    struct { fn f(p: *MyType, v: PayloadType) void { ... } }.f);
```

---

## Events

```zig
pub const Event = union(enum) {
    mouse_press:   MouseEvent,
    mouse_release: MouseEvent,
    mouse_move:    MouseMoveEvent,
    key_press:     KeyEvent,
    key_release:   KeyEvent,
    char_input:    u21,      // Unicode codepoint — use this for text input
    resize:        ResizeEvent,
    scroll:        ScrollEvent,
    close:         void,
    paint:         void,
    focus_gained:  void,
    focus_lost:    void,
};

pub const MouseEvent = struct { x: i32, y: i32, button: MouseButton, modifiers: Modifiers };
pub const MouseMoveEvent = struct { x: i32, y: i32, dx: i32, dy: i32, modifiers: Modifiers };
pub const KeyEvent = struct { key: KeyCode, modifiers: Modifiers, repeat: bool };
pub const ResizeEvent = struct { width: u32, height: u32 };
pub const ScrollEvent = struct { x: i32, y: i32, dx: f32, dy: f32 };

pub const MouseButton = enum { left, middle, right, x1, x2 };

pub const Modifiers = packed struct {
    shift: bool, ctrl: bool, alt: bool, super: bool, _pad: u4,
};
```

### KeyCode (selected)

```
a..z, @"0"..@"9"
f1..f12
up, down, left, right
enter, escape, backspace, tab, space, delete, insert
home, end, page_up, page_down
left_shift, right_shift, left_ctrl, right_ctrl, left_alt, right_alt
unknown
```

**char_input vs key_press**: Use `char_input` for typed text (handles layout, dead keys, Unicode). Use `key_press` for action keys (Enter, Escape, arrows, shortcuts).

---

## Tween (Animation)

```zig
pub const Tween = struct {
    value:  f32 = 0.0,
    target: f32 = 0.0,
    speed:  f32 = 10.0,   // higher = faster (units: 1/seconds)

    pub fn update(self: *Tween, dt_s: f32) void   // call once per frame
    pub fn set(self: *Tween, target: f32) void     // set new target
    pub fn snap(self: *Tween, v: f32) void         // jump immediately, no animation
};
```

`update` applies exponential decay: `value += (target - value) * (1 - exp(-speed * dt))`.

Typical speeds: `6` = slow (250ms), `10` = default (150ms), `18` = snappy (80ms).

---

## Zig 0.16 Gotchas

These caused bugs in this codebase — record them here to avoid repeating them.

**Signed integer division**: `i32 / comptime_int` is a compile error. Use `@divTrunc`, `@divFloor`, or `@divExact`.
```zig
// WRONG:  const half = my_i32 / 2;
const half = @divTrunc(my_i32, 2);
```

**u32↔i32 in Rect**: `Rect.width` and `.height` are `u32`; `.x` and `.y` are `i32`. Arithmetic mixing them requires explicit casts.
```zig
const right: i32 = rect.x + @as(i32, @intCast(rect.width));
```

**`std.time.milliTimestamp` does not exist in 0.16**. Use Win32 `GetTickCount64`:
```zig
extern "kernel32" fn GetTickCount64() callconv(std.builtin.CallingConvention.winapi) u64;
```

**`@memset` on `[]u32` works** — preferred over pixel loops for clear/fillRect hot paths.

**`std.process.Init` main signature**:
```zig
pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    ...
}
```

**`b.addModule` does not take `.optimize`** — optimization is determined by the artifact that imports the module.

**Write tool requires a prior Read** — the file must be read before it can be edited in this session.

---

## File layout quick reference

```
src/
  root.zig              ← public API re-exports (start here)
  main.zig              ← demo/gallery app
  core/
    app.zig             ← Application, deltaSeconds, capFps
    animation.zig       ← Tween
  widgets/
    button.zig
    label.zig
    text_field.zig
    checkbox.zig
    slider.zig
    container.zig
  layout/
    geometry.zig        ← Rect, Point, Size, Margin
    box.zig             ← BoxLayout
    grid.zig            ← GridLayout
  style/
    color.zig           ← Color
    theme.zig           ← Theme
  events/
    event.zig           ← Event, KeyCode, Modifiers
  signals/
    signal.zig          ← Signal(T)
  platform/
    win32/
      window.zig        ← Win32 window, message loop
      clipboard.zig     ← CF_UNICODETEXT get/set
      gl_context.zig    ← WGL bootstrap for OpenGL backend
  graphics/
    renderer.zig        ← comptime backend shim
    software/
      renderer.zig      ← DIB pixel buffer, GDI text
      font.zig          ← 8×8 VGA fallback font
    opengl/
      renderer.zig      ← batched quad VAO/VBO
      gl.zig            ← GL function pointer table
      font_atlas.zig    ← 768×8 R8 texture
```
