const std      = @import("std");
const Color    = @import("../style/color.zig").Color;
const Rect     = @import("../layout/geometry.zig").Rect;
const Size     = @import("../layout/geometry.zig").Size;
const Renderer = @import("../graphics/renderer.zig").Renderer;
const Event    = @import("../events/event.zig").Event;

pub const TextArea = struct {
    lines:          std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8)),
    cursor_row:     usize = 0,
    cursor_col:     usize = 0,
    scroll_y:       i32   = 0,
    focused:        bool  = false,
    placeholder:    []const u8 = "",
    line_height:    u32   = 22,
    pad:            u32   = 8,
    bg:             Color = Color.rgb(30, 30, 32),
    border:         Color = Color.rgba(255, 255, 255, 40),
    border_focused: Color = Color.rgb(0, 103, 192),
    fg:             Color = Color.white,
    fg_placeholder: Color = Color.rgba(255, 255, 255, 80),
    cursor_color:   Color = Color.white,

    pub fn init(alloc: std.mem.Allocator) !TextArea {
        var ta = TextArea{ .lines = .empty };
        try ta.lines.append(alloc, std.ArrayListUnmanaged(u8).empty);
        return ta;
    }

    pub fn deinit(self: *TextArea, alloc: std.mem.Allocator) void {
        for (self.lines.items) |*line| line.deinit(alloc);
        self.lines.deinit(alloc);
    }

    pub fn draw(self: *const TextArea, r: *Renderer, rect: Rect) void {
        r.fillRoundRect(rect, 6, self.bg);

        const border = if (self.focused) self.border_focused else self.border;
        r.fillRoundRect(rect, 6, border);
        r.fillRoundRect(Rect.init(rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2), 5, self.bg);

        const pad = @as(i32, @intCast(self.pad));
        const lh  = @as(i32, @intCast(self.line_height));

        const is_empty = self.lines.items.len == 1 and self.lines.items[0].items.len == 0;
        if (is_empty and !self.focused and self.placeholder.len > 0) {
            r.drawText(self.placeholder, rect.x + pad, rect.y + pad - self.scroll_y, self.fg_placeholder);
            return;
        }

        for (self.lines.items, 0..) |line, i| {
            const line_y = rect.y + pad - self.scroll_y + @as(i32, @intCast(i)) * lh;
            if (line_y < rect.y - lh) continue;
            if (line_y > rect.bottom()) break;
            r.drawText(line.items, rect.x + pad, line_y, self.fg);
        }

        if (self.focused) {
            const cursor_line_y = rect.y + pad - self.scroll_y + @as(i32, @intCast(self.cursor_row)) * lh;
            const cursor_x = rect.x + pad + @as(i32, @intCast(r.textWidth(self.lines.items[self.cursor_row].items[0..self.cursor_col])));
            r.fillRect(Rect.init(cursor_x, cursor_line_y, 1, self.line_height - 4), self.cursor_color);
        }
    }

    pub fn handleEvent(self: *TextArea, event: Event, rect: Rect, alloc: std.mem.Allocator) bool {
        switch (event) {
            .mouse_press => |m| {
                if (m.button == .left) {
                    const was = self.focused;
                    self.focused = rect.contains(.{ .x = m.x, .y = m.y });
                    return self.focused != was or self.focused;
                }
            },
            .char_input => |cp| {
                if (!self.focused) return false;
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(cp, &buf) catch return false;
                self.lines.items[self.cursor_row].insertSlice(alloc, self.cursor_col, buf[0..len]) catch return false;
                self.cursor_col += len;
                return true;
            },
            .key_press => |k| {
                if (!self.focused) return false;

                switch (k.key) {
                    .enter => {
                        const cur = &self.lines.items[self.cursor_row];
                        const tail = cur.items[self.cursor_col..];
                        var new_line = std.ArrayListUnmanaged(u8).empty;
                        new_line.appendSlice(alloc, tail) catch return false;
                        cur.shrinkRetainingCapacity(self.cursor_col);
                        self.lines.insert(alloc, self.cursor_row + 1, new_line) catch return false;
                        self.cursor_row += 1;
                        self.cursor_col  = 0;
                        return true;
                    },
                    .backspace => {
                        if (self.cursor_col > 0) {
                            const cur = &self.lines.items[self.cursor_row];
                            const removed = prevCharLen(cur.items, self.cursor_col);
                            const new_pos = self.cursor_col - removed;
                            cur.replaceRange(alloc, new_pos, removed, &.{}) catch return false;
                            self.cursor_col = new_pos;
                        } else if (self.cursor_row > 0) {
                            const prev_len = self.lines.items[self.cursor_row - 1].items.len;
                            const cur_items = self.lines.items[self.cursor_row].items;
                            self.lines.items[self.cursor_row - 1].appendSlice(alloc, cur_items) catch return false;
                            var removed_line = self.lines.orderedRemove(self.cursor_row);
                            removed_line.deinit(alloc);
                            self.cursor_row -= 1;
                            self.cursor_col  = prev_len;
                        }
                        return true;
                    },
                    .delete => {
                        const cur = &self.lines.items[self.cursor_row];
                        if (self.cursor_col < cur.items.len) {
                            const removed = nextCharLen(cur.items, self.cursor_col);
                            cur.replaceRange(alloc, self.cursor_col, removed, &.{}) catch return false;
                        } else if (self.cursor_row < self.lines.items.len - 1) {
                            const next_items = self.lines.items[self.cursor_row + 1].items;
                            cur.appendSlice(alloc, next_items) catch return false;
                            var removed_line = self.lines.orderedRemove(self.cursor_row + 1);
                            removed_line.deinit(alloc);
                        }
                        return true;
                    },
                    .left => {
                        if (self.cursor_col > 0) {
                            self.cursor_col -= prevCharLen(self.lines.items[self.cursor_row].items, self.cursor_col);
                        } else if (self.cursor_row > 0) {
                            self.cursor_row -= 1;
                            self.cursor_col  = self.lines.items[self.cursor_row].items.len;
                        }
                        return true;
                    },
                    .right => {
                        const cur = self.lines.items[self.cursor_row].items;
                        if (self.cursor_col < cur.len) {
                            self.cursor_col += nextCharLen(cur, self.cursor_col);
                        } else if (self.cursor_row < self.lines.items.len - 1) {
                            self.cursor_row += 1;
                            self.cursor_col  = 0;
                        }
                        return true;
                    },
                    .up => {
                        if (self.cursor_row > 0) {
                            self.cursor_row -= 1;
                            self.cursor_col = @min(self.cursor_col, self.lines.items[self.cursor_row].items.len);
                        }
                        return true;
                    },
                    .down => {
                        if (self.cursor_row < self.lines.items.len - 1) {
                            self.cursor_row += 1;
                            self.cursor_col = @min(self.cursor_col, self.lines.items[self.cursor_row].items.len);
                        }
                        return true;
                    },
                    .home => {
                        self.cursor_col = 0;
                        return true;
                    },
                    .end => {
                        self.cursor_col = self.lines.items[self.cursor_row].items.len;
                        return true;
                    },
                    .escape => {
                        self.focused = false;
                        return true;
                    },
                    .tab => {
                        self.focused = false;
                        return true;
                    },
                    else => {},
                }
                return true;
            },
            else => {},
        }
        return false;
    }

    pub fn preferredSize(_: *const TextArea) Size {
        return .{ .width = 300, .height = 120 };
    }

    pub fn setText(self: *TextArea, alloc: std.mem.Allocator, text: []const u8) !void {
        for (self.lines.items) |*line| line.deinit(alloc);
        self.lines.clearRetainingCapacity();

        if (text.len == 0) {
            try self.lines.append(alloc, std.ArrayListUnmanaged(u8).empty);
        } else {
            var it = std.mem.splitScalar(u8, text, '\n');
            while (it.next()) |segment| {
                var line = std.ArrayListUnmanaged(u8).empty;
                try line.appendSlice(alloc, segment);
                try self.lines.append(alloc, line);
            }
        }

        self.cursor_row = 0;
        self.cursor_col = 0;
        self.scroll_y   = 0;
    }

    pub fn getText(self: *const TextArea, alloc: std.mem.Allocator) ![]u8 {
        var total: usize = 0;
        for (self.lines.items) |line| total += line.items.len;
        if (self.lines.items.len > 0) total += self.lines.items.len - 1; // newlines between lines

        var buf = try alloc.alloc(u8, total);
        var pos: usize = 0;
        for (self.lines.items, 0..) |line, i| {
            @memcpy(buf[pos..][0..line.items.len], line.items);
            pos += line.items.len;
            if (i < self.lines.items.len - 1) {
                buf[pos] = '\n';
                pos += 1;
            }
        }
        return buf;
    }
};

fn prevCharLen(bytes: []const u8, pos: usize) usize {
    if (pos == 0) return 0;
    var i: usize = 1;
    while (i <= pos and i <= 4) : (i += 1) {
        if (std.unicode.utf8ByteSequenceLength(bytes[pos - i]) catch null) |_| return i;
    }
    return 1;
}

fn nextCharLen(bytes: []const u8, pos: usize) usize {
    if (pos >= bytes.len) return 0;
    return std.unicode.utf8ByteSequenceLength(bytes[pos]) catch 1;
}
