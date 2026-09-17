const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Corners    = @import("../style/paint.zig").Corners;
const Rect       = @import("../layout/geometry.zig").Rect;
const Size       = @import("../layout/geometry.zig").Size;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

pub const Badge = struct {
    text: []const u8,
    bg: Color = Color.rgb(0, 120, 212),
    fg: Color = Color.white,
    radius: f32 = 9,

    pub fn draw(self: *const Badge, r: *Renderer, rect: Rect) void {
        r.fillCorners(rect, Corners.uniform(self.radius), self.bg);
        const tw = r.textWidth(self.text);
        const tx = rect.x + @as(i32, @intCast((rect.width -| tw) / 2));
        const ty = rect.y + @as(i32, @intCast(rect.height / 2)) - 7;
        r.drawText(self.text, tx, ty, self.fg);
    }

    pub fn preferredSize(self: *const Badge, r: *const Renderer) Size {
        return .{ .width = r.textWidth(self.text) + 16, .height = 18 };
    }

    pub fn accessNode(self: *const Badge, rect: Rect) AccessNode {
        return .{ .role = .label, .name = self.text, .bounds = rect };
    }
};

test "Badge accessNode exposes text" {
    const badge = Badge{ .text = "New" };
    const node = badge.accessNode(Rect.init(0, 0, 40, 18));
    try std.testing.expectEqual(.label, node.role);
    try std.testing.expectEqualStrings("New", node.name);
}
