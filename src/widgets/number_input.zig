const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Rect       = @import("../layout/geometry.zig").Rect;
const Size       = @import("../layout/geometry.zig").Size;
const Point      = @import("../layout/geometry.zig").Point;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const Event      = @import("../events/event.zig").Event;
const Signal     = @import("../signals/signal.zig").Signal;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

const BG_INPUT = Color.rgb(30, 30, 32);
const ACCENT   = Color.rgb(0, 103, 192);
const FG       = Color.rgb(255, 255, 255);
const SEP      = Color.rgb(55, 55, 60);

const BTN_W: u32 = 28;

pub const NumberInput = struct {
    value:       f64  = 0,
    min:         f64  = 0,
    max:         f64  = 100,
    step:        f64  = 1,
    hovered:     bool = false,
    focused:     bool = false,
    inc_hovered: bool = false,
    dec_hovered: bool = false,
    changed: Signal(f64) = .{},

    pub fn deinit(self: *NumberInput, alloc: std.mem.Allocator) void {
        self.changed.deinit(alloc);
    }

    fn clamp(self: *NumberInput) void {
        if (self.value < self.min) self.value = self.min;
        if (self.value > self.max) self.value = self.max;
    }

    fn incRect(rect: Rect) Rect {
        return Rect.init(rect.right() - @as(i32, BTN_W), rect.y, BTN_W, rect.height);
    }

    fn decRect(rect: Rect) Rect {
        return Rect.init(rect.x, rect.y, BTN_W, rect.height);
    }

    pub fn handleEvent(self: *NumberInput, ev: Event, rect: Rect) void {
        const inc_r = incRect(rect);
        const dec_r = decRect(rect);
        switch (ev) {
            .mouse_move => |m| {
                const pt = Point{ .x = m.x, .y = m.y };
                self.hovered     = rect.contains(pt);
                self.inc_hovered = inc_r.contains(pt);
                self.dec_hovered = dec_r.contains(pt);
            },
            .mouse_press => |m| {
                if (m.button != .left) return;
                const pt = Point{ .x = m.x, .y = m.y };
                if (inc_r.contains(pt)) {
                    self.value += self.step;
                    self.clamp();
                    self.changed.emit(self.value);
                } else if (dec_r.contains(pt)) {
                    self.value -= self.step;
                    self.clamp();
                    self.changed.emit(self.value);
                } else if (rect.contains(pt)) {
                    self.focused = true;
                }
            },
            .key_press => |k| {
                if (!self.focused) return;
                switch (k.key) {
                    .up => {
                        self.value += self.step;
                        self.clamp();
                        self.changed.emit(self.value);
                    },
                    .down => {
                        self.value -= self.step;
                        self.clamp();
                        self.changed.emit(self.value);
                    },
                    else => {},
                }
            },
            .focus_lost => { self.focused = false; },
            else => {},
        }
    }

    pub fn draw(self: *const NumberInput, r: *Renderer, rect: Rect) void {
        const border = if (self.focused) ACCENT else SEP;

        // Outer border then inset background
        r.fillRoundRect(rect, 5, border);
        r.fillRoundRect(
            Rect.init(rect.x + 1, rect.y + 1, rect.width -| 2, rect.height -| 2),
            4, BG_INPUT,
        );

        // Decrement button
        const dec_r = decRect(rect);
        const dec_bg = if (self.dec_hovered) ACCENT.lerp(BG_INPUT, 0.5) else BG_INPUT;
        r.fillRoundRect(dec_r, 4, dec_bg);
        const dec_tw = r.textWidth("-");
        const dec_tx = dec_r.x + @as(i32, @intCast((dec_r.width -| dec_tw) / 2));
        const dec_ty = dec_r.y + @as(i32, @intCast(dec_r.height / 2)) - 7;
        r.drawText("-", dec_tx, dec_ty, FG);

        // Increment button
        const inc_r = incRect(rect);
        const inc_bg = if (self.inc_hovered) ACCENT.lerp(BG_INPUT, 0.5) else BG_INPUT;
        r.fillRoundRect(inc_r, 4, inc_bg);
        const inc_tw = r.textWidth("+");
        const inc_tx = inc_r.x + @as(i32, @intCast((inc_r.width -| inc_tw) / 2));
        const inc_ty = inc_r.y + @as(i32, @intCast(inc_r.height / 2)) - 7;
        r.drawText("+", inc_tx, inc_ty, FG);

        // Dividers between buttons and value area
        r.fillRect(Rect.init(dec_r.right(), rect.y, 1, rect.height), SEP);
        r.fillRect(Rect.init(inc_r.x - 1,  rect.y, 1, rect.height), SEP);

        // Value text centred in the middle area
        var buf: [32]u8 = undefined;
        const val_str: []const u8 = blk: {
            if (self.step >= 1.0) {
                break :blk std.fmt.bufPrint(&buf, "{d:.0}", .{self.value}) catch "?";
            } else {
                break :blk std.fmt.bufPrint(&buf, "{d:.2}", .{self.value}) catch "?";
            }
        };
        const mid_x = dec_r.right() + 1;
        const mid_w: i32 = inc_r.x - 1 - mid_x;
        const tw = @as(i32, @intCast(r.textWidth(val_str)));
        const tx = mid_x + @max(0, @divTrunc(mid_w - tw, 2));
        const ty = rect.y + @as(i32, @intCast(rect.height / 2)) - 7;
        r.drawText(val_str, tx, ty, FG);

        // Hover highlight
        if (self.hovered and !self.focused) {
            r.fillRoundRect(rect, 5, Color.rgba(255, 255, 255, 10));
        }
    }

    pub fn accessNode(self: *const NumberInput, rect: Rect, name: [:0]const u8) AccessNode {
        return .{
            .role   = .slider,
            .name   = name,
            .bounds = rect,
            .state  = .{ .focused = self.focused, .enabled = true },
        };
    }

    pub fn preferredSize(_: *const NumberInput) Size {
        return .{ .width = 120, .height = 34 };
    }
};
