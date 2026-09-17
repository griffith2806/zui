const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Rect       = @import("../layout/geometry.zig").Rect;
const Size       = @import("../layout/geometry.zig").Size;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

pub const Icon = struct {
    glyph: []const u8,
    scale: u32 = 1,
    color: Color = Color.white,

    pub fn draw(self: *const Icon, r: *Renderer, rect: Rect) void {
        r.drawIcon(self.glyph, rect.x, rect.y, self.color, self.scale);
    }

    pub fn preferredSize(self: *const Icon, r: *const Renderer) Size {
        return .{ .width = r.iconWidthScaled(self.glyph, self.scale), .height = 16 };
    }

    pub fn accessNode(_: *const Icon, name: []const u8, rect: Rect) AccessNode {
        return .{ .role = .image, .name = name, .bounds = rect };
    }
};

test "Icon accessNode is an image with the given name" {
    const icon = Icon{ .glyph = "\u{E713}" };
    const node = icon.accessNode("Settings", Rect.init(4, 8, 16, 16));
    try std.testing.expectEqual(.image, node.role);
    try std.testing.expectEqualStrings("Settings", node.name);
}
