const std = @import("std");
const Color = @import("color.zig").Color;

/// Maximum number of stops a gradient can hold without allocating.
pub const MAX_GRADIENT_STOPS = 8;

// ── Gradient ──────────────────────────────────────────────────────────────────

pub const GradientType = enum { linear, radial, angular, diamond };

pub const GradientStop = struct {
    position: f32 = 0.0,
    color: Color = Color.black,
};

/// A gradient paint with a fixed-capacity stop list (no allocation) and a 2x3
/// affine transform in Figma's row-major layout: `[m00 m01 m02 m10 m11 m12]`.
pub const Gradient = struct {
    kind: GradientType = .linear,
    stop_data: [MAX_GRADIENT_STOPS]GradientStop =
        [_]GradientStop{GradientStop{}} ** MAX_GRADIENT_STOPS,
    stop_count: u8 = 0,
    transform: [6]f32 = .{ 1, 0, 0, 1, 0, 0 },

    /// Copy up to MAX_GRADIENT_STOPS stops from `stops`. Extra stops are dropped.
    pub fn setStops(self: *Gradient, new_stops: []const GradientStop) void {
        const n = @min(new_stops.len, MAX_GRADIENT_STOPS);
        for (0..n) |i| self.stop_data[i] = new_stops[i];
        self.stop_count = @intCast(n);
    }

    /// The active stops (length == stop_count).
    pub fn stops(self: *const Gradient) []const GradientStop {
        return self.stop_data[0..self.stop_count];
    }
};

// ── Image paint ───────────────────────────────────────────────────────────────

/// Sample a position-sorted gradient stop list at normalized `t` (0..1),
/// clamping outside the first/last stop. Shared by every renderer backend.
pub fn sampleStops(stops: []const GradientStop, t_in: f32) Color {
    if (stops.len == 0) return Color.transparent;
    if (stops.len == 1) return stops[0].color;
    const t = std.math.clamp(t_in, 0.0, 1.0);
    if (t <= stops[0].position) return stops[0].color;
    const last = stops.len - 1;
    if (t >= stops[last].position) return stops[last].color;
    var i: usize = 1;
    while (i < stops.len and stops[i].position < t) : (i += 1) {}
    const a = stops[i - 1];
    const b = stops[i];
    const dt = b.position - a.position;
    const f = if (dt != 0) (t - a.position) / dt else 0.0;
    return a.color.lerp(b.color, f);
}

pub const ScaleMode = enum { fill, fit, crop, tile };

pub const ImagePaint = struct {
    /// Opaque handle resolved to a `graphics.Image` at render time. Style may not
    /// import graphics, so images are referenced by id here.
    image_id: u32 = 0,
    scale_mode: ScaleMode = .fill,
};

// ── Paint ─────────────────────────────────────────────────────────────────────

pub const Paint = union(enum) {
    solid: Color,
    gradient: Gradient,
    image: ImagePaint,
};

// ── Corners ───────────────────────────────────────────────────────────────────

/// Per-corner radii plus Figma's corner smoothing factor (0..1). Field order is
/// Figma's: top-left, top-right, bottom-right, bottom-left.
pub const Corners = struct {
    tl: f32 = 0,
    tr: f32 = 0,
    br: f32 = 0,
    bl: f32 = 0,
    smoothing: f32 = 0,

    pub fn uniform(r: f32) Corners {
        return .{ .tl = r, .tr = r, .br = r, .bl = r };
    }

    /// Largest of the four corner radii.
    pub fn maxRadius(self: Corners) f32 {
        return @max(@max(self.tl, self.tr), @max(self.br, self.bl));
    }
};

// ── Border / stroke ───────────────────────────────────────────────────────────

pub const StrokeAlign = enum { inside, center, outside };

pub const Border = struct {
    paint: Paint = .{ .solid = Color.black },
    width: f32 = 1,
    align_mode: StrokeAlign = .center,
    /// Per-side widths [top, right, bottom, left]; null = use `width` for all sides.
    individual: ?[4]f32 = null,
    /// Dash pattern in logical pixels; null = solid.
    dash_pattern: ?[]const f32 = null,
};

// ── Effects ───────────────────────────────────────────────────────────────────

pub const ShadowKind = enum { drop, inner };

pub const Shadow = struct {
    kind: ShadowKind = .drop,
    color: Color = Color.rgba(0, 0, 0, 64),
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    blur: f32 = 0,
    spread: f32 = 0,
    visible: bool = true,
};

/// A Figma effect: either a shadow or a blur (layer or background).
pub const Effect = union(enum) {
    shadow: Shadow,
    layer_blur: f32,
    background_blur: f32,
};

// ── Blend mode ────────────────────────────────────────────────────────────────

pub const BlendMode = enum {
    normal,
    multiply,
    screen,
    overlay,
    darken,
    lighten,
    color_dodge,
    color_burn,
    hard_light,
    soft_light,
    difference,
    exclusion,
    hue,
    saturation,
    color,
    luminosity,
};

// ── Transform ─────────────────────────────────────────────────────────────────

/// 2x3 affine transform, row-major: `[m00 m01 m02 m10 m11 m12]`.
pub const Transform = struct {
    m: [6]f32 = .{ 1, 0, 0, 1, 0, 0 },

    pub const identity = Transform{};

    pub fn rotate(degrees: f32) Transform {
        const rad = degrees * std.math.pi / 180.0;
        const c = std.math.cos(rad);
        const s = std.math.sin(rad);
        return .{ .m = .{ c, -s, 0, s, c, 0 } };
    }

    pub fn translate(x: f32, y: f32) Transform {
        return .{ .m = .{ 1, 0, x, 0, 1, y } };
    }

    pub fn scale(sx: f32, sy: f32) Transform {
        return .{ .m = .{ sx, 0, 0, 0, sy, 0 } };
    }
};

// ── Visual ────────────────────────────────────────────────────────────────────

/// The full Figma appearance of a node. Slices are caller-owned (the importer or
/// widget owns the backing storage); the empty default means "nothing".
pub const Visual = struct {
    fills: []const Paint = &.{},
    strokes: []const Border = &.{},
    effects: []const Effect = &.{},
    corners: ?Corners = null,
    blend_mode: BlendMode = .normal,
    opacity: f32 = 1.0,
    transform: Transform = Transform.identity,

    pub const empty = Visual{};
};

// ── Tests ─────────────────────────────────────────────────────────────────────

test "Paint solid holds color" {
    const p = Paint{ .solid = Color.rgb(10, 20, 30) };
    try std.testing.expectEqual(Color.rgb(10, 20, 30), p.solid);
}

test "Paint gradient holds kind and transform" {
    const p = Paint{ .gradient = .{ .kind = .radial } };
    try std.testing.expectEqual(GradientType.radial, p.gradient.kind);
    try std.testing.expectEqual(@as(f32, 1), p.gradient.transform[0]);
}

test "Gradient.setStops copies and counts" {
    var g = Gradient{};
    try std.testing.expectEqual(@as(u8, 0), g.stop_count);
    g.setStops(&.{
        .{ .position = 0.0, .color = Color.red },
        .{ .position = 1.0, .color = Color.blue },
    });
    try std.testing.expectEqual(@as(u8, 2), g.stop_count);
    try std.testing.expectEqual(@as(usize, 2), g.stops().len);
    try std.testing.expectEqual(Color.red, g.stops()[0].color);
    try std.testing.expectEqual(@as(f32, 1.0), g.stops()[1].position);
}

test "Gradient.setStops clamps to MAX_GRADIENT_STOPS" {
    var g = Gradient{};
    var many: [16]GradientStop = undefined;
    for (&many, 0..) |*s, i| s.* = .{ .position = @floatFromInt(i), .color = Color.white };
    g.setStops(&many);
    try std.testing.expectEqual(@as(u8, MAX_GRADIENT_STOPS), g.stop_count);
    try std.testing.expectEqual(@as(usize, MAX_GRADIENT_STOPS), g.stops().len);
}

test "Corners.uniform sets all four, smoothing zero" {
    const c = Corners.uniform(8);
    try std.testing.expectEqual(@as(f32, 8), c.tl);
    try std.testing.expectEqual(@as(f32, 8), c.tr);
    try std.testing.expectEqual(@as(f32, 8), c.br);
    try std.testing.expectEqual(@as(f32, 8), c.bl);
    try std.testing.expectEqual(@as(f32, 0), c.smoothing);
}

test "Border defaults" {
    const b = Border{};
    try std.testing.expectEqual(@as(f32, 1), b.width);
    try std.testing.expectEqual(StrokeAlign.center, b.align_mode);
    try std.testing.expectEqual(@as(?[4]f32, null), b.individual);
    try std.testing.expectEqual(@as(?[]const f32, null), b.dash_pattern);
}

test "Effect union variants" {
    const e1 = Effect{ .shadow = .{ .kind = .inner, .blur = 4 } };
    try std.testing.expectEqual(ShadowKind.inner, e1.shadow.kind);
    try std.testing.expectEqual(@as(f32, 4), e1.shadow.blur);

    const e2 = Effect{ .layer_blur = 12 };
    try std.testing.expectEqual(@as(f32, 12), e2.layer_blur);
}

test "Transform.identity is identity" {
    const t = Transform.identity;
    try std.testing.expectEqualSlices(f32, &.{ 1, 0, 0, 1, 0, 0 }, &t.m);
}

test "Transform.rotate 90 degrees" {
    const t = Transform.rotate(90);
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.m[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, -1), t.m[1], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), t.m[3], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), t.m[4], 1e-5);
}

test "Transform.translate and scale" {
    try std.testing.expectEqualSlices(f32, &.{ 1, 0, 5, 0, 1, 7 }, &Transform.translate(5, 7).m);
    try std.testing.expectEqualSlices(f32, &.{ 2, 0, 0, 0, 3, 0 }, &Transform.scale(2, 3).m);
}

test "Visual defaults are empty and opaque" {
    const v = Visual.empty;
    try std.testing.expectEqual(@as(usize, 0), v.fills.len);
    try std.testing.expectEqual(@as(usize, 0), v.strokes.len);
    try std.testing.expectEqual(@as(usize, 0), v.effects.len);
    try std.testing.expectEqual(@as(?Corners, null), v.corners);
    try std.testing.expectEqual(BlendMode.normal, v.blend_mode);
    try std.testing.expectEqual(@as(f32, 1.0), v.opacity);
}

test "Visual carries fills, corners and blend" {
    const fills = [_]Paint{ .{ .solid = Color.white }, .{ .gradient = .{} } };
    const v = Visual{
        .fills = &fills,
        .corners = Corners.uniform(12),
        .blend_mode = .multiply,
        .opacity = 0.5,
    };
    try std.testing.expectEqual(@as(usize, 2), v.fills.len);
    try std.testing.expectEqual(@as(f32, 12), v.corners.?.tl);
    try std.testing.expectEqual(BlendMode.multiply, v.blend_mode);
    try std.testing.expectEqual(@as(f32, 0.5), v.opacity);
}
