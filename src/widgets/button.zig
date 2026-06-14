const std      = @import("std");
const Color    = @import("../style/color.zig").Color;
const Rect     = @import("../layout/geometry.zig").Rect;
const Size     = @import("../layout/geometry.zig").Size;
const Point    = @import("../layout/geometry.zig").Point;
const Renderer = @import("../graphics/software/renderer.zig").Renderer;
const Event    = @import("../events/event.zig").Event;
const Signal   = @import("../signals/signal.zig").Signal;
const font     = @import("../graphics/software/font.zig");

pub const ButtonStyle = struct {
    bg:       Color = Color.rgb(45, 45, 48),
    bg_hover: Color = Color.rgb(62, 62, 66),
    bg_press: Color = Color.rgb(28, 28, 28),
    fg:       Color = Color.white,
    pad_x:    u32   = 16,
    pad_y:    u32   = 8,
};

pub const Button = struct {
    label:   []const u8,
    style:   ButtonStyle = .{},
    hovered: bool = false,
    pressed: bool = false,
    clicked: Signal(void) = .{},

    pub fn deinit(self: *Button, alloc: std.mem.Allocator) void {
        self.clicked.deinit(alloc);
    }

    pub fn draw(self: *const Button, r: *Renderer, rect: Rect) void {
        const bg = if (self.pressed) self.style.bg_press
                   else if (self.hovered) self.style.bg_hover
                   else self.style.bg;
        r.fillRect(rect, bg);

        // 1-px border using a slightly lighter colour
        const border = Color.rgb(80, 80, 83);
        r.fillRect(Rect.init(rect.x, rect.y, rect.width, 1), border);
        r.fillRect(Rect.init(rect.x, rect.bottom() - 1, rect.width, 1), border);
        r.fillRect(Rect.init(rect.x, rect.y, 1, rect.height), border);
        r.fillRect(Rect.init(rect.right() - 1, rect.y, 1, rect.height), border);

        const tx = rect.x + @as(i32, @intCast(self.style.pad_x));
        const ty = rect.y + @as(i32, @intCast(self.style.pad_y));
        r.drawText(self.label, tx, ty, self.style.fg);
    }

    pub fn preferredSize(self: *const Button) Size {
        return .{
            .width  = Renderer.textWidth(self.label) + self.style.pad_x * 2,
            .height = font.GLYPH_H + self.style.pad_y * 2,
        };
    }

    /// Call each frame with the latest event and this button's bounding rect.
    /// Returns true if the event was consumed.
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
