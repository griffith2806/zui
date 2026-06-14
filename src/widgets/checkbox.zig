const Color    = @import("../style/color.zig").Color;
const Rect     = @import("../layout/geometry.zig").Rect;
const Renderer = @import("../graphics/renderer.zig").Renderer;
const Event    = @import("../events/event.zig").Event;
const Signal   = @import("../signals/signal.zig").Signal;
const Tween    = @import("../core/animation.zig").Tween;
const std      = @import("std");

pub const CheckboxStyle = struct {
    size:       u32   = 20,
    radius:     u32   = 4,
    bg:         Color = Color.rgb(40, 40, 44),
    bg_checked: Color = Color.rgb(0, 103, 192),
    fg:         Color = Color.white,
    border:     Color = Color.rgb(80, 80, 86),
};

pub const Checkbox = struct {
    checked:  bool  = false,
    hovered:  bool  = false,
    label:    []const u8 = "",
    style:    CheckboxStyle = .{},
    check_t:  Tween = .{ .speed = 12.0 },
    changed:  Signal(bool) = .{},

    pub fn deinit(self: *Checkbox, alloc: std.mem.Allocator) void {
        self.changed.deinit(alloc);
    }

    pub fn update(self: *Checkbox, dt_s: f32) void {
        self.check_t.set(if (self.checked) 1.0 else 0.0);
        self.check_t.update(dt_s);
    }

    pub fn draw(self: *const Checkbox, r: *Renderer, x: i32, y: i32) void {
        const sz: u32 = self.style.size;
        const box = Rect.init(x, y, sz, sz);

        // Box background lerps from unchecked to checked color
        const bg = self.style.bg.lerp(self.style.bg_checked, self.check_t.value);
        r.fillRoundRect(box, self.style.radius, self.style.border);
        r.fillRoundRect(Rect.init(x + 1, y + 1, sz - 2, sz - 2), self.style.radius, bg);

        // Checkmark (drawn as two filled rects forming an L)
        if (self.check_t.value > 0.05) {
            const alpha: u8 = @intFromFloat(@min(255.0, self.check_t.value * 255.0));
            const fg = Color.rgba(self.style.fg.r, self.style.fg.g, self.style.fg.b, alpha);
            const m: i32 = @intCast(sz / 2);
            // Short arm of checkmark
            r.fillRect(Rect.init(x + 3, y + m + 1, 5, 3), fg);
            // Long arm of checkmark
            r.fillRect(Rect.init(x + 6, y + m - 3, 3, 8), fg);
        }

        // Label
        if (self.label.len > 0) {
            r.drawText(self.label, x + @as(i32, @intCast(sz)) + 10, y + 2, Color.rgb(200, 200, 205));
        }
    }

    pub fn handleEvent(self: *Checkbox, event: Event, x: i32, y: i32) bool {
        const sz: u32 = self.style.size;
        const box = Rect.init(x, y, sz, sz);
        switch (event) {
            .mouse_move => |m| {
                self.hovered = box.contains(.{ .x = m.x, .y = m.y });
                return false;
            },
            .mouse_press => |m| {
                if (m.button == .left and box.contains(.{ .x = m.x, .y = m.y })) {
                    self.checked = !self.checked;
                    self.changed.emit(self.checked);
                    return true;
                }
            },
            else => {},
        }
        return false;
    }
};
