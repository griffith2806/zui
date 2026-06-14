const std      = @import("std");
const Color    = @import("../style/color.zig").Color;
const Rect     = @import("../layout/geometry.zig").Rect;
const Size     = @import("../layout/geometry.zig").Size;
const Renderer = @import("../graphics/renderer.zig").Renderer;
const Event    = @import("../events/event.zig").Event;
const Signal   = @import("../signals/signal.zig").Signal;

pub const TabView = struct {
    tabs:        []const []const u8,
    active:      usize = 0,
    hovered:     ?usize = null,
    changed:     Signal(usize) = .{},
    tab_height:  u32   = 40,
    accent:      Color = Color.rgb(0, 103, 192),
    bg:          Color = Color.rgb(28, 28, 30),
    fg_active:   Color = Color.white,
    fg_inactive: Color = Color.rgb(140, 140, 148),

    pub fn deinit(self: *TabView, alloc: std.mem.Allocator) void {
        self.changed.deinit(alloc);
    }

    pub fn draw(self: *const TabView, r: *Renderer, rect: Rect) void {
        r.fillRect(Rect.init(rect.x, rect.y, rect.width, self.tab_height), self.bg);

        const n = self.tabs.len;
        if (n == 0) return;
        const tab_w = rect.width / @as(u32, @intCast(n));

        for (self.tabs, 0..) |label, i| {
            const tx = rect.x + @as(i32, @intCast(@as(u32, @intCast(i)) * tab_w));
            const tab_rect = Rect.init(tx, rect.y, tab_w, self.tab_height);

            if (self.hovered) |h| {
                if (h == i and i != self.active) {
                    r.fillRect(tab_rect, Color.rgba(255, 255, 255, 12));
                }
            }

            const fg = if (i == self.active) self.fg_active else self.fg_inactive;
            const lw = r.textWidth(label);
            const lx = tx + @as(i32, @intCast((tab_w -| lw) / 2));
            const ly = rect.y + @as(i32, @intCast(self.tab_height / 2)) - 7;
            r.drawText(label, lx, ly, fg);

            if (i == self.active) {
                const underline_y = rect.y + @as(i32, @intCast(self.tab_height)) - 2;
                r.fillRect(Rect.init(tx, underline_y, tab_w, 2), self.accent);
            }
        }

        const divider_y = rect.y + @as(i32, @intCast(self.tab_height)) - 1;
        r.fillRect(Rect.init(rect.x, divider_y, rect.width, 1), Color.rgba(255, 255, 255, 20));
    }

    pub fn handleEvent(self: *TabView, event: Event, rect: Rect) bool {
        const n = self.tabs.len;
        if (n == 0) return false;
        const tab_w = rect.width / @as(u32, @intCast(n));

        switch (event) {
            .mouse_move => |m| {
                const bar = Rect.init(rect.x, rect.y, rect.width, self.tab_height);
                if (bar.contains(.{ .x = m.x, .y = m.y })) {
                    const rel_x = m.x - rect.x;
                    if (rel_x >= 0) {
                        self.hovered = @as(usize, @intCast(rel_x)) / @as(usize, @intCast(tab_w));
                    }
                } else {
                    self.hovered = null;
                }
                return false;
            },
            .mouse_press => |m| {
                if (m.button != .left) return false;
                const bar = Rect.init(rect.x, rect.y, rect.width, self.tab_height);
                if (bar.contains(.{ .x = m.x, .y = m.y })) {
                    const rel_x = m.x - rect.x;
                    if (rel_x >= 0) {
                        const idx = @as(usize, @intCast(rel_x)) / @as(usize, @intCast(tab_w));
                        if (idx < n) {
                            self.active = idx;
                            self.changed.emit(idx);
                            return true;
                        }
                    }
                }
            },
            else => {},
        }
        return false;
    }

    pub fn contentRect(self: *const TabView, rect: Rect) Rect {
        return Rect.init(
            rect.x,
            rect.y + @as(i32, @intCast(self.tab_height)),
            rect.width,
            rect.height -| self.tab_height,
        );
    }

    pub fn preferredSize(self: *const TabView) Size {
        return .{ .width = 0, .height = self.tab_height };
    }
};
