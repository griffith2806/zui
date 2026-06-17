const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Rect       = @import("../layout/geometry.zig").Rect;
const Point      = @import("../layout/geometry.zig").Point;
const Size       = @import("../layout/geometry.zig").Size;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const Event      = @import("../events/event.zig").Event;
const Signal     = @import("../signals/signal.zig").Signal;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

// ---------------------------------------------------------------------------
// DataSource — caller-provided vtable for virtual data access.
// A value type with no allocation required.
// ---------------------------------------------------------------------------
pub const DataSource = struct {
    ctx:      *anyopaque,
    count_fn: *const fn (*anyopaque) usize,
    get_fn:   *const fn (*anyopaque, index: usize) []const u8,

    pub fn count(self: DataSource) usize {
        return self.count_fn(self.ctx);
    }

    pub fn get(self: DataSource, i: usize) []const u8 {
        return self.get_fn(self.ctx, i);
    }

    /// Convenience: wrap a []const []const u8 slice.
    /// The caller must ensure `slice` outlives the DataSource.
    pub fn fromSlice(slice: *const []const []const u8) DataSource {
        return .{
            .ctx      = @constCast(@ptrCast(slice)),
            .count_fn = struct {
                fn count_impl(ctx: *anyopaque) usize {
                    const s: *const []const []const u8 = @ptrCast(@alignCast(ctx));
                    return s.*.len;
                }
            }.count_impl,
            .get_fn   = struct {
                fn get_impl(ctx: *anyopaque, index: usize) []const u8 {
                    const s: *const []const []const u8 = @ptrCast(@alignCast(ctx));
                    return s.*[index];
                }
            }.get_impl,
        };
    }
};

// ---------------------------------------------------------------------------
// ListView — virtual/recycled list; only visible rows are rendered.
// ---------------------------------------------------------------------------
pub const ListView = struct {
    source:        DataSource,
    selected:      ?usize = null,
    hovered:       ?usize = null,
    scroll_offset: i32    = 0,
    item_height:   u32    = 32,
    bg:            Color  = Color.rgb(30, 30, 32),
    item_hover:    Color  = Color.rgba(255, 255, 255, 15),
    item_selected: Color  = Color.rgb(0, 103, 192),
    fg:            Color  = Color.white,
    fg_selected:   Color  = Color.white,
    changed:       Signal(usize) = .{},

    // -----------------------------------------------------------------------
    // Convenience constructor: backward-compatible slice-backed list.
    // `items` must outlive the returned ListView.
    // -----------------------------------------------------------------------
    pub fn fromSlice(items: *const []const []const u8) ListView {
        return .{ .source = DataSource.fromSlice(items) };
    }

    pub fn deinit(self: *ListView, alloc: std.mem.Allocator) void {
        self.changed.deinit(alloc);
    }

    pub fn contentHeight(self: *const ListView) u32 {
        return @as(u32, @intCast(self.source.count())) * self.item_height;
    }

    pub fn preferredSize(self: *const ListView) Size {
        const visible = @min(@as(u32, 6), @as(u32, @intCast(self.source.count())));
        return .{
            .width  = 200,
            .height = visible * self.item_height,
        };
    }

    pub fn accessNode(self: *const ListView, rect: Rect, focused: bool) AccessNode {
        const item_count = self.source.count();
        const name = if (self.selected) |s|
            (if (s < item_count) self.source.get(s) else "List")
        else
            "List";
        return .{ .role = .list, .name = name, .bounds = rect, .state = .{ .focused = focused } };
    }

    pub fn draw(self: *const ListView, r: *Renderer, rect: Rect) void {
        r.fillRect(rect, self.bg);

        const item_h = @as(i32, @intCast(self.item_height));
        const total  = self.source.count();
        if (total == 0) return;

        // Virtual window: compute which rows are (potentially) visible.
        // Add a 2-row overdraw buffer on each side.
        const first_raw = @divFloor(self.scroll_offset, item_h);
        const first_visible: usize = if (first_raw > 2)
            @as(usize, @intCast(first_raw - 2))
        else
            0;

        const last_raw = @divFloor(self.scroll_offset + @as(i32, @intCast(rect.height)), item_h) + 2;
        const last_visible: usize = @min(
            @as(usize, @intCast(@max(0, last_raw))),
            total,
        );

        var i = first_visible;
        while (i < last_visible) : (i += 1) {
            const item_y = rect.y - self.scroll_offset + @as(i32, @intCast(i)) * item_h;
            const item_rect = Rect.init(rect.x, item_y, rect.width, self.item_height);

            // Fine-grained clip guard (covers overdraw rows that still miss)
            if (item_rect.bottom() <= rect.y) continue;
            if (item_rect.y >= rect.bottom()) continue;

            if (self.selected != null and self.selected.? == i) {
                r.fillRect(item_rect, self.item_selected);
            } else if (self.hovered != null and self.hovered.? == i) {
                r.fillRect(item_rect, self.item_hover);
            }

            const fg_color = if (self.selected != null and self.selected.? == i)
                self.fg_selected
            else
                self.fg;

            const text_y = item_rect.y + @as(i32, @intCast(self.item_height / 2)) - 7;
            r.drawText(self.source.get(i), item_rect.x + 12, text_y, fg_color);
        }
    }

    pub fn handleEvent(self: *ListView, event: Event, rect: Rect) bool {
        switch (event) {
            .mouse_move => |m| {
                const pt = Point{ .x = m.x, .y = m.y };
                if (rect.contains(pt)) {
                    const rel_y = m.y - rect.y + self.scroll_offset;
                    if (rel_y >= 0) {
                        const idx = @as(usize, @intCast(rel_y)) / @as(usize, @intCast(self.item_height));
                        if (idx < self.source.count()) {
                            self.hovered = idx;
                        } else {
                            self.hovered = null;
                        }
                    } else {
                        self.hovered = null;
                    }
                } else {
                    self.hovered = null;
                }
                return false;
            },
            .mouse_press => |m| {
                if (m.button == .left and rect.contains(.{ .x = m.x, .y = m.y })) {
                    const rel_y = m.y - rect.y + self.scroll_offset;
                    if (rel_y >= 0) {
                        const idx = @as(usize, @intCast(rel_y)) / @as(usize, @intCast(self.item_height));
                        if (idx < self.source.count()) {
                            self.selected = idx;
                            self.changed.emit(idx);
                            return true;
                        }
                    }
                }
            },
            .scroll => |ev| {
                const delta = @as(i32, @intFromFloat(ev.dy * @as(f32, @floatFromInt(self.item_height))));
                self.scroll_offset -= delta;
                const max_offset: i32 = blk: {
                    const raw = @as(i32, @intCast(self.contentHeight())) - @as(i32, @intCast(rect.height));
                    break :blk @max(0, raw);
                };
                if (self.scroll_offset < 0) self.scroll_offset = 0;
                if (self.scroll_offset > max_offset) self.scroll_offset = max_offset;
                return true;
            },
            .key_press => |k| {
                if (self.selected == null) return false;
                switch (k.key) {
                    .up => {
                        if (self.selected.? > 0) {
                            self.selected = self.selected.? - 1;
                            self.changed.emit(self.selected.?);
                            return true;
                        }
                    },
                    .down => {
                        if (self.selected.? + 1 < self.source.count()) {
                            self.selected = self.selected.? + 1;
                            self.changed.emit(self.selected.?);
                            return true;
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
        return false;
    }
};
