const std      = @import("std");
const Color    = @import("../style/color.zig").Color;
const Rect     = @import("../layout/geometry.zig").Rect;
const Renderer = @import("../graphics/renderer.zig").Renderer;
const Event    = @import("../events/event.zig").Event;
const Signal   = @import("../signals/signal.zig").Signal;

pub const MenuItem = struct {
    label:     []const u8,
    enabled:   bool = true,
    separator: bool = false,
};

pub const Menu = struct {
    items:       []const MenuItem,
    open:        bool    = false,
    hovered:     ?usize  = null,
    anchor:      Rect    = Rect.init(0, 0, 0, 0),
    item_height: u32     = 32,
    sep_height:  u32     = 9,
    width:       u32     = 200,
    bg:          Color   = Color.rgb(36, 36, 38),
    bg_hover:    Color   = Color.rgba(255, 255, 255, 15),
    bg_disabled: Color   = Color.rgba(255, 255, 255, 5),
    fg:          Color   = Color.white,
    fg_disabled: Color   = Color.rgba(255, 255, 255, 60),
    border:      Color   = Color.rgba(255, 255, 255, 40),
    sep_color:   Color   = Color.rgba(255, 255, 255, 25),
    radius:      u32     = 6,
    selected:    Signal(usize) = .{},

    pub fn deinit(self: *Menu, alloc: std.mem.Allocator) void {
        self.selected.deinit(alloc);
    }

    pub fn show(self: *Menu, anchor: Rect) void {
        self.anchor  = anchor;
        self.open    = true;
        self.hovered = null;
    }

    pub fn hide(self: *Menu) void {
        self.open    = false;
        self.hovered = null;
    }

    fn totalHeight(self: *const Menu) u32 {
        var h: u32 = 8;
        for (self.items) |item| {
            h += if (item.separator) self.sep_height else self.item_height;
        }
        return h;
    }

    fn menuRect(self: *const Menu) Rect {
        return Rect.init(self.anchor.x, self.anchor.bottom(), self.width, self.totalHeight());
    }

    fn itemY(self: *const Menu, idx: usize) i32 {
        var y: i32 = 4;
        for (self.items[0..idx]) |item| {
            y += @as(i32, @intCast(if (item.separator) self.sep_height else self.item_height));
        }
        return y;
    }

    pub fn draw(self: *const Menu, r: *Renderer) void {
        if (!self.open) return;

        const mr = self.menuRect();

        r.fillRoundRect(mr, self.radius, self.border);
        r.fillRoundRect(
            Rect.init(mr.x + 1, mr.y + 1, mr.width -| 2, mr.height -| 2),
            self.radius,
            self.bg,
        );

        for (self.items, 0..) |item, i| {
            const iy_abs = mr.y + self.itemY(i);

            if (item.separator) {
                const line_y = iy_abs + @as(i32, @intCast(self.sep_height / 2));
                r.fillRect(Rect.init(mr.x + 4, line_y, self.width -| 8, 1), self.sep_color);
            } else {
                const item_r = Rect.init(mr.x + 4, iy_abs, self.width -| 8, self.item_height);

                if (self.hovered) |h| {
                    if (h == i and item.enabled) {
                        r.fillRoundRect(item_r, 4, self.bg_hover);
                    }
                }
                if (!item.enabled) {
                    r.fillRoundRect(item_r, 4, self.bg_disabled);
                }

                const fg_color = if (item.enabled) self.fg else self.fg_disabled;
                r.drawText(
                    item.label,
                    item_r.x + 8,
                    item_r.y + @as(i32, @intCast(self.item_height / 2)) - 7,
                    fg_color,
                );
            }
        }
    }

    pub fn handleEvent(self: *Menu, event: Event) bool {
        if (!self.open) return false;

        const mr = self.menuRect();

        switch (event) {
            .mouse_move => |m| {
                self.hovered = null;
                for (self.items, 0..) |item, i| {
                    if (item.separator) continue;
                    const iy_abs = mr.y + self.itemY(i);
                    const item_r = Rect.init(mr.x + 4, iy_abs, self.width -| 8, self.item_height);
                    if (item_r.contains(.{ .x = m.x, .y = m.y })) {
                        self.hovered = i;
                        break;
                    }
                }
                return true;
            },
            .mouse_press => |m| {
                if (m.button == .left) {
                    if (!mr.contains(.{ .x = m.x, .y = m.y })) {
                        self.hide();
                        return false;
                    }
                    for (self.items, 0..) |item, i| {
                        if (item.separator or !item.enabled) continue;
                        const iy_abs = mr.y + self.itemY(i);
                        const item_r = Rect.init(mr.x + 4, iy_abs, self.width -| 8, self.item_height);
                        if (item_r.contains(.{ .x = m.x, .y = m.y })) {
                            self.selected.emit(i);
                            self.hide();
                            break;
                        }
                    }
                }
                return true;
            },
            .key_press => |k| {
                switch (k.key) {
                    .escape => {
                        self.hide();
                        return true;
                    },
                    .up => {
                        self.moveHover(-1);
                        return true;
                    },
                    .down => {
                        self.moveHover(1);
                        return true;
                    },
                    else => return true,
                }
            },
            else => return false,
        }
    }

    fn moveHover(self: *Menu, dir: i32) void {
        const n = self.items.len;
        if (n == 0) return;

        var start: usize = if (dir > 0) 0 else n - 1;
        if (self.hovered) |h| {
            if (dir > 0) {
                start = if (h + 1 < n) h + 1 else 0;
            } else {
                start = if (h > 0) h - 1 else n - 1;
            }
        }

        var idx = start;
        var iterations: usize = 0;
        while (iterations < n) : (iterations += 1) {
            const item = self.items[idx];
            if (!item.separator and item.enabled) {
                self.hovered = idx;
                return;
            }
            if (dir > 0) {
                idx = if (idx + 1 < n) idx + 1 else 0;
            } else {
                idx = if (idx > 0) idx - 1 else n - 1;
            }
        }
    }
};
