const std      = @import("std");
const Color    = @import("../style/color.zig").Color;
const Rect     = @import("../layout/geometry.zig").Rect;
const Size     = @import("../layout/geometry.zig").Size;
const Renderer = @import("../graphics/renderer.zig").Renderer;
const Event    = @import("../events/event.zig").Event;
const Tween    = @import("../core/animation.zig").Tween;

pub const ProgressBar = struct {
    value:       f32   = 0.0,
    display_t:   Tween = .{},
    track_color: Color = Color.rgb(55, 55, 60),
    fill_color:  Color = Color.rgb(0, 103, 192),
    radius:      u32   = 3,
    height:      u32   = 6,

    pub fn setValue(self: *ProgressBar, v: f32) void {
        self.value = std.math.clamp(v, 0.0, 1.0);
        self.display_t.set(self.value);
    }

    pub fn update(self: *ProgressBar, dt_s: f32) void {
        self.display_t.update(dt_s);
    }

    pub fn draw(self: *const ProgressBar, r: *Renderer, rect: Rect) void {
        r.fillRoundRect(rect, self.radius, self.track_color);
        const fill_width = @as(u32, @intFromFloat(@as(f32, @floatFromInt(rect.width)) * self.display_t.value));
        if (fill_width > 0) {
            r.fillRoundRect(Rect.init(rect.x, rect.y, fill_width, rect.height), self.radius, self.fill_color);
        }
    }

    pub fn handleEvent(_: *ProgressBar, _: Event, _: Rect) bool {
        return false;
    }

    pub fn preferredSize(self: *const ProgressBar) Size {
        return .{ .width = 200, .height = self.height };
    }
};
