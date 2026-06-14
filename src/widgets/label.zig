const Color    = @import("../style/color.zig").Color;
const Rect     = @import("../layout/geometry.zig").Rect;
const Size     = @import("../layout/geometry.zig").Size;
const Renderer = @import("../graphics/renderer.zig").Renderer;
const font     = @import("../graphics/software/font.zig");

pub const Label = struct {
    text:  []const u8,
    color: Color = Color.white,

    pub fn draw(self: *const Label, r: *Renderer, rect: Rect) void {
        r.drawText(self.text, rect.x, rect.y, self.color);
    }

    pub fn preferredSize(self: *const Label) Size {
        return .{
            .width  = Renderer.textWidth(self.text),
            .height = font.GLYPH_H,
        };
    }
};
