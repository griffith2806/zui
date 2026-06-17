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
const BG_LIST  = Color.rgb(35, 35, 38);
const ACCENT   = Color.rgb(0, 103, 192);
const FG       = Color.rgb(255, 255, 255);
const FG_SEC   = Color.rgb(178, 178, 185);
const FG_TER   = Color.rgb(110, 110, 118);
const SEP      = Color.rgb(55, 55, 60);
const BORDER   = Color.rgba(255, 255, 255, 30);

const MONTHS = [12][]const u8{
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
};

// Width of each segment (day / month / year)
const DAY_W:   u32 = 60;
const MONTH_W: u32 = 100;
const YEAR_W:  u32 = 80;
const ITEM_H:  u32 = 28;

fn isLeapYear(y: u32) bool {
    return (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0);
}

fn daysInMonth(m: u32, y: u32) u32 {
    return switch (m) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11            => 30,
        2                      => if (isLeapYear(y)) 29 else 28,
        else                   => 31,
    };
}

pub const DatePicker = struct {
    day:   u32 = 1,
    month: u32 = 1,
    year:  u32 = 2024,
    focus: enum { none, day, month, year } = .none,

    day_open:   bool = false,
    month_open: bool = false,
    year_open:  bool = false,

    // Hover tracking for popup items
    day_hover:   ?u32 = null,
    month_hover: ?u32 = null,
    year_hover:  ?u32 = null,

    changed: Signal(DateValue) = .{},

    pub const DateValue = struct { day: u32, month: u32, year: u32 };

    pub fn deinit(self: *DatePicker, alloc: std.mem.Allocator) void {
        self.changed.deinit(alloc);
    }

    fn clampDay(self: *DatePicker) void {
        const max_day = daysInMonth(self.month, self.year);
        if (self.day < 1) self.day = 1;
        if (self.day > max_day) self.day = max_day;
    }

    // Segment rects derived from the widget rect
    fn dayRect(rect: Rect) Rect   { return Rect.init(rect.x, rect.y, DAY_W, rect.height); }
    fn monthRect(rect: Rect) Rect { return Rect.init(rect.x + @as(i32, DAY_W) + 1, rect.y, MONTH_W, rect.height); }
    fn yearRect(rect: Rect) Rect  { return Rect.init(rect.x + @as(i32, DAY_W + MONTH_W) + 2, rect.y, YEAR_W, rect.height); }

    // Popup rects (appear below the segment)
    fn dayPopupRect(rect: Rect) Rect {
        const dr = dayRect(rect);
        const max_day = 31;
        return Rect.init(dr.x, dr.bottom(), DAY_W, max_day * ITEM_H);
    }

    fn monthPopupRect(rect: Rect) Rect {
        const mr = monthRect(rect);
        return Rect.init(mr.x, mr.bottom(), MONTH_W, 12 * ITEM_H);
    }

    fn yearPopupRect(rect: Rect) Rect {
        const yr = yearRect(rect);
        // Show a range of 10 years centered on current
        return Rect.init(yr.x, yr.bottom(), YEAR_W, 10 * ITEM_H);
    }

    fn yearBase(self: *const DatePicker) u32 {
        return if (self.year >= 5) self.year - 5 else 0;
    }

    pub fn handleEvent(self: *DatePicker, ev: Event, rect: Rect) void {
        const dr = dayRect(rect);
        const mr = monthRect(rect);
        const yr = yearRect(rect);

        switch (ev) {
            .mouse_press => |m| {
                if (m.button != .left) return;
                const pt = Point{ .x = m.x, .y = m.y };

                // Check popups first (they are on top)
                if (self.day_open) {
                    const pop = dayPopupRect(rect);
                    if (pop.contains(pt)) {
                        const rel_y = m.y - pop.y;
                        if (rel_y >= 0) {
                            const idx = @as(u32, @intCast(@as(usize, @intCast(rel_y)) / ITEM_H));
                            const new_day = idx + 1;
                            const max_d = daysInMonth(self.month, self.year);
                            if (new_day >= 1 and new_day <= max_d) {
                                self.day = new_day;
                                self.day_open = false;
                                self.changed.emit(.{ .day = self.day, .month = self.month, .year = self.year });
                            }
                        }
                        return;
                    }
                    self.day_open = false;
                    return;
                }

                if (self.month_open) {
                    const pop = monthPopupRect(rect);
                    if (pop.contains(pt)) {
                        const rel_y = m.y - pop.y;
                        if (rel_y >= 0) {
                            const idx = @as(u32, @intCast(@as(usize, @intCast(rel_y)) / ITEM_H));
                            if (idx < 12) {
                                self.month = idx + 1;
                                self.clampDay();
                                self.month_open = false;
                                self.changed.emit(.{ .day = self.day, .month = self.month, .year = self.year });
                            }
                        }
                        return;
                    }
                    self.month_open = false;
                    return;
                }

                if (self.year_open) {
                    const pop = yearPopupRect(rect);
                    if (pop.contains(pt)) {
                        const rel_y = m.y - pop.y;
                        if (rel_y >= 0) {
                            const idx = @as(u32, @intCast(@as(usize, @intCast(rel_y)) / ITEM_H));
                            if (idx < 10) {
                                self.year = self.yearBase() + idx;
                                self.clampDay();
                                self.year_open = false;
                                self.changed.emit(.{ .day = self.day, .month = self.month, .year = self.year });
                            }
                        }
                        return;
                    }
                    self.year_open = false;
                    return;
                }

                // Click on segment headers
                if (dr.contains(pt)) {
                    self.day_open   = !self.day_open;
                    self.month_open = false;
                    self.year_open  = false;
                    self.focus      = .day;
                } else if (mr.contains(pt)) {
                    self.month_open = !self.month_open;
                    self.day_open   = false;
                    self.year_open  = false;
                    self.focus      = .month;
                } else if (yr.contains(pt)) {
                    self.year_open  = !self.year_open;
                    self.day_open   = false;
                    self.month_open = false;
                    self.focus      = .year;
                } else {
                    self.day_open   = false;
                    self.month_open = false;
                    self.year_open  = false;
                    self.focus      = .none;
                }
            },
            .mouse_move => |m| {
                const pt = Point{ .x = m.x, .y = m.y };

                if (self.day_open) {
                    const pop = dayPopupRect(rect);
                    if (pop.contains(pt)) {
                        const rel_y = m.y - pop.y;
                        if (rel_y >= 0) {
                            self.day_hover = @intCast(@as(usize, @intCast(rel_y)) / ITEM_H);
                        }
                    } else self.day_hover = null;
                }

                if (self.month_open) {
                    const pop = monthPopupRect(rect);
                    if (pop.contains(pt)) {
                        const rel_y = m.y - pop.y;
                        if (rel_y >= 0) {
                            self.month_hover = @intCast(@as(usize, @intCast(rel_y)) / ITEM_H);
                        }
                    } else self.month_hover = null;
                }

                if (self.year_open) {
                    const pop = yearPopupRect(rect);
                    if (pop.contains(pt)) {
                        const rel_y = m.y - pop.y;
                        if (rel_y >= 0) {
                            self.year_hover = @intCast(@as(usize, @intCast(rel_y)) / ITEM_H);
                        }
                    } else self.year_hover = null;
                }
            },
            else => {},
        }
    }

    pub fn draw(self: *const DatePicker, r: *Renderer, rect: Rect) void {
        const dr = dayRect(rect);
        const mr = monthRect(rect);
        const yr = yearRect(rect);

        // Draw the three segment backgrounds
        drawSegment(r, dr,  self.focus == .day   or self.day_open);
        drawSegment(r, mr,  self.focus == .month or self.month_open);
        drawSegment(r, yr,  self.focus == .year  or self.year_open);

        // Dividers
        r.fillRect(Rect.init(dr.right(), rect.y, 1, rect.height), SEP);
        r.fillRect(Rect.init(mr.right(), rect.y, 1, rect.height), SEP);

        // Day text "01"–"31"
        var day_buf: [4]u8 = undefined;
        const day_str = std.fmt.bufPrint(&day_buf, "{d:0>2}", .{self.day}) catch "??";
        drawSegmentText(r, dr, day_str);

        // Month text "Jan"–"Dec"
        const month_str = if (self.month >= 1 and self.month <= 12)
            MONTHS[self.month - 1]
        else
            "???";
        drawSegmentText(r, mr, month_str);

        // Year text "2024"
        var yr_buf: [6]u8 = undefined;
        const yr_str = std.fmt.bufPrint(&yr_buf, "{d}", .{self.year}) catch "????";
        drawSegmentText(r, yr, yr_str);

        // Chevron indicators
        r.drawText("v", dr.right() - 14, dr.y + @as(i32, @intCast(dr.height / 2)) - 7, FG_TER);
        r.drawText("v", mr.right() - 14, mr.y + @as(i32, @intCast(mr.height / 2)) - 7, FG_TER);
        r.drawText("v", yr.right() - 14, yr.y + @as(i32, @intCast(yr.height / 2)) - 7, FG_TER);

        // Popups (drawn last — on top)
        if (self.day_open) {
            const pop = dayPopupRect(rect);
            const max_d = daysInMonth(self.month, self.year);
            drawPopup(r, pop);
            for (0..max_d) |i| {
                const i32_i = @as(i32, @intCast(i));
                const iy = pop.y + i32_i * @as(i32, ITEM_H);
                const item_rect = Rect.init(pop.x + 1, iy, pop.width -| 2, ITEM_H);
                const day_num = @as(u32, @intCast(i)) + 1;
                if (day_num == self.day) {
                    r.fillRect(item_rect, ACCENT);
                } else if (self.day_hover != null and self.day_hover.? == @as(u32, @intCast(i))) {
                    r.fillRect(item_rect, Color.rgba(255, 255, 255, 20));
                }
                var db: [4]u8 = undefined;
                const ds = std.fmt.bufPrint(&db, "{d:0>2}", .{day_num}) catch "??";
                const tw = r.textWidth(ds);
                const tx = pop.x + @as(i32, @intCast((pop.width -| tw) / 2));
                r.drawText(ds, tx, iy + @as(i32, @intCast(ITEM_H / 2)) - 7, FG);
            }
        }

        if (self.month_open) {
            const pop = monthPopupRect(rect);
            drawPopup(r, pop);
            for (0..12) |i| {
                const i32_i = @as(i32, @intCast(i));
                const iy = pop.y + i32_i * @as(i32, ITEM_H);
                const item_rect = Rect.init(pop.x + 1, iy, pop.width -| 2, ITEM_H);
                const m_num = @as(u32, @intCast(i)) + 1;
                if (m_num == self.month) {
                    r.fillRect(item_rect, ACCENT);
                } else if (self.month_hover != null and self.month_hover.? == @as(u32, @intCast(i))) {
                    r.fillRect(item_rect, Color.rgba(255, 255, 255, 20));
                }
                const ms = MONTHS[i];
                const tw = r.textWidth(ms);
                const tx = pop.x + @as(i32, @intCast((pop.width -| tw) / 2));
                r.drawText(ms, tx, iy + @as(i32, @intCast(ITEM_H / 2)) - 7, FG);
            }
        }

        if (self.year_open) {
            const pop = yearPopupRect(rect);
            drawPopup(r, pop);
            const yb = self.yearBase();
            for (0..10) |i| {
                const i32_i = @as(i32, @intCast(i));
                const iy = pop.y + i32_i * @as(i32, ITEM_H);
                const item_rect = Rect.init(pop.x + 1, iy, pop.width -| 2, ITEM_H);
                const y_num = yb + @as(u32, @intCast(i));
                if (y_num == self.year) {
                    r.fillRect(item_rect, ACCENT);
                } else if (self.year_hover != null and self.year_hover.? == @as(u32, @intCast(i))) {
                    r.fillRect(item_rect, Color.rgba(255, 255, 255, 20));
                }
                var yb2: [6]u8 = undefined;
                const ys = std.fmt.bufPrint(&yb2, "{d}", .{y_num}) catch "????";
                const tw = r.textWidth(ys);
                const tx = pop.x + @as(i32, @intCast((pop.width -| tw) / 2));
                r.drawText(ys, tx, iy + @as(i32, @intCast(ITEM_H / 2)) - 7, FG);
            }
        }
    }

    pub fn accessNode(self: *const DatePicker, rect: Rect) AccessNode {
        var buf: [16]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "{d:0>4}-{d:0>2}-{d:0>2}",
            .{ self.year, self.month, self.day }) catch "DatePicker";
        _ = name; // AccessNode.name needs a stable slice — use a static fallback
        return .{
            .role   = .combo_box,
            .name   = "DatePicker",
            .bounds = rect,
            .state  = .{
                .enabled  = true,
                .expanded = self.day_open or self.month_open or self.year_open,
            },
        };
    }

    pub fn preferredSize(_: *const DatePicker) Size {
        return .{ .width = 260, .height = 34 };
    }
};

// ── Drawing helpers ───────────────────────────────────────────────────────────

fn drawSegment(r: *Renderer, rect: Rect, active: bool) void {
    const border = if (active) ACCENT else SEP;
    r.fillRoundRect(rect, 4, border);
    r.fillRoundRect(
        Rect.init(rect.x + 1, rect.y + 1, rect.width -| 2, rect.height -| 2),
        3, BG_INPUT,
    );
}

fn drawSegmentText(r: *Renderer, rect: Rect, text: []const u8) void {
    const tw = r.textWidth(text);
    // Leave room for chevron (16px from right)
    const avail_w: i32 = @as(i32, @intCast(rect.width)) - 20;
    const tx = rect.x + @max(8, @divTrunc(avail_w - @as(i32, @intCast(tw)), 2));
    const ty = rect.y + @as(i32, @intCast(rect.height / 2)) - 7;
    r.drawText(text, tx, ty, FG);
}

fn drawPopup(r: *Renderer, rect: Rect) void {
    r.fillRoundRect(rect, 4, SEP);
    r.fillRoundRect(
        Rect.init(rect.x + 1, rect.y + 1, rect.width -| 2, rect.height -| 2),
        3, Color.rgb(35, 35, 38),
    );
}
