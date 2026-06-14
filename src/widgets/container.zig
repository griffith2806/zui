const Color    = @import("../style/color.zig").Color;
const Theme    = @import("../style/theme.zig").Theme;
const Rect     = @import("../layout/geometry.zig").Rect;
const Size     = @import("../layout/geometry.zig").Size;
const Renderer = @import("../graphics/software/renderer.zig").Renderer;

pub const Container = struct {
    title: ?[]const u8 = null,

    pub fn draw(self: *const Container, r: *Renderer, rect: Rect, theme: Theme) void {
        r.fillRect(rect, theme.bg_panel);

        r.fillRect(Rect.init(rect.x,           rect.y,            rect.width, 1),           theme.divider);
        r.fillRect(Rect.init(rect.x,           rect.bottom() - 1, rect.width, 1),           theme.divider);
        r.fillRect(Rect.init(rect.x,           rect.y,            1,          rect.height), theme.divider);
        r.fillRect(Rect.init(rect.right() - 1, rect.y,            1,          rect.height), theme.divider);

        if (self.title) |t| {
            r.fillRect(Rect.init(rect.x, rect.y, rect.width, 20), theme.bg_header);
            r.drawText(t, rect.x + 8, rect.y + 6, theme.fg_muted);
        }
    }

    pub fn contentRect(self: *const Container, rect: Rect) Rect {
        const top_offset: i32 = if (self.title != null) 20 else 1;
        return Rect.init(rect.x + 1, rect.y + top_offset, rect.width -| 2, rect.height -| @as(u32, @intCast(top_offset + 1)));
    }

    pub fn preferredSize(_: *const Container) Size {
        return .{ .width = 200, .height = 120 };
    }
};
