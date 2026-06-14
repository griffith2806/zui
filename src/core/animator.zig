const std = @import("std");
const Color = @import("../style/color.zig").Color;

pub const Easing = enum {
    linear,
    ease_out,    // exponential decay at rate 10 — reaches ~78% in 0.1s
    ease_in_out, // exponential decay at rate  6 — gentler start/end feel
    spring,      // critically-damped spring toward target
};

/// A single animated f32 value.
pub const Animated = struct {
    value:    f32,
    target:   f32,
    velocity: f32 = 0,    // used only by .spring
    duration: f32 = 0.15, // nominal duration (used by .linear only)
    elapsed:  f32 = 0,
    easing:   Easing = .ease_out,

    pub fn init(value: f32) Animated {
        return .{ .value = value, .target = value };
    }

    /// Change the animation target.  Restarts elapsed time for ease_* modes.
    pub fn setTarget(self: *Animated, target: f32) void {
        if (self.target == target) return;
        self.target = target;
        self.elapsed = 0;
    }

    /// Advance animation by `dt` seconds.  Returns true while still animating.
    pub fn update(self: *Animated, dt: f32) bool {
        const eps: f32 = 0.001;
        switch (self.easing) {
            .linear, .ease_out, .ease_in_out => {
                const rate: f32 = switch (self.easing) {
                    .linear     => 1.0 / self.duration,
                    .ease_out   => 10.0,
                    .ease_in_out=> 6.0,
                    else        => unreachable,
                };
                self.value += (self.target - self.value) * @min(1.0, dt * rate);
                if (@abs(self.target - self.value) < eps) {
                    self.value = self.target;
                    return false;
                }
                return true;
            },
            .spring => {
                // Critically-damped spring: stiffness=200, damping=2*sqrt(200)≈28.28
                const stiffness: f32 = 200.0;
                const damping:   f32 = 2.0 * std.math.sqrt(stiffness);
                const displacement = self.value - self.target;
                const spring_force  = -stiffness * displacement;
                const damping_force = -damping * self.velocity;
                self.velocity += (spring_force + damping_force) * dt;
                self.value    += self.velocity * dt;
                if (@abs(self.value - self.target) < eps and @abs(self.velocity) < eps) {
                    self.value    = self.target;
                    self.velocity = 0;
                    return false;
                }
                return true;
            },
        }
    }

    pub fn isSettled(self: *const Animated) bool {
        return self.value == self.target;
    }
};

/// An animated Color value — each channel is an independent Animated.
pub const AnimatedColor = struct {
    r: Animated,
    g: Animated,
    b: Animated,
    a: Animated,

    pub fn init(c: Color) AnimatedColor {
        return .{
            .r = Animated.init(@floatFromInt(c.r)),
            .g = Animated.init(@floatFromInt(c.g)),
            .b = Animated.init(@floatFromInt(c.b)),
            .a = Animated.init(@floatFromInt(c.a)),
        };
    }

    pub fn setTarget(self: *AnimatedColor, c: Color) void {
        self.r.setTarget(@floatFromInt(c.r));
        self.g.setTarget(@floatFromInt(c.g));
        self.b.setTarget(@floatFromInt(c.b));
        self.a.setTarget(@floatFromInt(c.a));
    }

    /// Returns true while any channel is still animating.
    pub fn update(self: *AnimatedColor, dt: f32) bool {
        const ra = self.r.update(dt);
        const ga = self.g.update(dt);
        const ba = self.b.update(dt);
        const aa = self.a.update(dt);
        return ra or ga or ba or aa;
    }

    pub fn current(self: *const AnimatedColor) Color {
        return .{
            .r = @intFromFloat(std.math.clamp(self.r.value, 0, 255)),
            .g = @intFromFloat(std.math.clamp(self.g.value, 0, 255)),
            .b = @intFromFloat(std.math.clamp(self.b.value, 0, 255)),
            .a = @intFromFloat(std.math.clamp(self.a.value, 0, 255)),
        };
    }
};

// ── Tests ─────────────────────────────────────────────────────────────────────

test "Animated.init is settled" {
    const a = Animated.init(42.0);
    try std.testing.expect(a.isSettled());
    try std.testing.expectEqual(@as(f32, 42.0), a.value);
    try std.testing.expectEqual(@as(f32, 42.0), a.target);
}

test "Animated.setTarget no-op when same" {
    var a = Animated.init(1.0);
    a.setTarget(1.0);
    try std.testing.expect(a.isSettled());
}

test "Animated ease_out settles after large dt" {
    var a = Animated.init(0.0);
    a.setTarget(1.0);
    // A large dt should snap the value to target
    _ = a.update(1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), a.value, 0.001);
    try std.testing.expect(a.isSettled());
}

test "Animated linear settles after large dt" {
    var a = Animated{ .value = 0, .target = 1, .easing = .linear, .duration = 0.1 };
    _ = a.update(1.0);
    try std.testing.expect(a.isSettled());
    try std.testing.expectEqual(@as(f32, 1.0), a.value);
}

test "Animated spring settles" {
    var a = Animated{ .value = 0, .target = 10, .easing = .spring };
    var settled = false;
    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        if (!a.update(0.001)) { settled = true; break; }
    }
    try std.testing.expect(settled);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), a.value, 0.001);
}

test "AnimatedColor init and current round-trip" {
    const c = Color.rgb(100, 150, 200);
    const ac = AnimatedColor.init(c);
    const out = ac.current();
    try std.testing.expectEqual(c.r, out.r);
    try std.testing.expectEqual(c.g, out.g);
    try std.testing.expectEqual(c.b, out.b);
    try std.testing.expectEqual(c.a, out.a);
}

test "AnimatedColor settles to target" {
    var ac = AnimatedColor.init(Color.black);
    ac.setTarget(Color.white);
    // advance by a large dt so all channels snap
    _ = ac.update(1.0);
    const out = ac.current();
    try std.testing.expectEqual(@as(u8, 255), out.r);
    try std.testing.expectEqual(@as(u8, 255), out.g);
    try std.testing.expectEqual(@as(u8, 255), out.b);
}
