const std      = @import("std");
const Color    = @import("../style/color.zig").Color;
const Theme    = @import("../style/theme.zig").Theme;
const Rect     = @import("../layout/geometry.zig").Rect;
const Size     = @import("../layout/geometry.zig").Size;
const Renderer = @import("../graphics/software/renderer.zig").Renderer;
const Event    = @import("../events/event.zig").Event;
const font     = @import("../graphics/software/font.zig");

pub const TextField = struct {
    text:    std.ArrayListUnmanaged(u8) = .empty,
    cursor:  usize = 0,
    focused: bool  = false,
    hovered: bool  = false,

    pub fn deinit(self: *TextField, alloc: std.mem.Allocator) void {
        self.text.deinit(alloc);
    }

    pub fn draw(self: *const TextField, r: *Renderer, rect: Rect, theme: Theme) void {
        r.fillRect(rect, theme.input_bg);

        const border = if (self.focused) theme.input_border_focused else theme.input_border;
        r.fillRect(Rect.init(rect.x,              rect.y,               rect.width, 1),           border);
        r.fillRect(Rect.init(rect.x,              rect.bottom() - 1,    rect.width, 1),           border);
        r.fillRect(Rect.init(rect.x,              rect.y,               1,          rect.height), border);
        r.fillRect(Rect.init(rect.right() - 1,    rect.y,               1,          rect.height), border);

        const tx = rect.x + 8;
        const ty = rect.y + @as(i32, @intCast((rect.height -| font.GLYPH_H) / 2));
        r.drawText(self.text.items, tx, ty, theme.fg);

        if (self.focused) {
            const cx = tx + @as(i32, @intCast(self.cursor * font.GLYPH_W));
            r.fillRect(Rect.init(cx, ty, 1, font.GLYPH_H), theme.fg);
        }
    }

    pub fn preferredSize(_: *const TextField) Size {
        return .{ .width = 200, .height = font.GLYPH_H + 16 };
    }

    pub fn handleEvent(self: *TextField, event: Event, rect: Rect, alloc: std.mem.Allocator) bool {
        switch (event) {
            .mouse_move => |m| {
                self.hovered = rect.contains(.{ .x = m.x, .y = m.y });
                return false;
            },
            .mouse_press => |m| {
                if (m.button == .left) {
                    const was = self.focused;
                    self.focused = rect.contains(.{ .x = m.x, .y = m.y });
                    if (self.focused) {
                        self.cursor = self.text.items.len;
                        return true;
                    }
                    return was != self.focused;
                }
            },
            .char_input => |cp| {
                if (!self.focused) return false;
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(cp, &buf) catch return false;
                self.text.insertSlice(alloc, self.cursor, buf[0..len]) catch return false;
                self.cursor += len;
                return true;
            },
            .key_press => |k| {
                if (!self.focused) return false;
                switch (k.key) {
                    .backspace => {
                        if (self.cursor > 0) {
                            const removed = prevCharLen(self.text.items, self.cursor);
                            const new_pos = self.cursor - removed;
                            self.text.replaceRange(alloc, new_pos, removed, &.{}) catch return false;
                            self.cursor = new_pos;
                        }
                        return true;
                    },
                    .delete => {
                        if (self.cursor < self.text.items.len) {
                            const removed = nextCharLen(self.text.items, self.cursor);
                            self.text.replaceRange(alloc, self.cursor, removed, &.{}) catch return false;
                        }
                        return true;
                    },
                    .left => {
                        if (self.cursor > 0)
                            self.cursor -= prevCharLen(self.text.items, self.cursor);
                        return true;
                    },
                    .right => {
                        if (self.cursor < self.text.items.len)
                            self.cursor += nextCharLen(self.text.items, self.cursor);
                        return true;
                    },
                    .home => { self.cursor = 0; return true; },
                    .end  => { self.cursor = self.text.items.len; return true; },
                    .escape, .tab => { self.focused = false; return true; },
                    else => {},
                }
            },
            else => {},
        }
        return false;
    }
};

fn prevCharLen(bytes: []const u8, pos: usize) usize {
    if (pos == 0) return 0;
    var i: usize = 1;
    while (i <= pos and i <= 4) : (i += 1) {
        if (std.unicode.utf8ByteSequenceLength(bytes[pos - i]) catch null) |_| break;
    }
    return i - 1;
}

fn nextCharLen(bytes: []const u8, pos: usize) usize {
    if (pos >= bytes.len) return 0;
    return std.unicode.utf8ByteSequenceLength(bytes[pos]) catch 1;
}
