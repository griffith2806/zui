const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Corners    = @import("../style/paint.zig").Corners;
const Rect       = @import("../layout/geometry.zig").Rect;
const Size       = @import("../layout/geometry.zig").Size;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const Event      = @import("../events/event.zig").Event;
const Signal     = @import("../signals/signal.zig").Signal;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

pub const TRACK_W: u32 = 40;
pub const TRACK_H: u32 = 22;

pub const Toggle = struct {
    on: bool = false,
    hovered: bool = false,
    label: []const u8 = "",
    changed: Signal(bool) = .{},
    anim: f32 = 0.0,
    track_on: Color = Color.rgb(0, 120, 212),
    track_off: Color = Color.rgb(90, 90, 96),
    knob_color: Color = Color.white,
    track_w: u32 = TRACK_W,
    track_h: u32 = TRACK_H,
    knob_pad: u32 = 2,

    pub fn deinit(self: *Toggle, alloc: std.mem.Allocator) void {
        self.changed.deinit(alloc);
    }

    pub fn update(self: *Toggle, dt_s: f32) void {
        const target: f32 = if (self.on) 1.0 else 0.0;
        self.anim += (target - self.anim) * @min(1.0, dt_s * 12.0);
    }

    pub fn draw(self: *const Toggle, r: *Renderer, x: i32, y: i32) void {
        const track = Rect.init(x, y, self.track_w, self.track_h);
        const bg = if (self.on) self.track_on else self.track_off;
        const track_radius = @as(f32, @floatFromInt(self.track_h)) / 2.0;
        r.fillCorners(track, Corners.uniform(track_radius), bg);

        const knob_d = self.track_h -| self.knob_pad * 2;
        const travel: f32 = @floatFromInt(self.track_w -| (knob_d + self.knob_pad * 2));
        const pad: i32 = @intCast(self.knob_pad);
        const knob_x = x + pad + @as(i32, @intFromFloat(self.anim * travel));
        const knob_radius = @as(f32, @floatFromInt(knob_d)) / 2.0;
        r.fillCorners(Rect.init(knob_x, y + pad, knob_d, knob_d), Corners.uniform(knob_radius), self.knob_color);

        if (self.label.len > 0) {
            r.drawText(self.label, x + @as(i32, @intCast(self.track_w)) + 8, y + 3, Color.rgb(200, 200, 205));
        }
    }

    pub fn handleEvent(self: *Toggle, event: Event, x: i32, y: i32) bool {
        const box = Rect.init(x, y, self.track_w, self.track_h);
        switch (event) {
            .mouse_move => |m| {
                self.hovered = box.contains(.{ .x = m.x, .y = m.y });
                return false;
            },
            .mouse_release => |m| {
                if (m.button == .left and box.contains(.{ .x = m.x, .y = m.y })) {
                    self.on = !self.on;
                    self.changed.emit(self.on);
                    return true;
                }
            },
            else => {},
        }
        return false;
    }

    pub fn accessNode(self: *Toggle, x: i32, y: i32) AccessNode {
        return .{
            .role   = .checkbox,
            .name   = self.label,
            .bounds = Rect.init(x, y, self.track_w, self.track_h),
            .state  = .{ .checked = self.on, .enabled = true },
            .toggle_fn = struct {
                fn f(ctx: *anyopaque) void {
                    const t: *Toggle = @ptrCast(@alignCast(ctx));
                    t.on = !t.on;
                    t.changed.emit(t.on);
                }
            }.f,
            .ctx = self,
        };
    }

    pub fn preferredSize(self: *const Toggle, r: *const Renderer) Size {
        const extra: u32 = if (self.label.len > 0) r.textWidth(self.label) + 8 else 0;
        return .{ .width = self.track_w + extra, .height = self.track_h };
    }
};

test "Toggle handleEvent flips state and emits" {
    const alloc = std.testing.allocator;
    var t = Toggle{ .label = "Wi-Fi" };
    defer t.deinit(alloc);

    var last: bool = false;
    _ = try t.changed.connect(alloc, &last, struct {
        fn f(p: *bool, v: bool) void { p.* = v; }
    }.f);

    const handled = t.handleEvent(.{ .mouse_release = .{ .x = 10, .y = 10, .button = .left } }, 0, 0);
    try std.testing.expect(handled);
    try std.testing.expect(t.on);
    try std.testing.expect(last);
}

test "Toggle update approaches target" {
    var t = Toggle{ .on = true, .anim = 0.0 };
    t.update(1.0);
    try std.testing.expect(t.anim > 0.9);
}

test "Toggle accessNode exposes checkbox state and toggle callback" {
    var t = Toggle{ .on = true, .label = "Dark mode" };
    const node = t.accessNode(4, 8);
    try std.testing.expectEqual(.checkbox, node.role);
    try std.testing.expectEqualStrings("Dark mode", node.name);
    try std.testing.expect(node.state.checked);
    try std.testing.expect(node.toggle_fn != null);
    try std.testing.expect(node.ctx != null);
}

test "Toggle custom size and colours drive preferredSize and accessNode bounds" {
    var t = Toggle{
        .track_on = Color.rgb(79, 142, 247),
        .track_off = Color.rgb(60, 60, 60),
        .knob_color = Color.rgb(240, 240, 240),
        .track_w = 28,
        .track_h = 28,
        .knob_pad = 3,
    };

    const r: *const Renderer = undefined;
    const s = t.preferredSize(r);
    try std.testing.expectEqual(@as(u32, 28), s.width);
    try std.testing.expectEqual(@as(u32, 28), s.height);

    const node = t.accessNode(5, 7);
    try std.testing.expectEqual(@as(i32, 5), node.bounds.x);
    try std.testing.expectEqual(@as(i32, 7), node.bounds.y);
    try std.testing.expectEqual(@as(u32, 28), node.bounds.width);
    try std.testing.expectEqual(@as(u32, 28), node.bounds.height);

    try std.testing.expectEqual(Color.rgb(79, 142, 247).toU32(), t.track_on.toU32());
    try std.testing.expectEqual(Color.rgb(60, 60, 60).toU32(), t.track_off.toU32());
    try std.testing.expectEqual(Color.rgb(240, 240, 240).toU32(), t.knob_color.toU32());
}
