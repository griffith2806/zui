const Color      = @import("../style/color.zig").Color;
const Rect       = @import("../layout/geometry.zig").Rect;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const Event      = @import("../events/event.zig").Event;
const Signal     = @import("../signals/signal.zig").Signal;
const std        = @import("std");
const AccessNode = @import("../accessibility/node.zig").AccessNode;

pub const SliderStyle = struct {
    track_h:     u32   = 2,
    thumb_w:     u32   = 16,
    thumb_h:     u32   = 16,
    track_bg:    Color = Color.rgb(60, 60, 65),
    track_fill:  Color = Color.rgb(0, 103, 192),
    thumb_color: Color = Color.white,
    thumb_hover: Color = Color.rgb(220, 220, 255),
};

pub const Slider = struct {
    value:    f32   = 0.0,   // 0..1
    min_val:  f32   = 0.0,
    max_val:  f32   = 1.0,
    dragging: bool  = false,
    hovered:  bool  = false,
    style:    SliderStyle = .{},
    changed:  Signal(f32) = .{},

    pub fn deinit(self: *Slider, alloc: std.mem.Allocator) void {
        self.changed.deinit(alloc);
    }

    pub fn draw(self: *const Slider, r: *Renderer, rect: Rect) void {
        const cy: i32 = rect.y + @as(i32, @intCast(rect.height / 2));
        const th: u32 = self.style.track_h;

        // Track background
        r.fillRoundRect(Rect.init(rect.x, cy - @as(i32, @intCast(th / 2)), rect.width, th), th / 2, self.style.track_bg);

        // Filled portion
        const t = std.math.clamp((self.value - self.min_val) / (self.max_val - self.min_val), 0.0, 1.0);
        const fill_w: u32 = @intFromFloat(@as(f32, @floatFromInt(rect.width)) * t);
        if (fill_w > 0) {
            r.fillRoundRect(Rect.init(rect.x, cy - @as(i32, @intCast(th / 2)), fill_w, th), th / 2, self.style.track_fill);
        }

        // Thumb
        const tw: u32 = self.style.thumb_w;
        const tth: u32 = self.style.thumb_h;
        const thumb_x = rect.x + @as(i32, @intFromFloat(@as(f32, @floatFromInt(rect.width - tw)) * t));
        const thumb_y = cy - @as(i32, @intCast(tth / 2));
        const thumb_color = if (self.hovered or self.dragging) self.style.thumb_hover else self.style.thumb_color;
        r.fillRoundRect(Rect.init(thumb_x, thumb_y, tw, tth), tw / 2, Color.rgb(80, 80, 90));
        r.fillRoundRect(Rect.init(thumb_x + 1, thumb_y + 1, tw - 2, tth - 2), (tw - 2) / 2, thumb_color);
    }

    pub fn accessNode(_: *const Slider, rect: Rect, focused: bool) AccessNode {
        return .{
            .role   = .slider,
            .name   = "Slider",
            .bounds = rect,
            .state  = .{ .focused = focused },
        };
    }
    // Note: value string omitted — live percentage would require caller-supplied buffer.

    pub fn handleEvent(self: *Slider, event: Event, rect: Rect) bool {
        switch (event) {
            .mouse_move => |m| {
                self.hovered = rect.contains(.{ .x = m.x, .y = m.y });
                if (self.dragging) {
                    self.setFromX(m.x, rect);
                    return true;
                }
                return false;
            },
            .mouse_press => |m| {
                if (m.button == .left and rect.contains(.{ .x = m.x, .y = m.y })) {
                    self.dragging = true;
                    self.setFromX(m.x, rect);
                    return true;
                }
            },
            .mouse_release => |m| {
                if (self.dragging and m.button == .left) {
                    self.dragging = false;
                    return true;
                }
            },
            else => {},
        }
        return false;
    }

    fn setFromX(self: *Slider, mx: i32, rect: Rect) void {
        const tw: i32 = @intCast(self.style.thumb_w);
        const usable = rect.width - @as(u32, @intCast(tw));
        const raw = mx - rect.x - @divTrunc(tw, 2);
        const t = std.math.clamp(@as(f32, @floatFromInt(raw)) / @as(f32, @floatFromInt(usable)), 0.0, 1.0);
        self.value = self.min_val + t * (self.max_val - self.min_val);
        self.changed.emit(self.value);
    }
};
