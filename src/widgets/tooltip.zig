const std      = @import("std");
const Color    = @import("../style/color.zig").Color;
const Rect     = @import("../layout/geometry.zig").Rect;
const Renderer = @import("../graphics/renderer.zig").Renderer;

pub const Tooltip = struct {
    text:     []const u8 = "",
    delay_s:  f32        = 0.5,
    hover_ms: f32        = 0.0,
    visible:  bool       = false,
    pad:      u32        = 8,
    bg:       Color      = Color.rgb(50, 50, 55),
    border:   Color      = Color.rgba(255, 255, 255, 60),
    fg:       Color      = Color.white,
    radius:   u32        = 4,

    pub fn update(self: *Tooltip, dt_s: f32, hovered: bool) void {
        if (hovered) {
            self.hover_ms += dt_s;
            if (self.hover_ms >= self.delay_s) self.visible = true;
        } else {
            self.hover_ms = 0.0;
            self.visible = false;
        }
    }

    pub fn draw(self: *const Tooltip, r: *Renderer, anchor: Rect, window_rect: Rect) void {
        if (!self.visible) return;

        const tw = r.textWidth(self.text) + self.pad * 2;
        const th: u32 = 16 + self.pad * 2;

        var x = anchor.x;
        var y = anchor.bottom() + 4;

        const tw_i = @as(i32, @intCast(tw));
        const th_i = @as(i32, @intCast(th));

        const max_x = window_rect.right() - tw_i;
        if (x > max_x) x = max_x;

        if (y + th_i > window_rect.bottom()) {
            y = anchor.y - th_i - 4;
        }

        const tip_rect = Rect.init(x, y, tw, th);

        r.fillRoundRect(tip_rect, self.radius, self.border);
        r.fillRoundRect(
            Rect.init(x + 1, y + 1, tw -| 2, th -| 2),
            self.radius,
            self.bg,
        );

        r.drawText(
            self.text,
            x + @as(i32, @intCast(self.pad)),
            y + @as(i32, @intCast(self.pad)),
            self.fg,
        );
    }
};
