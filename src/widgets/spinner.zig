const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Rect       = @import("../layout/geometry.zig").Rect;
const Size       = @import("../layout/geometry.zig").Size;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

/// MUI-style indeterminate spinner: a partial arc that rotates continuously.
/// Call `update` once per frame with the delta seconds; `draw` renders the
/// current arc. The segment geometry is pure (see `segmentLit`) so it is
/// unit-testable without a renderer.
pub const Spinner = struct {
    /// Arc stroke thickness in logical px.
    thickness: u32 = 2,
    /// Colour of the lit arc.
    color: Color = Color.rgb(0, 120, 212),
    /// Rotation of the arc start, in radians. Advanced by `update`.
    rotation: f32 = 0.0,
    /// Fraction of the circle the lit arc spans (0..1). 0.75 ≈ a 270° arc.
    sweep: f32 = 0.75,
    /// Number of segments the ring is split into (draw resolution).
    segments: u32 = 64,
    /// Radians per second the arc start advances.
    speed: f32 = 2.0 * std.math.pi,

    /// Advance the arc. Wraps `rotation` back into [0, 2π).
    pub fn update(self: *Spinner, dt_s: f32) void {
        if (dt_s <= 0) return;
        self.rotation += dt_s * self.speed;
        const tau = 2.0 * std.math.pi;
        while (self.rotation >= tau) self.rotation -= tau;
    }

    /// True when segment `i` (0..segments) falls inside the lit arc. Pure:
    /// no renderer or allocation.
    pub fn segmentLit(self: *const Spinner, i: u32) bool {
        const tau = 2.0 * std.math.pi;
        const n: f32 = @floatFromInt(@max(self.segments, 1));
        const angle: f32 = @as(f32, @floatFromInt(i)) / n * tau;
        var delta = angle - self.rotation;
        delta = @mod(delta, tau);
        if (delta < 0) delta += tau;
        return delta < self.sweep * tau;
    }

    pub fn draw(self: *const Spinner, r: *Renderer, rect: Rect) void {
        const w: f32 = @floatFromInt(rect.width);
        const h: f32 = @floatFromInt(rect.height);
        const cx: f32 = @as(f32, @floatFromInt(rect.x)) + w / 2.0;
        const cy: f32 = @as(f32, @floatFromInt(rect.y)) + h / 2.0;
        const thickness: f32 = @floatFromInt(self.thickness);
        const radius: f32 = @min(w, h) / 2.0 - thickness / 2.0;
        const half: f32 = thickness / 2.0;

        var i: u32 = 0;
        while (i < self.segments) : (i += 1) {
            if (!self.segmentLit(i)) continue;
            const angle: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(self.segments)) * 2.0 * std.math.pi;
            const px: f32 = cx + radius * @cos(angle);
            const py: f32 = cy + radius * @sin(angle);
            const x: i32 = @intFromFloat(@round(px - half));
            const y: i32 = @intFromFloat(@round(py - half));
            r.fillRect(Rect.init(x, y, self.thickness, self.thickness), self.color);
        }
    }

    pub fn preferredSize(_: *const Spinner) Size {
        return .{ .width = 16, .height = 16 };
    }

    pub fn accessNode(_: *const Spinner, name: []const u8, rect: Rect) AccessNode {
        return .{
            .role   = .progress_bar,
            .name   = name,
            .bounds = rect,
            .state  = .{ .enabled = false },
        };
    }
};

test "Spinner segmentLit lights a leading arc" {
    const s = Spinner{ .segments = 4, .sweep = 0.5, .rotation = 0 };
    try std.testing.expect(s.segmentLit(0));
    try std.testing.expect(s.segmentLit(1));
    try std.testing.expect(!s.segmentLit(2));
    try std.testing.expect(!s.segmentLit(3));
}

test "Spinner segmentLit wraps with rotation" {
    // Half-turn rotation moves the lit half-arc to segments 2 and 3.
    const s = Spinner{ .segments = 4, .sweep = 0.5, .rotation = std.math.pi };
    try std.testing.expect(!s.segmentLit(0));
    try std.testing.expect(!s.segmentLit(1));
    try std.testing.expect(s.segmentLit(2));
    try std.testing.expect(s.segmentLit(3));
}

test "Spinner update advances and wraps rotation" {
    var s = Spinner{ .speed = std.math.pi }; // half turn per second
    s.update(0.5); // quarter turn
    try std.testing.expectApproxEqAbs(@as(f32, std.math.pi / 2.0), s.rotation, 0.0001);
    // Advance well past a full turn; rotation must stay in [0, 2π).
    s.update(10.0);
    try std.testing.expect(s.rotation >= 0.0);
    try std.testing.expect(s.rotation < 2.0 * std.math.pi);
}

test "Spinner preferredSize is square" {
    const s = Spinner{};
    const sz = s.preferredSize();
    try std.testing.expectEqual(@as(u32, 16), sz.width);
    try std.testing.expectEqual(@as(u32, 16), sz.height);
}
