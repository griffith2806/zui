const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Rect       = @import("../layout/geometry.zig").Rect;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const Image      = @import("../graphics/image.zig").Image;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

pub const ImageView = struct {
    image: ?*const Image = null,
    alt: []const u8 = "",

    pub fn draw(self: *const ImageView, r: *Renderer, rect: Rect) void {
        if (self.image) |img| {
            r.drawImage(img, rect);
        } else {
            r.fillRect(rect, Color.rgb(45, 45, 48));
        }
    }

    pub fn accessNode(self: *const ImageView, rect: Rect) AccessNode {
        return .{ .role = .image, .name = self.alt, .bounds = rect };
    }
};

test "ImageView accessNode uses alt text as name" {
    const view = ImageView{ .alt = "A cat" };
    const node = view.accessNode(Rect.init(0, 0, 64, 64));
    try std.testing.expectEqual(.image, node.role);
    try std.testing.expectEqualStrings("A cat", node.name);
    try std.testing.expectEqual(@as(?*const Image, null), view.image);
}
