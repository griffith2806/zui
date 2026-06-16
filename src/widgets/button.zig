const std      = @import("std");
const Color    = @import("../style/color.zig").Color;
const Rect     = @import("../layout/geometry.zig").Rect;
const Size     = @import("../layout/geometry.zig").Size;
const Renderer = @import("../graphics/renderer.zig").Renderer;
const Event    = @import("../events/event.zig").Event;
const Signal   = @import("../signals/signal.zig").Signal;
const Tween    = @import("../core/animation.zig").Tween;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

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
    style:   ButtonStyle = .{},
    hovered: bool = false,
    pressed: bool = false,
    clicked: Signal(void) = .{},
    hover_t: Tween = .{},

    pub fn deinit(self: *Button, alloc: std.mem.Allocator) void {
        self.clicked.deinit(alloc);
    }

    /// Advance hover animation.  Call once per frame with delta seconds.
    pub fn update(self: *Button, dt_s: f32) void {
        self.hover_t.set(if (self.hovered or self.pressed) 1.0 else 0.0);
        self.hover_t.update(dt_s);
    }

    pub fn draw(self: *const Button, r: *Renderer, rect: Rect) void {
        // Lerp background colour based on hover/press animation
        const base_bg = if (self.pressed) self.style.bg_press else self.style.bg;
        const target_bg = if (self.pressed) self.style.bg_press else self.style.bg_hover;
        const bg = base_bg.lerp(target_bg, self.hover_t.value);

        r.fillRoundRect(rect, self.style.radius, bg);

        // 1-px border at slightly higher brightness
        const brd = Color.rgba(255, 255, 255, 30);
        r.fillRoundRect(rect, self.style.radius, brd);
        r.fillRoundRect(Rect.init(rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2), self.style.radius, bg);

        // Centered label
        const tw = r.textWidth(self.label);
        const tx = rect.x + @as(i32, @intCast((rect.width -| tw) / 2));
        const ty = rect.y + @as(i32, @intCast(rect.height / 2)) - 7;
        r.drawText(self.label, tx, ty, self.style.fg);
    }

    pub fn preferredSize(self: *const Button, r: *const Renderer) Size {
        return .{
            .width  = r.textWidth(self.label) + self.style.pad_x * 2,
            .height = 34,
        };
    }

    pub fn accessNode(self: *const Button, rect: Rect, focused: bool) AccessNode {
        return .{
            .role   = .button,
            .name   = self.label,
            .bounds = rect,
            .state  = .{ .focused = focused, .enabled = true },
        };
    }

    pub fn handleEvent(self: *Button, event: Event, rect: Rect) bool {
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
            else => {},
        }
        return false;
    }
};
