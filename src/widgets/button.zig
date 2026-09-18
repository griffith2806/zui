const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Style      = @import("../style/style.zig").Style;
const pseudo     = @import("../style/pseudo.zig");
const PseudoState      = pseudo.PseudoState;
const WidgetStylesheet = pseudo.WidgetStylesheet;
const Rect       = @import("../layout/geometry.zig").Rect;
const Size       = @import("../layout/geometry.zig").Size;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const Event      = @import("../events/event.zig").Event;
const Signal     = @import("../signals/signal.zig").Signal;
const Tween      = @import("../core/animation.zig").Tween;
const AccessNode = @import("../accessibility/node.zig").AccessNode;
const Spinner    = @import("spinner.zig").Spinner;

/// Legacy per-widget colour overrides.  Kept for backward compatibility — existing
/// code that sets `Button{ .style = myButtonStyle }` continues to compile unchanged.
pub const ButtonStyle = struct {
    bg:       Color = Color.rgb(45, 45, 48),
    bg_hover: Color = Color.rgb(62, 62, 66),
    bg_press: Color = Color.rgb(28, 28, 28),
    fg:       Color = Color.white,
    radius:   u32   = 6,
    pad_x:    u32   = 16,
    pad_y:    u32   = 8,
};

pub const Button = struct {
    label:   []const u8,
    /// Legacy colour style.  Used whenever `stylesheet` is null (the default).
    style:      ButtonStyle = .{},
    /// Optional pseudo-state stylesheet.  When non-null it takes precedence over
    /// `style` for background colour, border colour, and text colour.
    /// Set individual overrides with `button.stylesheet.setOverride(.hover, ...)`.
    stylesheet: ?WidgetStylesheet = null,
    hovered:    bool = false,
    pressed:    bool = false,
    focused:    bool = false,
    /// When true the button shows an indeterminate spinner and ignores all
    /// input (MUI-style loading). Clicks are suppressed and the accessibility
    /// node reports disabled until loading is cleared.
    loading:    bool = false,
    /// Spinner state drawn while `loading` is set. Advanced by `update`.
    spinner:    Spinner = .{},
    clicked:    Signal(void) = .{},
    hover_t:    Tween = .{},

    /// Diameter (logical px) of the loading spinner and the gap before the label.
    pub const SPINNER_SIZE: i32 = 16;
    pub const SPINNER_GAP: i32 = 8;

    pub fn deinit(self: *Button, alloc: std.mem.Allocator) void {
        self.clicked.deinit(alloc);
    }

    /// Advance hover + spinner animation.  Call once per frame with delta seconds.
    pub fn update(self: *Button, dt_s: f32) void {
        self.hover_t.set(if (self.hovered or self.pressed) 1.0 else 0.0);
        self.hover_t.update(dt_s);
        if (self.loading) self.spinner.update(dt_s);
    }

    /// Build the current PseudoState from the button's tracked interaction state.
    /// A loading button is reported as `disabled` so stylesheet resolution and
    /// any consumer agree it is inert.
    pub fn pseudoState(self: *const Button) PseudoState {
        return .{
            .hover    = self.hovered and !self.loading,
            .focus    = self.focused and !self.loading,
            .active   = self.pressed and !self.loading,
            .disabled = self.loading,
        };
    }

    pub fn draw(self: *const Button, r: *Renderer, rect: Rect) void {
        if (self.stylesheet) |*ss| {
            // --- Stylesheet path ---
            const resolved = ss.resolve(self.pseudoState());

            const bg_color = resolved.bg orelse Color.rgb(45, 45, 48);
            const fg_color = resolved.fg orelse Color.white;
            const radius   = resolved.radius orelse self.style.radius;

            r.fillRoundRect(rect, radius, bg_color);

            // 1-px border
            const brd = if (resolved.border) |bc| bc else Color.rgba(255, 255, 255, 30);
            r.fillRoundRect(rect, radius, brd);
            r.fillRoundRect(
                Rect.init(rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2),
                radius,
                bg_color,
            );

            self.drawContent(r, rect, bg_color, fg_color);
        } else {
            // --- Legacy ButtonStyle path (unchanged) ---
            const base_bg   = if (self.pressed) self.style.bg_press else self.style.bg;
            const target_bg = if (self.pressed) self.style.bg_press else self.style.bg_hover;
            const bg        = base_bg.lerp(target_bg, self.hover_t.value);

            r.fillRoundRect(rect, self.style.radius, bg);

            // 1-px border at slightly higher brightness
            const brd = Color.rgba(255, 255, 255, 30);
            r.fillRoundRect(rect, self.style.radius, brd);
            r.fillRoundRect(
                Rect.init(rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2),
                self.style.radius,
                bg,
            );

            self.drawContent(r, rect, bg, self.style.fg);
        }
    }

    /// Draw the label (dimmed) with an optional leading spinner, centred as a
    /// group. Shared by both the stylesheet and legacy colour paths.
    fn drawContent(self: *const Button, r: *Renderer, rect: Rect, bg_color: Color, fg_color: Color) void {
        const tw: i32 = @intCast(r.textWidth(self.label));
        const ty = rect.y + @as(i32, @intCast(rect.height / 2)) - 7;

        if (self.loading) {
            // Spinner + gap + label, centred together.
            const group_w = SPINNER_SIZE + SPINNER_GAP + tw;
            const gx = rect.x + @as(i32, @intCast((rect.width -| @as(u32, @intCast(group_w))) / 2));

            const spinner_rect = Rect.init(gx, rect.y + @as(i32, @intCast((rect.height -| @as(u32, @intCast(SPINNER_SIZE))) / 2)), SPINNER_SIZE, SPINNER_SIZE);
            self.spinner.draw(r, spinner_rect);

            const label_color = fg_color.lerp(bg_color, 0.45);
            r.drawText(self.label, gx + SPINNER_SIZE + SPINNER_GAP, ty, label_color);
        } else {
            const tx = rect.x + @as(i32, @intCast((rect.width -| @as(u32, @intCast(tw))) / 2));
            r.drawText(self.label, tx, ty, fg_color);
        }
    }

    pub fn preferredSize(self: *const Button, r: *const Renderer) Size {
        const loading_extra: u32 = if (self.loading) SPINNER_SIZE + SPINNER_GAP else 0;
        return .{
            .width  = r.textWidth(self.label) + self.style.pad_x * 2 + loading_extra,
            .height = 34,
        };
    }

    pub fn accessNode(self: *const Button, rect: Rect, focused: bool) AccessNode {
        return .{
            .role   = .button,
            .name   = self.label,
            .bounds = rect,
            .state  = .{ .focused = focused, .enabled = !self.loading },
        };
    }

    pub fn handleEvent(self: *Button, event: Event, rect: Rect) bool {
        if (self.loading) return false;
        switch (event) {
            .mouse_move => |m| {
                self.hovered = rect.contains(.{ .x = m.x, .y = m.y });
                return false;
            },
            .mouse_press => |m| {
                if (rect.contains(.{ .x = m.x, .y = m.y }) and m.button == .left) {
                    self.pressed = true;
                    return true;
                }
            },
            .mouse_release => |m| {
                if (self.pressed) {
                    self.pressed = false;
                    if (rect.contains(.{ .x = m.x, .y = m.y })) {
                        self.clicked.emit({});
                        return true;
                    }
                }
            },
            .focus_gained => { self.focused = true;  return false; },
            .focus_lost   => { self.focused = false; return false; },
            else => {},
        }
        return false;
    }
};

test "Button loading suppresses clicks and reports disabled" {
    var alloc_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer alloc_arena.deinit();
    const alloc = alloc_arena.allocator();

    var btn = Button{ .label = "Sign in", .loading = true };
    defer btn.deinit(alloc);

    var clicks: u32 = 0;
    _ = try btn.clicked.connect(alloc, &clicks, struct {
        fn f(p: *u32, _: void) void { p.* += 1; }
    }.f);

    const rect = Rect.init(0, 0, 100, 34);
    try std.testing.expect(!btn.handleEvent(.{ .mouse_press = .{ .x = 50, .y = 17, .button = .left } }, rect));
    try std.testing.expect(!btn.handleEvent(.{ .mouse_release = .{ .x = 50, .y = 17, .button = .left } }, rect));
    try std.testing.expectEqual(@as(u32, 0), clicks);

    const node = btn.accessNode(rect, false);
    try std.testing.expect(!node.state.enabled);

    const ps = btn.pseudoState();
    try std.testing.expect(ps.disabled);

    // A non-loading button captures the press and emits on release.
    btn.loading = false;
    _ = btn.handleEvent(.{ .mouse_press = .{ .x = 50, .y = 17, .button = .left } }, rect);
    _ = btn.handleEvent(.{ .mouse_release = .{ .x = 50, .y = 17, .button = .left } }, rect);
    try std.testing.expectEqual(@as(u32, 1), clicks);
}

test "Button update advances spinner only while loading" {
    var btn = Button{ .label = "Go" };
    const before = btn.spinner.rotation;
    btn.update(0.25);
    try std.testing.expectEqual(before, btn.spinner.rotation);

    btn.loading = true;
    btn.update(0.25);
    try std.testing.expect(btn.spinner.rotation != before);
}

test "Button preferredSize reserves room for the spinner while loading" {
    // textWidth uses the bitmap fallback (gdi_dc null), so it never touches pixels.
    var r = Renderer.init(undefined, 1, 1);
    var btn = Button{ .label = "Hello" };
    const idle = btn.preferredSize(&r);
    btn.loading = true;
    const busy = btn.preferredSize(&r);
    try std.testing.expect(busy.width > idle.width);
}
