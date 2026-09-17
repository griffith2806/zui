const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Corners    = @import("../style/paint.zig").Corners;
const Rect       = @import("../layout/geometry.zig").Rect;
const Size       = @import("../layout/geometry.zig").Size;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const Image      = @import("../graphics/image.zig").Image;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

pub const Avatar = struct {
    image: ?*const Image = null,
    initials: []const u8 = "",
    size: u32 = 40,
    bg: Color = Color.rgb(0, 120, 212),
    fg: Color = Color.white,

    pub fn draw(self: *const Avatar, r: *Renderer, rect: Rect) void {
        const radius: f32 = @as(f32, @floatFromInt(@min(rect.width, rect.height))) / 2.0;
        r.fillCorners(rect, Corners.uniform(radius), self.bg);
        if (self.image) |img| {
            r.setClip(rect);
            r.drawImage(img, rect);
            r.clearClip();
        } else if (self.initials.len > 0) {
            const tw = r.textWidth(self.initials);
            const tx = rect.x + @as(i32, @intCast((rect.width -| tw) / 2));
            const ty = rect.y + @as(i32, @intCast(rect.height / 2)) - 7;
            r.drawText(self.initials, tx, ty, self.fg);
        }
    }

    pub fn preferredSize(self: *const Avatar) Size {
        return .{ .width = self.size, .height = self.size };
    }

    pub fn accessNode(self: *const Avatar, name: []const u8, rect: Rect) AccessNode {
        return .{
            .role   = .image,
            .name   = if (name.len > 0) name else self.initials,
            .bounds = rect,
        };
    }
};

test "Avatar preferredSize follows size" {
    const a = Avatar{ .size = 56 };
    const s = a.preferredSize();
    try std.testing.expectEqual(@as(u32, 56), s.width);
    try std.testing.expectEqual(@as(u32, 56), s.height);
}

test "Avatar accessNode falls back to initials" {
    const a = Avatar{ .initials = "AB" };
    const node = a.accessNode("", Rect.init(0, 0, 40, 40));
    try std.testing.expectEqual(.image, node.role);
    try std.testing.expectEqualStrings("AB", node.name);
    try std.testing.expectEqualStrings("Ada", a.accessNode("Ada", Rect.init(0, 0, 40, 40)).name);
}
