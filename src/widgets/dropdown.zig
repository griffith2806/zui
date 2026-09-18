const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Corners    = @import("../style/paint.zig").Corners;
const Shadow     = @import("../style/paint.zig").Shadow;
const Rect       = @import("../layout/geometry.zig").Rect;
const Point      = @import("../layout/geometry.zig").Point;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const Event      = @import("../events/event.zig").Event;
const Signal     = @import("../signals/signal.zig").Signal;
const AccessNode = @import("../accessibility/node.zig").AccessNode;
const Role       = @import("../accessibility/node.zig").Role;
const icons      = @import("../style/icons.zig");

/// Visual configuration for a DropDown. Every colour and metric is overridable so
/// callers can match their design tokens (e.g. rove's Figma palette).
pub const DropDownStyle = struct {
    bg:              Color  = Color.rgb(30, 30, 32),        // closed trigger fill
    bg_hover:        Color  = Color.rgb(45, 45, 48),        // trigger fill while hovered
    bg_open:         Color  = Color.rgb(40, 40, 44),        // trigger fill while open
    border:          Color  = Color.rgba(255, 255, 255, 30),// trigger border
    border_focus:    Color  = Color.rgb(0, 103, 192),       // accent ring when focused/open
    fg:              Color  = Color.white,                  // trigger + item text
    fg_dim:          Color  = Color.rgb(160, 160, 168),     // chevron
    list_bg:         Color  = Color.rgb(35, 35, 38),        // popup list fill
    list_border:     Color  = Color.rgba(255, 255, 255, 30),
    item_hover:      Color  = Color.rgba(255, 255, 255, 15),
    item_selected:   Color  = Color.rgb(0, 103, 192),
    item_selected_fg: Color = Color.white,
    radius:          u32    = 6,
    item_h:          u32    = 30,
    /// Maximum list items shown before the popup scrolls.
    max_visible:     u32    = 6,
    shadow:          Shadow = .{ .kind = .drop, .color = Color.rgba(0, 0, 0, 80), .offset_y = 2, .blur = 8 },
};

pub const DropDown = struct {
    items:        []const []const u8,
    selected:     usize = 0,
    open:         bool = false,
    hovered:      ?usize = null,
    trigger_hovered: bool = false,
    focused:      bool = false,
    scroll_offset: u32 = 0,
    style:        DropDownStyle = .{},

    changed: Signal(usize) = .{},

    pub fn deinit(self: *DropDown, alloc: std.mem.Allocator) void {
        self.changed.deinit(alloc);
    }

    /// Number of list rows visible at once (capped by `max_visible`).
    pub fn visibleCount(self: *const DropDown) u32 {
        return @min(@as(u32, @intCast(self.items.len)), @max(self.style.max_visible, 1));
    }

    /// Height of the popup list, in logical pixels.
    pub fn listHeight(self: *const DropDown) u32 {
        return self.visibleCount() * self.style.item_h;
    }

    /// Popup list rectangle, anchored below the trigger.
    pub fn listRect(self: *const DropDown, trigger: Rect) Rect {
        return Rect.init(trigger.x, trigger.bottom(), trigger.width, self.listHeight());
    }

    /// Clamp the scroll offset so a valid window is always shown.
    pub fn clampScroll(self: *DropDown) void {
        const total: u32 = @intCast(self.items.len);
        const visible = self.visibleCount();
        const max: u32 = if (total > visible) total - visible else 0;
        if (self.scroll_offset > max) self.scroll_offset = max;
    }

    /// Ensure `idx` is inside the visible window.
    fn scrollTo(self: *DropDown, idx: usize) void {
        const visible = self.visibleCount();
        const i: u32 = @intCast(idx);
        if (i < self.scroll_offset) {
            self.scroll_offset = i;
        } else if (i >= self.scroll_offset + visible) {
            self.scroll_offset = i - visible + 1;
        }
    }

    fn select(self: *DropDown, idx: usize) void {
        if (idx >= self.items.len) return;
        self.selected = idx;
        self.open = false;
        self.hovered = null;
        self.changed.emit(idx);
    }

    /// The combo-box node. When the list is open the caller should also emit the
    /// per-item nodes from `accessNodes` (children at depth +1).
    pub fn accessNode(self: *const DropDown, rect: Rect, focused: bool) AccessNode {
        const name = if (self.selected < self.items.len) self.items[self.selected] else "Dropdown";
        return .{
            .role   = .combo_box,
            .name   = name,
            .value  = name,
            .bounds = rect,
            .state  = .{ .focused = focused, .expanded = self.open },
        };
    }

    /// Emit one `list_item` node per visible popup row. Returns the count written.
    pub fn accessNodes(self: *const DropDown, trigger: Rect, out: []AccessNode) usize {
        if (!self.open) return 0;
        const list = self.listRect(trigger);
        const visible = self.visibleCount();
        var n: usize = 0;
        var i: u32 = self.scroll_offset;
        while (i < self.scroll_offset + visible and i < self.items.len) : (i += 1) {
            if (n >= out.len) break;
            const idx: usize = @intCast(i);
            const row = Rect.init(list.x + 1, list.y + @as(i32, @intCast((i - self.scroll_offset) * self.style.item_h)), list.width -| 2, self.style.item_h);
            out[n] = .{
                .role   = .list_item,
                .name   = self.items[idx],
                .bounds = row,
                .state  = .{ .selected = idx == self.selected },
                .depth  = 1,
            };
            n += 1;
        }
        return n;
    }

    /// Draw the trigger control only (no popup).
    pub fn drawTrigger(self: *const DropDown, r: *Renderer, rect: Rect) void {
        const s = self.style;
        const border = if (self.open or self.focused) s.border_focus else s.border;
        const bg = if (self.open) s.bg_open else if (self.trigger_hovered) s.bg_hover else s.bg;
        r.fillRoundRect(rect, s.radius, border);
        r.fillRoundRect(Rect.init(rect.x + 1, rect.y + 1, rect.width -| 2, rect.height -| 2), s.radius, bg);

        if (self.selected < self.items.len) {
            const ty = rect.y + @as(i32, @intCast((rect.height -| 14) / 2));
            r.drawText(self.items[self.selected], rect.x + 10, ty, s.fg);
        }

        const chev = if (self.open) icons.chevron_up else icons.chevron_down;
        const chev_x = rect.x + @as(i32, @intCast(rect.width)) - 24;
        const chev_y = rect.y + @as(i32, @intCast((rect.height -| 14) / 2));
        r.drawIcon(chev, chev_x, chev_y, s.fg_dim, 1);
    }

    /// Draw the open popup list only.
    pub fn drawList(self: *const DropDown, r: *Renderer, trigger: Rect) void {
        if (!self.open) return;
        const s = self.style;
        const list = self.listRect(trigger);

        r.drawShadow(list, Corners.uniform(@floatFromInt(s.radius)), s.shadow);
        r.fillRoundRect(list, s.radius, s.list_border);
        r.fillRoundRect(Rect.init(list.x + 1, list.y + 1, list.width -| 2, list.height -| 2), s.radius, s.list_bg);

        const visible = self.visibleCount();
        var i: u32 = self.scroll_offset;
        while (i < self.scroll_offset + visible and i < self.items.len) : (i += 1) {
            const idx: usize = @intCast(i);
            const row = Rect.init(list.x + 1, list.y + @as(i32, @intCast((i - self.scroll_offset) * s.item_h)), list.width -| 2, s.item_h);

            if (idx == self.selected) {
                r.fillRoundRect(row, s.radius, s.item_selected);
            } else if (self.hovered != null and self.hovered.? == idx) {
                r.fillRoundRect(row, s.radius, s.item_hover);
            }

            const fg = if (idx == self.selected) s.item_selected_fg else s.fg;
            const ty = row.y + @as(i32, @intCast((s.item_h -| 14) / 2));
            r.drawText(self.items[idx], row.x + 10, ty, fg);

            if (idx == self.selected) {
                const ck_x = row.x + @as(i32, @intCast(row.width)) - 24;
                const ck_y = row.y + @as(i32, @intCast((s.item_h -| 14) / 2));
                r.drawIcon(icons.accept, ck_x, ck_y, s.item_selected_fg, 1);
            }
        }
    }

    /// Draw the whole control (trigger + popup). Convenience for simple hosts;
    /// layered hosts should call `drawTrigger` and `drawList` separately so the
    /// popup renders above later content.
    pub fn draw(self: *const DropDown, r: *Renderer, rect: Rect) void {
        self.drawTrigger(r, rect);
        self.drawList(r, rect);
    }

    pub fn handleEvent(self: *DropDown, event: Event, trigger: Rect) bool {
        const list = self.listRect(trigger);
        switch (event) {
            .mouse_press => |m| {
                if (m.button != .left) return false;
                const pt = Point{ .x = m.x, .y = m.y };

                if (trigger.contains(pt)) {
                    self.open = !self.open;
                    self.hovered = null;
                    if (self.open) self.scrollTo(self.selected);
                    return true;
                }

                if (self.open and list.contains(pt)) {
                    const rel_y = m.y - list.y;
                    if (rel_y >= 0) {
                        const row: u32 = @intCast(@divFloor(rel_y, @as(i32, @intCast(self.style.item_h))));
                        const idx: usize = @intCast(self.scroll_offset + row);
                        if (idx < self.items.len) {
                            self.select(idx);
                            return true;
                        }
                    }
                }

                if (self.open) {
                    self.open = false;
                    return true;
                }
            },
            .mouse_move => |m| {
                const pt = Point{ .x = m.x, .y = m.y };
                self.trigger_hovered = trigger.contains(pt);
                if (self.open and list.contains(pt)) {
                    const rel_y = m.y - list.y;
                    if (rel_y >= 0) {
                        const row: u32 = @intCast(@divFloor(rel_y, @as(i32, @intCast(self.style.item_h))));
                        const idx: usize = @intCast(self.scroll_offset + row);
                        self.hovered = if (idx < self.items.len) idx else null;
                    }
                } else {
                    self.hovered = null;
                }
                return false;
            },
            .key_press => |k| {
                if (self.open) {
                    switch (k.key) {
                        .escape => { self.open = false; return true; },
                        .up => { self.moveHover(-1); return true; },
                        .down => { self.moveHover(1); return true; },
                        .home => { self.hovered = 0; self.scrollTo(0); return true; },
                        .end => { self.hovered = self.items.len - 1; self.scrollTo(self.items.len - 1); return true; },
                        .enter, .space => {
                            if (self.hovered) |idx| { self.select(idx); return true; }
                            return true;
                        },
                        else => {},
                    }
                } else if (self.focused and (k.key == .enter or k.key == .space)) {
                    self.open = true;
                    self.scrollTo(self.selected);
                    return true;
                }
                return false;
            },
            .scroll => |s| {
                if (!self.open) return false;
                const pt = Point{ .x = s.x, .y = s.y };
                if (list.contains(pt)) {
                    const total: u32 = @intCast(self.items.len);
                    const visible = self.visibleCount();
                    const max: u32 = if (total > visible) total - visible else 0;
                    const delta: i32 = if (s.dy > 0) -1 else 1;
                    var next: i64 = @as(i64, @intCast(self.scroll_offset)) + delta;
                    next = std.math.clamp(next, 0, @as(i64, @intCast(max)));
                    self.scroll_offset = @intCast(next);
                    return true;
                }
                return false;
            },
            .focus_gained => { self.focused = true; return false; },
            .focus_lost => {
                self.focused = false;
                if (self.open) self.open = false;
                return false;
            },
            else => {},
        }
        return false;
    }

    fn moveHover(self: *DropDown, dir: i32) void {
        if (self.items.len == 0) return;
        const cur: usize = self.hovered orelse self.selected;
        var next: i64 = @as(i64, @intCast(cur)) + dir;
        if (next < 0) next = @as(i64, @intCast(self.items.len)) - 1;
        if (next >= @as(i64, @intCast(self.items.len))) next = 0;
        self.hovered = @intCast(next);
        self.scrollTo(self.hovered.?);
    }
};

// ── Tests ────────────────────────────────────────────────────────────────────

test "DropDown toggles open on trigger click and closes on outside click" {
    const items = [_][]const u8{ "A", "B", "C" };
    var dd = DropDown{ .items = &items };
    const trigger = Rect.init(0, 0, 100, 30);

    try std.testing.expect(!dd.open);
    _ = dd.handleEvent(.{ .mouse_press = .{ .x = 50, .y = 15, .button = .left } }, trigger);
    try std.testing.expect(dd.open);

    _ = dd.handleEvent(.{ .mouse_press = .{ .x = 500, .y = 500, .button = .left } }, trigger);
    try std.testing.expect(!dd.open);
}

test "DropDown selects an item, emits changed, and closes" {
    const items = [_][]const u8{ "A", "B", "C" };
    var dd = DropDown{ .items = &items };
    const alloc = std.testing.allocator;
    defer dd.deinit(alloc);

    var last: usize = 99;
    _ = try dd.changed.connect(alloc, &last, struct {
        fn f(p: *usize, v: usize) void { p.* = v; }
    }.f);

    const trigger = Rect.init(0, 0, 100, 30);
    _ = dd.handleEvent(.{ .mouse_press = .{ .x = 50, .y = 15, .button = .left } }, trigger);
    try std.testing.expect(dd.open);

    // Click the second row (list starts at y=30; row 1 spans y=60..90).
    _ = dd.handleEvent(.{ .mouse_press = .{ .x = 50, .y = 75, .button = .left } }, trigger);
    try std.testing.expectEqual(@as(usize, 1), dd.selected);
    try std.testing.expectEqual(@as(usize, 1), last);
    try std.testing.expect(!dd.open);
}

test "DropDown keyboard navigation and selection" {
    const items = [_][]const u8{ "A", "B", "C" };
    var dd = DropDown{ .items = &items, .focused = true };
    const trigger = Rect.init(0, 0, 100, 30);

    _ = dd.handleEvent(.{ .key_press = .{ .key = .enter, .repeat = false } }, trigger);
    try std.testing.expect(dd.open);

    _ = dd.handleEvent(.{ .key_press = .{ .key = .down, .repeat = false } }, trigger);
    try std.testing.expectEqual(@as(?usize, 1), dd.hovered);
    _ = dd.handleEvent(.{ .key_press = .{ .key = .down, .repeat = false } }, trigger);
    try std.testing.expectEqual(@as(?usize, 2), dd.hovered);
    _ = dd.handleEvent(.{ .key_press = .{ .key = .down, .repeat = false } }, trigger);
    try std.testing.expectEqual(@as(?usize, 0), dd.hovered); // wraps

    _ = dd.handleEvent(.{ .key_press = .{ .key = .enter, .repeat = false } }, trigger);
    try std.testing.expectEqual(@as(usize, 0), dd.selected);
    try std.testing.expect(!dd.open);

    // Escape closes an open list.
    _ = dd.handleEvent(.{ .key_press = .{ .key = .enter, .repeat = false } }, trigger);
    try std.testing.expect(dd.open);
    _ = dd.handleEvent(.{ .key_press = .{ .key = .escape, .repeat = false } }, trigger);
    try std.testing.expect(!dd.open);
}

test "DropDown scroll clamps and scrollTo keeps selection visible" {
    var items: [8][]const u8 = .{ "a", "b", "c", "d", "e", "f", "g", "h" };
    var dd = DropDown{ .items = &items, .selected = 7 };
    const trigger = Rect.init(0, 0, 100, 30);

    _ = dd.handleEvent(.{ .mouse_press = .{ .x = 50, .y = 15, .button = .left } }, trigger);
    try std.testing.expect(dd.open);
    // 6 visible → scroll must be clamped to 2 (rows 2..7).
    try std.testing.expectEqual(@as(u32, 2), dd.scroll_offset);
    try std.testing.expectEqual(@as(u32, 6), dd.visibleCount());
    try std.testing.expectEqual(@as(u32, 180), dd.listHeight());

    // Select row "a" by scrolling to top then clicking first visible row.
    dd.scroll_offset = 0;
    _ = dd.handleEvent(.{ .mouse_press = .{ .x = 50, .y = 32, .button = .left } }, trigger);
    try std.testing.expectEqual(@as(usize, 0), dd.selected);
}

test "DropDown accessNode exposes combo_box and accessNodes emits children" {    const items = [_][]const u8{ "A", "B", "C" };
    var dd = DropDown{ .items = &items, .open = true, .selected = 1 };
    const trigger = Rect.init(0, 0, 100, 30);

    const node = dd.accessNode(trigger, false);
    try std.testing.expectEqual(Role.combo_box, node.role);
    try std.testing.expect(node.state.expanded);
    try std.testing.expectEqualStrings("B", node.name);

    var buf: [8]AccessNode = undefined;
    const n = dd.accessNodes(trigger, &buf);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualStrings("A", buf[0].name);
    try std.testing.expect(!buf[0].state.selected);
    try std.testing.expect(buf[1].state.selected);
    try std.testing.expectEqual(@as(u16, 1), buf[0].depth);

    // Closed dropdown emits no children.
    dd.open = false;
    try std.testing.expectEqual(@as(usize, 0), dd.accessNodes(trigger, &buf));
}

test "DropDown wheel scrolls the open list and clamps at the ends" {
    var items: [8][]const u8 = .{ "a", "b", "c", "d", "e", "f", "g", "h" };
    var dd = DropDown{ .items = &items, .open = true, .selected = 0 };
    const trigger = Rect.init(0, 0, 100, 30);
    // List is at y=30..210 (6 visible rows of 30px).

    // Wheel down (dy < 0) advances the window toward the end.
    _ = dd.handleEvent(.{ .scroll = .{ .x = 50, .y = 40, .dx = 0, .dy = -1 } }, trigger);
    try std.testing.expectEqual(@as(u32, 1), dd.scroll_offset);

    // Clamped at max (8 - 6 = 2).
    _ = dd.handleEvent(.{ .scroll = .{ .x = 50, .y = 40, .dx = 0, .dy = -1 } }, trigger);
    _ = dd.handleEvent(.{ .scroll = .{ .x = 50, .y = 40, .dx = 0, .dy = -1 } }, trigger);
    _ = dd.handleEvent(.{ .scroll = .{ .x = 50, .y = 40, .dx = 0, .dy = -1 } }, trigger);
    try std.testing.expectEqual(@as(u32, 2), dd.scroll_offset);

    // Wheel up (dy > 0) steps back and clamps at 0.
    _ = dd.handleEvent(.{ .scroll = .{ .x = 50, .y = 40, .dx = 0, .dy = 1 } }, trigger);
    try std.testing.expectEqual(@as(u32, 1), dd.scroll_offset);

    // A scroll outside the list is ignored.
    _ = dd.handleEvent(.{ .scroll = .{ .x = 500, .y = 500, .dx = 0, .dy = -1 } }, trigger);
    try std.testing.expectEqual(@as(u32, 1), dd.scroll_offset);
}
