const std      = @import("std");
const Color    = @import("../style/color.zig").Color;
const Rect     = @import("../layout/geometry.zig").Rect;
const Point    = @import("../layout/geometry.zig").Point;
const Renderer = @import("../graphics/renderer.zig").Renderer;
const Event    = @import("../events/event.zig").Event;
const Signal   = @import("../signals/signal.zig").Signal;

pub const DropDown = struct {
    items:    []const []const u8,
    selected: usize  = 0,
    open:     bool   = false,
    hovered:  ?usize = null,
    item_h:   u32    = 30,

    bg:       Color = Color.rgb(45, 45, 48),
    bg_hover: Color = Color.rgb(60, 60, 65),
    bg_list:  Color = Color.rgb(35, 35, 38),
    fg:       Color = Color.rgb(255, 255, 255),
    fg_dim:   Color = Color.rgb(160, 160, 168),
    accent:   Color = Color.rgb(0, 103, 192),
    border:   Color = Color.rgba(255, 255, 255, 30),

    changed: Signal(usize) = .{},

    pub fn deinit(self: *DropDown, alloc: std.mem.Allocator) void {
        self.changed.deinit(alloc);
    }

    pub fn draw(self: *const DropDown, r: *Renderer, rect: Rect) void {
        // Button background + border (same technique as Button widget)
        r.fillRoundRect(rect, 4, self.bg);
        r.fillRoundRect(rect, 4, self.border);
        r.fillRoundRect(Rect.init(rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2), 4, self.bg);

        // Selected item label
        if (self.selected < self.items.len) {
            const ty = rect.y + @as(i32, @intCast(rect.height / 2)) - 7;
            r.drawText(self.items[self.selected], rect.x + 10, ty, self.fg);
        }

        // Chevron indicator
        const chev_x = rect.x + @as(i32, @intCast(rect.width)) - 20;
        const chev_y = rect.y + @as(i32, @intCast(rect.height / 2)) - 7;
        r.drawText("v", chev_x, chev_y, self.fg_dim);

        if (!self.open) return;

        // Dropdown list
        const list_h = @as(u32, @intCast(self.items.len)) * self.item_h;
        const list_rect = Rect.init(rect.x, rect.bottom(), rect.width, list_h);

        // List background + border
        r.fillRoundRect(list_rect, 4, self.bg_list);
        r.fillRoundRect(list_rect, 4, self.border);
        r.fillRoundRect(Rect.init(list_rect.x + 1, list_rect.y + 1, list_rect.width - 2, list_rect.height - 2), 4, self.bg_list);

        for (self.items, 0..) |item, i| {
            const iy = list_rect.y + @as(i32, @intCast(i * self.item_h));
            const item_rect = Rect.init(list_rect.x + 1, iy, list_rect.width - 2, self.item_h);

            if (i == self.selected) {
                r.fillRect(item_rect, self.accent);
            } else if (self.hovered != null and self.hovered.? == i) {
                r.fillRect(item_rect, self.bg_hover);
            }

            const text_y = iy + @as(i32, @intCast(self.item_h / 2)) - 7;
            r.drawText(item, item_rect.x + 10, text_y, self.fg);
        }
    }

    pub fn handleEvent(self: *DropDown, event: Event, rect: Rect) bool {
        const list_h = @as(u32, @intCast(self.items.len)) * self.item_h;
        const list_rect = Rect.init(rect.x, rect.bottom(), rect.width, list_h);

        switch (event) {
            .mouse_press => |m| {
                if (m.button != .left) return false;
                const pt = Point{ .x = m.x, .y = m.y };

                if (rect.contains(pt)) {
                    self.open = !self.open;
                    self.hovered = null;
                    return true;
                }

                if (self.open and list_rect.contains(pt)) {
                    const rel_y = m.y - list_rect.y;
                    if (rel_y >= 0) {
                        const idx = @as(usize, @intCast(rel_y)) / @as(usize, @intCast(self.item_h));
                        if (idx < self.items.len) {
                            self.selected = idx;
                            self.open = false;
                            self.changed.emit(idx);
                            return true;
                        }
                    }
                }

                // Click outside — close
                if (self.open) {
                    self.open = false;
                    return true;
                }
            },
            .mouse_move => |m| {
                if (!self.open) return false;
                const pt = Point{ .x = m.x, .y = m.y };
                if (list_rect.contains(pt)) {
                    const rel_y = m.y - list_rect.y;
                    if (rel_y >= 0) {
                        const idx = @as(usize, @intCast(rel_y)) / @as(usize, @intCast(self.item_h));
                        self.hovered = if (idx < self.items.len) idx else null;
                    }
                } else {
                    self.hovered = null;
                }
                return false;
            },
            else => {},
        }
        return false;
    }
};
