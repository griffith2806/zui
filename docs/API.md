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

`backend` option defaults to `.software`. Pass `-Dbackend=opengl` or `-Dbackend=vulkan` on the command line.

---

## Public API (`@import("zui")`)

```zig
// Core
zui.Application       // app init/deinit/event loop
zui.Renderer          // drawing primitives (obtained from app.renderer)
// Style
zui.Color             // RGBA color type
zui.Theme             // dark/light preset, runtime toggle
zui.Style             // per-widget style override (fg/bg/border/radius/padding/font)
zui.Stylesheet        // .zss flat CSS parser
zui.Font              // font descriptor (family/size/weight/style)
zui.PseudoState       // packed u8 bitfield: hover/focus/disabled/active/checked
zui.PseudoStateTag    // enum for indexing WidgetStylesheet overrides
zui.WidgetStylesheet  // zero-alloc base+per-pseudo-state style resolver
// Layout
zui.Rect              // i32 x/y, u32 width/height
zui.Point             // i32 x/y
zui.Size              // u32 width/height
zui.Margin            // u32 top/right/bottom/left
zui.BoxLayout         // vertical/horizontal, spacing, padding, flex factors
zui.Direction         // .vertical | .horizontal
zui.GridLayout        // N×M grid, gap, padding
zui.FlowLayout        // CSS flex-wrap: wrap equivalent
// Widgets
zui.Button            // clickable button with hover animation
zui.ButtonStyle       // bg/bg_hover/bg_press/fg/radius/pad_x/pad_y
zui.Label             // text display
zui.TextField         // single-line text input with cursor, clipboard
zui.TextArea          // multi-line text editor with undo stack
zui.Container         // titled panel
zui.Checkbox          // toggle with animated checkmark
zui.Slider            // 0..1 drag input
zui.ProgressBar       // determinate fill bar
zui.TabView           // tab strip with content switching
zui.DropDown          // popup select list
zui.ScrollArea        // scrollable viewport wrapping any child
zui.ListView          // data list with selection and keyboard nav
zui.Dialog            // modal dialog with title/OK/Cancel
zui.Menu              // popup context menu
zui.Tooltip           // 0.5s hover delay tooltip
// Signals
zui.Signal(T)         // typed comptime-verified observer
zui.Property(T)       // Signal-backed observable value with change suppression
zui.Computed(T)       // cached derived value, recomputes when source Properties change
// Events
zui.Event             // union of all input events
zui.KeyCode           // keyboard keys enum
// Animation (new — spring/easing based)
zui.Animated          // f32 spring/ease animation
zui.AnimatedColor     // per-channel RGBA animation
zui.Easing            // .linear | .ease_out | .ease_in_out | .spring
// Animation (legacy — exponential decay)
zui.Tween             // exponential-decay lerp (used internally by widgets)
// Graphics
zui.Image             // owned pixel buffer with draw/scale support
// Focus
zui.FocusManager      // Tab-key focus ring across widgets
// Builder DSL
zui.WidgetTag         // enum { button, label, text_field, checkbox, list_view, hbox, vbox }
zui.WidgetType(tag)   // comptime fn — returns the struct type for a WidgetTag
zui.ui(tag, opts)     // comptime factory — constructs a widget from a tag + anonymous opts struct
```

---

## Application

```zig
pub const Config = struct {
    title:  []const u8 = "zui",
    width:  u32 = 800,
    height: u32 = 600,
};

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

### Canonical main loop (with dirty rendering)

The dirty-rendering pattern avoids redrawing every frame when nothing has changed — critical for CPU usage. Static pages cost 0% CPU once events settle.

```zig
pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    var app = try zui.Application.init(alloc, .{ .title = "App", .width = 800, .height = 600 });
    defer app.deinit();

    var redraw_cnt: u32 = 3; // initial frames to paint before going idle

    while (!app.window.should_close) {
        const dt_s = app.deltaSeconds(); // ← must be first in loop

        var got_event = false;
        while (app.pollEvent()) |ev| {
            got_event = true;
            switch (ev) {
                .close     => app.window.should_close = true,
                .key_press => |k| { if (k.key == .escape) app.window.should_close = true; },
                else => {},
            }
            // forward ev to widgets here
        }
        if (got_event) redraw_cnt = 30; // ~0.5s grace covers hover fade-outs

        app.syncSize();

        // Keep redrawing while animations are live
        // if (my_animated_value.isSettled() == false) redraw_cnt = @max(redraw_cnt, 1);

        if (redraw_cnt > 0) {
            redraw_cnt -= 1;
            app.renderer.clear(bg_color);
            // draw widgets here
            app.present();
        }

        app.capFps(60);
    }
}
```

### Memory model

`init.arena.allocator()` is an arena that lives for the process lifetime — it never frees during the run. This is intentional: widget state, signal slots, and text buffers allocate once at init. There are no per-frame allocations. The dominant memory consumer is the pixel buffer (software renderer only): at 200% DPI on a 1920×1080 monitor, the backbuffer is ~2120×1360×4 bytes ≈ 11.5 MB. At 4K/200% DPI, expect ~33 MB for the pixel buffer alone.

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
r.drawImage(image: Image, dst: Rect) void     // nearest-neighbor scale blit
r.drawScrollbar(rect: Rect, thumb: Rect, theme: Theme) void

// Clipping (M13+)
r.setClip(rect: Rect) void   // restrict subsequent draws to rect
r.clearClip() void           // remove clip
```

`fillRoundRect` draws a semi-transparent rounded rectangle. Call it twice (border + inset) for bordered cards:
```zig
r.fillRoundRect(rect, 8, border_color);
r.fillRoundRect(Rect.init(rect.x+1, rect.y+1, rect.width-2, rect.height-2), 7, fill_color);
```

Text clipping pattern:
```zig
r.setClip(label_rect);
r.drawText(long_text, label_rect.x, label_rect.y, color);
r.clearClip();
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

Pass `theme` to widget draw calls for consistent colors. Toggle with `dark_mode = !dark_mode`.

---

## Style / Stylesheet / Font

### Style

Per-widget style override. All fields are optional — `null` means "inherit from base."

```zig
pub const Style = struct {
    fg:      ?Color  = null,
    bg:      ?Color  = null,
    border:  ?Color  = null,
    radius:  ?u32    = null,
    padding: ?u32    = null,
    font:    ?Font   = null,

    pub const empty: Style = .{};    // no-op override — merge(base, Style.empty) == base

    pub fn merge(base: Style, override: Style) Style
        // Non-null override fields win; null fields fall back to base
};
```

Usage:
```zig
const base = Style{ .bg = Color.rgb(42, 42, 48), .radius = 4 };
const over = Style{ .bg = ACCENT, .radius = 12 };
const merged = Style.merge(base, over);
// merged.bg = ACCENT, merged.radius = 12, merged.fg = null (inherited from base = null)
```

### Stylesheet

Parses a flat `.zss` file into a `Style`.

```zig
pub const Stylesheet = struct {
    style: Style,

    pub fn parse(src: []const u8) !Stylesheet
};
```

`.zss` format (one `key: value` per line, `#` comments):
```
# widget.zss
bg: #5a2d82
fg: #ffffff
border: #8040c0
radius: 10
padding: 14
```

Supported keys: `bg`, `fg`, `border` (hex `#RRGGBB` or `#RRGGBBAA`), `radius` (u32), `padding` (u32).

Usage:
```zig
const ss = try zui.Stylesheet.parse(
    \\bg: #1e1e2e
    \\fg: #cdd6f4
    \\radius: 8
);
const style = ss.style;
```

### PseudoState / WidgetStylesheet

Pseudo-state support lets widgets display different styles for `:hover`, `:focus`, `:active`, `:disabled`, and `:checked` states — with zero allocations.

#### PseudoState

A `packed struct(u8)` bitfield. Set any combination of flags; combine with a struct literal.

```zig
pub const PseudoState = packed struct(u8) {
    hover:    bool = false,
    focus:    bool = false,
    disabled: bool = false,
    active:   bool = false,
    checked:  bool = false,
    // ...

    pub fn bits(self: PseudoState) u8         // raw backing byte
    pub fn isDefault(self: PseudoState) bool  // true when all flags are clear
};

// examples
const ps = PseudoState{ .hover = true };
const ps2 = PseudoState{ .hover = true, .focus = true };
```

#### PseudoStateTag

Enum used to index into `WidgetStylesheet.overrides`. Values: `.hover`, `.focus`, `.disabled`, `.active`, `.checked`.

```zig
pub const PseudoStateTag = enum(usize) { hover, focus, disabled, active, checked };
```

#### WidgetStylesheet

Zero-allocation stack struct holding a base `Style` plus up to five per-pseudo-state overrides.

```zig
pub const WidgetStylesheet = struct {
    base:      Style                          = .{},
    overrides: [5]?Style                      = .{null} ** 5,

    pub fn setOverride(self: *WidgetStylesheet, which: PseudoStateTag, style: Style) void
    pub fn getOverride(self: *const WidgetStylesheet, which: PseudoStateTag) ?Style
    pub fn resolve(self: *const WidgetStylesheet, pseudo: PseudoState) Style
};
```

**`resolve` application order** (later wins):
```
base -> hover -> focus -> active -> disabled -> checked
```

`disabled` is applied after `hover` so a disabled widget cannot appear interactive.

Usage:
```zig
var ss = zui.WidgetStylesheet{};
ss.base = zui.Style{ .bg = zui.Color.rgb(45, 45, 48), .fg = zui.Color.white };
ss.setOverride(.hover,    zui.Style{ .bg = zui.Color.rgb(62, 62, 66) });
ss.setOverride(.active,   zui.Style{ .bg = zui.Color.rgb(28, 28, 28) });
ss.setOverride(.disabled, zui.Style{ .bg = zui.Color.rgb(20, 20, 20), .fg = zui.Color.rgb(80, 80, 80) });

var btn = zui.Button{ .label = "Click me", .stylesheet = ss };
// In the draw loop, btn.draw() automatically calls ss.resolve(btn.pseudoState())
```

#### Button pseudo-state integration

`Button` tracks `hovered`, `pressed`, and `focused` booleans and provides:

```zig
pub fn pseudoState(self: *const Button) PseudoState
    // Returns PseudoState{ .hover=hovered, .focus=focused, .active=pressed }
```

When `Button.stylesheet` is non-null, `draw()` calls `stylesheet.resolve(pseudoState())` to pick the effective style. When `stylesheet` is null (the default), the legacy `ButtonStyle` path is used unchanged — existing code needs no changes.

```zig
// Legacy style (unchanged, backward-compatible):
var btn = zui.Button{ .label = "OK", .style = .{ .bg = zui.Color.rgb(0, 120, 212) } };

// New stylesheet style:
var ss = zui.WidgetStylesheet{};
ss.base = zui.Style{ .bg = zui.Color.rgb(0, 120, 212) };
ss.setOverride(.hover, zui.Style{ .bg = zui.Color.rgb(16, 137, 229) });
var btn2 = zui.Button{ .label = "OK", .stylesheet = ss };
```

---

### Font

Descriptor for font selection. Not yet wired to the GDI renderer (renderer uses Segoe UI Variable internally); use `drawTextScaled` with a `scale` parameter to approximate size differences.

```zig
pub const Font = struct {
    family: []const u8 = "Segoe UI Variable",
    size_pt: f32       = 12.0,
    weight: Weight     = .regular,
    style:  FontStyle  = .normal,

    pub const Weight = enum { thin, light, regular, medium, semibold, bold, black };
    pub const FontStyle = enum { normal, italic };

    // Presets
    pub fn default()  Font  // 12pt regular
    pub fn heading()  Font  // 20pt semibold
    pub fn caption()  Font  // 10pt regular
    pub fn mono()     Font  // Cascadia Code 12pt regular
};
```

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
    label:      []const u8,
    style:      ButtonStyle       = .{},          // legacy colour overrides (always backward-compat)
    stylesheet: ?WidgetStylesheet = null,         // pseudo-state stylesheet; takes precedence when non-null
    hovered:    bool = false,
    pressed:    bool = false,
    focused:    bool = false,                     // set by focus_gained / focus_lost events
    clicked:    Signal(void) = .{},

    pub fn deinit(self: *Button, alloc: Allocator) void
    pub fn update(self: *Button, dt_s: f32) void
    pub fn draw(self: *const Button, r: *Renderer, rect: Rect) void
    pub fn handleEvent(self: *Button, event: Event, rect: Rect) bool  // returns true on click
    pub fn preferredSize(self: *const Button, r: *const Renderer) Size
    pub fn pseudoState(self: *const Button) PseudoState
        // Returns PseudoState{ .hover=hovered, .focus=focused, .active=pressed }
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

`handleEvent` returns `true` on click. Check the return value for simple cases instead of connecting a signal.

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

Handled keys: `Backspace`, `Delete`, `Left`, `Right`, `Home`, `End`, `Escape`/`Tab` (defocus), `Ctrl+A` (select all / cursor to end), `Ctrl+C` (copy), `Ctrl+V` (paste), `Ctrl+X` (cut).

**Enter key is NOT handled** — detect it yourself:
```zig
.key_press => |k| {
    if (k.key == .enter and field.focused and field.text.items.len > 0) {
        // submit; clear with:
        field.text.clearRetainingCapacity();
        field.cursor = 0;
    }
},
```

Read text: `field.text.items` (`[]u8`).

---

### TextArea

Multi-line editor. Handles Enter (newline), word-wrap, clipboard, and an undo stack.

```zig
pub const TextArea = struct {
    lines:       std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8)),
    cursor_line: usize = 0,
    cursor_col:  usize = 0,
    scroll_y:    i32   = 0,
    focused:     bool  = false,

    pub fn init(alloc: Allocator) !TextArea
    pub fn deinit(self: *TextArea, alloc: Allocator) void
    pub fn draw(self: *const TextArea, r: *Renderer, rect: Rect, theme: Theme) void
    pub fn handleEvent(self: *TextArea, event: Event, rect: Rect, alloc: Allocator) void
    pub fn getText(self: *const TextArea, alloc: Allocator) ![]u8   // caller frees
};
```

Handled keys: all TextField keys, plus `Enter` (newline), `Ctrl+Z` (undo), `Ctrl+A` (select all), `Ctrl+C/V/X` (clipboard).

---

### Checkbox

```zig
pub const Checkbox = struct {
    checked: bool  = false,
    hovered: bool  = false,
    label:   []const u8 = "",
    changed: Signal(bool) = .{},

    pub fn deinit(self: *Checkbox, alloc: Allocator) void
    pub fn update(self: *Checkbox, dt_s: f32) void
    pub fn draw(self: *const Checkbox, r: *Renderer, x: i32, y: i32) void
    pub fn handleEvent(self: *Checkbox, event: Event, x: i32, y: i32) bool
};
```

**Coordinates** are `(x, y)` — not a `Rect`. Hit box is a 20×20 square at `(x, y)`.

---

### Slider

```zig
pub const Slider = struct {
    value:    f32  = 0.0,   // 0.0 .. 1.0
    dragging: bool = false,
    changed:  Signal(f32) = .{},

    pub fn deinit(self: *Slider, alloc: Allocator) void
    pub fn draw(self: *const Slider, r: *Renderer, rect: Rect) void
    pub fn handleEvent(self: *Slider, event: Event, rect: Rect) bool
};
```

---

### ProgressBar

```zig
pub const ProgressBar = struct {
    value:  f32          = 0.0,    // 0.0 .. 1.0
    label:  []const u8   = "",
    color:  Color        = ACCENT,

    pub fn draw(self: *const ProgressBar, r: *Renderer, rect: Rect) void
};
```

No event handling — set `value` directly each frame.

---

### TabView

```zig
pub const TabView = struct {
    tabs:         []const []const u8,   // tab labels
    active_tab:   usize = 0,
    tab_changed:  Signal(usize) = .{},

    pub fn deinit(self: *TabView, alloc: Allocator) void
    pub fn draw(self: *const TabView, r: *Renderer, rect: Rect, theme: Theme) void
    pub fn handleEvent(self: *TabView, event: Event, rect: Rect) bool
    pub fn contentRect(self: *const TabView, rect: Rect) Rect  // area below tab strip
};
```

---

### DropDown

```zig
pub const DropDown = struct {
    items:      []const []const u8,
    selected:   usize = 0,
    open:       bool  = false,
    hovered_i:  usize = 0,
    changed:    Signal(usize) = .{},

    pub fn deinit(self: *DropDown, alloc: Allocator) void
    pub fn draw(self: *const DropDown, r: *Renderer, rect: Rect, theme: Theme) void
    pub fn handleEvent(self: *DropDown, event: Event, rect: Rect) bool
};
```

Keyboard: `Up`/`Down` move selection when open, `Enter` confirms, `Escape` closes.

---

### ScrollArea

Wraps any child draw call, providing vertical/horizontal scrollbars.

```zig
pub const ScrollArea = struct {
    scroll_x:     i32  = 0,
    scroll_y:     i32  = 0,
    content_w:    u32  = 0,   // set to actual content width before draw
    content_h:    u32  = 0,   // set to actual content height before draw

    pub fn draw(self: *ScrollArea, r: *Renderer, rect: Rect, theme: Theme,
                draw_content: fn(*Renderer, Rect) void) void
    pub fn handleEvent(self: *ScrollArea, event: Event, rect: Rect) bool
};
```

Usage pattern:
```zig
scroll.content_h = total_rows * ROW_H;
_ = scroll.handleEvent(ev, viewport_rect);
scroll.draw(&renderer, viewport_rect, theme, struct {
    fn f(r: *Renderer, content_rect: Rect) void {
        // draw content offset by content_rect.x / .y
    }
}.f);
```

---

### ListView

```zig
pub const ListView = struct {
    items:    []const []const u8,
    selected: usize = 0,
    scroll_y: i32   = 0,
    changed:  Signal(usize) = .{},

    pub fn deinit(self: *ListView, alloc: Allocator) void
    pub fn draw(self: *const ListView, r: *Renderer, rect: Rect, theme: Theme) void
    pub fn handleEvent(self: *ListView, event: Event, rect: Rect) bool
};
```

Keyboard: `Up`/`Down` move selection, `Enter` emits `changed`.

---

### Container

```zig
pub const Container = struct {
    title: []const u8 = "",

    pub fn draw(self: *const Container, r: *Renderer, rect: Rect, theme: Theme) void
    pub fn contentRect(self: *const Container, rect: Rect) Rect
};
```

No event handling — visual grouping only.

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

### Dialog

Modal dialog. Draws a semi-transparent scrim over the page.

```zig
pub const Dialog = struct {
    title:   []const u8 = "Dialog",
    message: []const u8 = "",
    open:    bool = false,
    ok:      Signal(void) = .{},
    cancel:  Signal(void) = .{},

    pub fn deinit(self: *Dialog, alloc: Allocator) void
    pub fn draw(self: *const Dialog, r: *Renderer, win_rect: Rect, theme: Theme) void
    pub fn handleEvent(self: *Dialog, event: Event, win_rect: Rect) bool
};
```

`win_rect` is the full window rect — Dialog centers itself and draws its own scrim. `Escape` triggers cancel.

---

### Menu

Popup context menu anchored to a button or point.

```zig
pub const MenuItem = struct {
    label:    []const u8,
    disabled: bool = false,
    sep:      bool = false,   // true = draw as a separator line
};

pub const Menu = struct {
    items:    []const MenuItem,
    open:     bool  = false,
    anchor:   Rect  = .{},   // set before opening (button rect)
    hovered:  usize = 0,
    selected: Signal(usize) = .{},

    pub fn deinit(self: *Menu, alloc: Allocator) void
    pub fn draw(self: *const Menu, r: *Renderer, theme: Theme) void
    pub fn handleEvent(self: *Menu, event: Event) bool
};
```

Open on button click:
```zig
if (btn.handleEvent(ev, btn_rect)) {
    menu.anchor = btn_rect;
    menu.open = true;
}
```

---

### Tooltip

```zig
pub const Tooltip = struct {
    text:      []const u8,
    delay_s:   f32  = 0.5,
    hovered:   bool = false,
    hover_t:   f32  = 0.0,   // accumulated hover time

    pub fn update(self: *Tooltip, dt_s: f32) void
    pub fn draw(self: *const Tooltip, r: *Renderer, anchor: Rect, theme: Theme) void
    pub fn handleEvent(self: *Tooltip, event: Event, rect: Rect) void
};
```

`draw` is a no-op until `hover_t >= delay_s`. Call `update` every frame regardless.

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

**Flex factors** (M13): Pass `Size{ .width = 0, .height = 0 }` for items that should stretch — the remaining space is divided among zero-size items equally.

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

### FlowLayout

Wraps children like CSS `flex-wrap: wrap`.

```zig
pub const FlowLayout = struct {
    gap_x:  u32 = 8,
    gap_y:  u32 = 8,
    padding: Margin = .{},

    pub fn compute(self: FlowLayout, bounds: Rect, sizes: []const Size, out: []Rect) void
    pub fn measure(self: FlowLayout, bounds_w: u32, sizes: []const Size) Size
};
```

Children with `width > remaining_space` wrap to the next row.

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

**Inline slot pattern**:
```zig
try widget.signal.connect(alloc, &my_var,
    struct { fn f(p: *MyType, v: PayloadType) void { ... } }.f);
```

---

## Property(T)

A Signal-backed observable value. Fires `changed` whenever the stored value transitions to a new value. Equal writes are silent no-ops.

**Equality semantics** (resolved at comptime):
- Slices (`[]T` / `[]const T`) — compared with `std.mem.eql`
- All other types — compared with `==`

**Allocation contract**: `init`/`get`/`set` never allocate. `bind` allocates one Signal slot. `deinit` frees the slot list.

```zig
pub fn Property(comptime T: type) type {
    return struct {
        value:   T,
        changed: Signal(T),  // fired on every value change

        pub fn init(initial: T) Property(T)
        pub fn deinit(self: *Property(T), alloc: Allocator) void
        pub fn get(self: *const Property(T)) T
        pub fn set(self: *Property(T), new_val: T) void   // emits changed if value differs
        pub fn bind(self: *Property(T), alloc: Allocator, target: *Property(T)) !void
        // bind: one-directional; when self changes, target.set(value) is called
    };
}
```

**Basic usage**:
```zig
var volume: Property(f32) = Property(f32).init(0.5);
defer volume.deinit(alloc);

// React to changes
_ = try volume.changed.connect(alloc, &my_slider, struct {
    fn f(s: *Slider, v: f32) void { s.value = v; }
}.f);

volume.set(0.8);  // fires changed(0.8)
volume.set(0.8);  // same value — silent, no emit
```

**One-directional binding**:
```zig
// When model.username changes, text_field_username is also updated
try model.username.bind(alloc, &text_field_username);
```

**Disconnect**:
```zig
// Remove all slots bound to a specific ctx pointer:
volume.changed.disconnect(alloc, &my_slider);
// Or save the Connection handle from connect() and use disconnectHandle()
```

---

## Computed(T)

A lazily-evaluated derived value. Holds a cached result and recomputes via a user-supplied function when any registered source `Property` changes. No automatic dependency tracking — the user wires sources manually with `addSource()`.

**Cache semantics**: The value is computed once at `init`, then cached. It is recomputed on the next `get()` call after any source emits `changed` (or after `invalidate()` is called manually).

**Allocation contract**: `init`/`get`/`invalidate` never allocate. `addSource` allocates one Signal slot per source. `deinit` frees the slot list and disconnects all source listeners.

```zig
pub fn Computed(comptime T: type) type {
    return struct {
        pub fn init(ctx: *anyopaque, compute_fn: *const fn(*anyopaque) T) Computed(T)
        pub fn deinit(self: *Computed(T), alloc: Allocator) void
        pub fn get(self: *Computed(T)) T                   // returns cached value, recomputes if dirty
        pub fn invalidate(self: *Computed(T)) void         // mark dirty; forces recompute on next get()
        pub fn addSource(
            self: *Computed(T),
            alloc: Allocator,
            source: anytype,               // *Property(S) for any S
        ) !void
    };
}
```

**Usage**:
```zig
var first: Property([]const u8) = Property([]const u8).init("Ada");
var last:  Property([]const u8) = Property([]const u8).init("Lovelace");

const Ctx = struct { first: *Property([]const u8), last: *Property([]const u8) };
var ctx = Ctx{ .first = &first, .last = &last };

var full = Computed([]const u8).init(@ptrCast(&ctx), struct {
    fn f(raw: *anyopaque) []const u8 {
        const c: *Ctx = @ptrCast(@alignCast(raw));
        return c.first.get();  // simplified; real impl joins strings
    }
}.f);
try full.addSource(alloc, &first);
try full.addSource(alloc, &last);
defer full.deinit(alloc);

_ = full.get();        // "Ada" — cached from init
first.set("Grace");
_ = full.get();        // recomputed — source change set dirty flag
```

**Notes**:
- The source type `S` does not need to match `T`.
- The `compute_fn` receives the opaque context; it reads the updated source values itself.
- For mutable external state (non-Property), call `invalidate()` manually before `get()`.

---

## Events

```zig
pub const Event = union(enum) {
    mouse_press:   MouseEvent,
    mouse_release: MouseEvent,
    mouse_move:    MouseMoveEvent,
    key_press:     KeyEvent,
    key_release:   KeyEvent,
    char_input:    u21,      // Unicode codepoint — use for text input
    resize:        ResizeEvent,
    scroll:        ScrollEvent,
    close:         void,
    paint:         void,
    focus_gained:  void,
    focus_lost:    void,
};

pub const MouseEvent     = struct { x: i32, y: i32, button: MouseButton, modifiers: Modifiers };
pub const MouseMoveEvent = struct { x: i32, y: i32, dx: i32, dy: i32, modifiers: Modifiers };
pub const KeyEvent       = struct { key: KeyCode, modifiers: Modifiers, repeat: bool };
pub const ResizeEvent    = struct { width: u32, height: u32 };
pub const ScrollEvent    = struct { x: i32, y: i32, dx: f32, dy: f32 };
pub const MouseButton    = enum { left, middle, right, x1, x2 };

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

## Animation

### Animated (spring/easing — M18)

```zig
pub const Easing = enum { linear, ease_out, ease_in_out, spring };

pub const Animated = struct {
    value:    f32    = 0.0,
    target:   f32    = 0.0,
    velocity: f32    = 0.0,     // spring only
    duration: f32    = 0.15,    // seconds (ignored by spring)
    elapsed:  f32    = 0.0,
    easing:   Easing = .ease_out,

    pub fn update(self: *Animated, dt_s: f32) void
    pub fn setTarget(self: *Animated, target: f32) void
    pub fn isSettled(self: *const Animated) bool  // true when value == target
};

pub const AnimatedColor = struct {
    r: Animated, g: Animated, b: Animated, a: Animated,

    pub fn init(color: Color) AnimatedColor
    pub fn setTarget(self: *AnimatedColor, color: Color) void
    pub fn update(self: *AnimatedColor, dt_s: f32) void
    pub fn current(self: *const AnimatedColor) Color
    pub fn isSettled(self: *const AnimatedColor) bool
};
```

Spring parameters (critically-damped): stiffness=200, damping=2√200 ≈ 28.3. Always settles without oscillation.

Usage with dirty rendering:
```zig
anim.setTarget(1.0);

// in loop:
anim.update(dt_s);
if (!anim.isSettled()) redraw_cnt = @max(redraw_cnt, 1);
```

### Tween (exponential decay — legacy)

Used internally by Button, Checkbox hover states. Prefer `Animated` for user-facing animations.

```zig
pub const Tween = struct {
    value:  f32 = 0.0,
    target: f32 = 0.0,
    speed:  f32 = 10.0,   // higher = faster (1/seconds)

    pub fn update(self: *Tween, dt_s: f32) void   // exponential decay
    pub fn set(self: *Tween, target: f32) void
    pub fn snap(self: *Tween, v: f32) void         // jump immediately
};
```

---

## Image

```zig
pub const Image = struct {
    pixels: []u32,   // ARGB packed u32
    width:  u32,
    height: u32,

    pub fn solid(alloc: Allocator, w: u32, h: u32, color: Color) !Image
    pub fn fromRaw(pixels: []u32, w: u32, h: u32) Image
    pub fn loadPng(alloc: Allocator, path: []const u8) !Image  // stub — not yet implemented
    pub fn deinit(self: *Image, alloc: Allocator) void
};
```

Draw with: `r.drawImage(image, dst_rect)` — nearest-neighbor scale.

---

## FocusManager

Manages Tab-key traversal across focusable widgets. Each widget reports `isFocusable()`.

```zig
pub const FocusManager = struct {
    focused: usize = 0,   // index into registered widget list

    pub fn register(self: *FocusManager, widget: *anyopaque) void
    pub fn handleEvent(self: *FocusManager, event: Event) void
    pub fn isFocused(self: *const FocusManager, widget: *anyopaque) bool
};
```

Draw the focus ring manually after the widget draw:
```zig
if (focus.isFocused(&my_widget)) {
    r.fillRoundRect(Rect.init(rect.x-2, rect.y-2, rect.width+4, rect.height+4), 8, ACCENT);
}
```

---

## Zig 0.16 Gotchas

These caused bugs in this codebase — record them here to avoid repeating them.

**Signed integer division**: `i32 / comptime_int` is a compile error. Use `@divTrunc`, `@divFloor`, or `@divExact`.
```zig
const half = @divTrunc(my_i32, 2);
```

**u32↔i32 in Rect**: `Rect.width` and `.height` are `u32`; `.x` and `.y` are `i32`. Arithmetic mixing them requires explicit casts.
```zig
const right: i32 = rect.x + @as(i32, @intCast(rect.width));
```

**`@min`/`@max` on mixed types**: Returns the type of the first operand. Cast before @intCast:
```zig
const fill_w: u32 = @intCast(@min(computed_w, @as(i32, @intCast(max_w))));
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

---

## Builder DSL (`zui.ui`)

`src/core/builder.zig` provides a zero-cost comptime factory for constructing
widget structs declaratively, without naming each type explicitly.

### Types

```zig
pub const WidgetTag = enum {
    button, label, text_field, checkbox, list_view, hbox, vbox,
};

pub fn WidgetType(comptime tag: WidgetTag) type { ... }  // returns the struct type
pub fn ui(comptime tag: WidgetTag, opts: anytype) WidgetType(tag) { ... }
```

All three are exported from `src/root.zig` as `zui.WidgetTag`, `zui.WidgetType`,
and `zui.ui`.

### How it works

`ui(tag, opts)` maps `tag` to the matching struct type (`Button`, `Label`,
`BoxLayout`, …) and copies matching fields from `opts`.  Unrecognised fields in
`opts` (for example a `children` key) are silently ignored.  Fields absent from
`opts` that have a struct default value are initialised to that default.

Because the mapping is resolved entirely at comptime, the generated code is
identical to writing `Button{ .label = "Click" }` by hand.

### Usage

```zig
const zui = @import("zui");

// Simple widgets
const btn = zui.ui(.button, .{ .label = "Click me" });
const lbl = zui.ui(.label,  .{ .text  = "Hello" });

// Layout containers (direction is preset automatically)
const vb = zui.ui(.vbox, .{ .spacing = 8 });
const hb = zui.ui(.hbox, .{ .spacing = 4 });

// Override ButtonStyle fields
const accent_btn = zui.ui(.button, .{
    .label = "Accent",
    .style = zui.ButtonStyle{
        .bg       = zui.Color.rgb(0, 103, 192),
        .bg_hover = zui.Color.rgb(0, 120, 215),
        .fg       = zui.Color.white,
    },
});

// DSL with ignored `children` key (for future tree construction)
const row = zui.ui(.hbox, .{
    .spacing  = 12,
    .children = .{
        zui.ui(.button, .{ .label = "A" }),
        zui.ui(.button, .{ .label = "B" }),
    },
});
// `row` is a plain BoxLayout{ .direction = .horizontal, .spacing = 12 }
// The children tuple is discarded — use BoxLayout.compute() to lay them out.
```

### Tag → type reference

| Tag          | Returned type |
|--------------|---------------|
| `.button`    | `Button`      |
| `.label`     | `Label`       |
| `.text_field`| `TextField`   |
| `.checkbox`  | `Checkbox`    |
| `.list_view` | `ListView`    |
| `.hbox`      | `BoxLayout` (`.direction = .horizontal`) |
| `.vbox`      | `BoxLayout` (`.direction = .vertical`)   |

### Required fields

Some widget types have fields with no default value that must be supplied in
`opts`:

| Tag          | Required opts field |
|--------------|---------------------|
| `.button`    | `.label: []const u8` |
| `.label`     | `.text: []const u8`  |
| `.list_view` | `.items: []const []const u8` |

Omitting a required field produces a compile-time error ("use of undefined value
here causes undefined behavior" or a missing-field initializer error).

---

## File layout quick reference

```
src/
  root.zig              ← public API re-exports (start here)
  main.zig              ← demo/gallery app
  core/
    app.zig             ← Application, deltaSeconds, capFps
    animation.zig       ← Tween (legacy exponential decay)
    animator.zig        ← Animated, AnimatedColor, Easing (spring/ease)
    focus.zig           ← FocusManager
    builder.zig         ← ui() declarative widget-tree DSL
  widgets/
    button.zig
    label.zig
    text_field.zig
    text_area.zig
    checkbox.zig
    slider.zig
    progress_bar.zig
    tab_view.zig
    dropdown.zig
    scroll_area.zig
    list_view.zig
    container.zig
    dialog.zig
    menu.zig
    tooltip.zig
  layout/
    geometry.zig        ← Rect, Point, Size, Margin
    box.zig             ← BoxLayout
    grid.zig            ← GridLayout
    flow.zig            ← FlowLayout
  style/
    color.zig           ← Color
    theme.zig           ← Theme
    style.zig           ← Style, Style.merge
    stylesheet.zig      ← Stylesheet (.zss parser)
    font.zig            ← Font descriptor + presets
  events/
    event.zig           ← Event, KeyCode, Modifiers
  signals/
    signal.zig          ← Signal(T)
    property.zig        ← Property(T) — observable value, change-suppressing set
    computed.zig        ← Computed(T) — lazily derived value from Property sources
  graphics/
    renderer.zig        ← comptime backend shim
    image.zig           ← Image type
    software/
      renderer.zig      ← DIB pixel buffer, GDI text, setClip/clearClip
    opengl/
      renderer.zig      ← batched quad VAO/VBO
      gl.zig            ← GL function pointer table
      font_atlas.zig    ← 768×8 R8 texture
    vulkan/
      renderer.zig      ← Vulkan init + push-constant pipeline (SPIR-V stubs)
  platform/
    win32/
      window.zig        ← Win32 window, message loop, DWM Mica title bar
      clipboard.zig     ← CF_UNICODETEXT get/set
      gl_context.zig    ← WGL bootstrap for OpenGL backend
    x11/
      window.zig        ← X11 backend (written M19, untested on Linux)
```
