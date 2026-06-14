const std = @import("std");

/// Smooth exponential-decay tween.  `speed` is "how many times per second
/// the gap halves" — speed=10 means 150 ms to reach ~78% of target.
pub const Tween = struct {
    value:  f32 = 0.0,
    target: f32 = 0.0,
    speed:  f32 = 10.0,

    pub fn update(self: *Tween, dt_s: f32) void {
        const k = 1.0 - @exp(-self.speed * dt_s);
        self.value += (self.target - self.value) * k;
    }

    pub fn set(self: *Tween, target: f32) void { self.target = target; }
    pub fn snap(self: *Tween, v: f32) void { self.value = v; self.target = v; }
};

pub fn easeOut(t: f32) f32 {
    const tc = std.math.clamp(t, 0.0, 1.0);
    return 1.0 - (1.0 - tc) * (1.0 - tc);
}
