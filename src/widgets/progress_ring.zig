const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Rect       = @import("../layout/geometry.zig").Rect;
const Size       = @import("../layout/geometry.zig").Size;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

pub const ProgressRing = struct {
    value: f32 = 0.0,
    thickness: u32 = 4,
    color: Color = Color.rgb(0, 120, 212),
    track: Color = Color.rgba(255, 255, 255, 40),

    pub fn draw(self: *const ProgressRing, r: *Renderer, rect: Rect) void {
        const SEGMENTS: u32 = 64;
        const w: f32 = @floatFromInt(rect.width);
        const h: f32 = @floatFromInt(rect.height);
        const cx: f32 = @as(f32, @floatFromInt(rect.x)) + w / 2.0;
        const cy: f32 = @as(f32, @floatFromInt(rect.y)) + h / 2.0;
        const thickness: f32 = @floatFromInt(self.thickness);
        const radius: f32 = @min(w, h) / 2.0 - thickness / 2.0;
        const half: f32 = thickness / 2.0;
        const seg: f32 = @floatFromInt(SEGMENTS);

        var i: u32 = 0;
        while (i < SEGMENTS) : (i += 1) {
            const angle: f32 = @as(f32, @floatFromInt(i)) / seg * 2.0 * std.math.pi;
            const px: f32 = cx + radius * @cos(angle);
            const py: f32 = cy + radius * @sin(angle);
            const x: i32 = @intFromFloat(@round(px - half));
            const y: i32 = @intFromFloat(@round(py - half));
            r.fillRect(Rect.init(x, y, self.thickness, self.thickness), self.track);
        }

        i = 0;
        while (i < SEGMENTS) : (i += 1) {
            if (@as(f32, @floatFromInt(i)) / seg > self.value) continue;
            const angle: f32 = @as(f32, @floatFromInt(i)) / seg * 2.0 * std.math.pi;
            const px: f32 = cx + radius * @cos(angle);
            const py: f32 = cy + radius * @sin(angle);
            const x: i32 = @intFromFloat(@round(px - half));
            const y: i32 = @intFromFloat(@round(py - half));
            r.fillRect(Rect.init(x, y, self.thickness, self.thickness), self.color);
        }
    }

    pub fn accessNode(_: *const ProgressRing, name: []const u8, rect: Rect) AccessNode {
        return .{
            .role   = .progress_bar,
            .name   = name,
            .bounds = rect,
            .state  = .{ .enabled = true },
        };
    }

    pub fn preferredSize(_: *const ProgressRing) Size {
        return .{ .width = 48, .height = 48 };
    }
};

test "ProgressRing preferredSize is square" {
    const ring = ProgressRing{};
    const s = ring.preferredSize();
    try std.testing.expectEqual(@as(u32, 48), s.width);
    try std.testing.expectEqual(@as(u32, 48), s.height);
}

test "ProgressRing accessNode is a progress bar" {
    const ring = ProgressRing{ .value = 0.5 };
    const node = ring.accessNode("Loading", Rect.init(0, 0, 48, 48));
    try std.testing.expectEqual(.progress_bar, node.role);
    try std.testing.expectEqualStrings("Loading", node.name);
}
