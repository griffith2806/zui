const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Theme      = @import("../style/theme.zig").Theme;
const Rect       = @import("../layout/geometry.zig").Rect;
const Size       = @import("../layout/geometry.zig").Size;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const Event      = @import("../events/event.zig").Event;
const cb         = @import("../platform/win32/clipboard.zig");
const AccessNode = @import("../accessibility/node.zig").AccessNode;

pub const TextField = struct {
    text:       std.ArrayListUnmanaged(u8) = .empty,
    cursor:     usize = 0,
    view_start: usize = 0,  // byte offset: scroll left until cursor is visible
    focused:    bool  = false,
    hovered:    bool  = false,

    // IME / CJK composition state.
    // When `ime_active` is true, `ime_composition` holds the provisional string
    // that is being composed but not yet committed.  It is rendered inline after
    // the committed text and is also reflected in `accessNode()` so UIA screen
    // readers can announce the in-progress composition.
    ime_active:      bool                           = false,
    ime_composition: std.ArrayListUnmanaged(u8)     = .empty,
    // Scratch buffer used by accessNode() to concatenate committed + composition
    // text into a single contiguous slice for the UIA value field.  Grown as
    // needed; never shrunk so subsequent frames are allocation-free once stable.
    _value_scratch:  std.ArrayListUnmanaged(u8)     = .empty,

    pub fn deinit(self: *TextField, alloc: std.mem.Allocator) void {
        self.text.deinit(alloc);
        self.ime_composition.deinit(alloc);
        self._value_scratch.deinit(alloc);
    }

    /// Build an AccessNode for this text field.
    ///
    /// When an IME composition is in progress (`ime_active == true`) the `value`
    /// field of the returned node contains the committed text followed by the
    /// provisional composition string, so UIA screen readers see the full visible
    /// content including the in-progress characters.
    ///
    /// `alloc` is used only to grow the internal scratch buffer — it is
    /// allocation-free in the common case once the buffer has reached a steady
    /// size.  Pass the same allocator used for the rest of the widget lifecycle.
    pub fn accessNode(self: *TextField, name: []const u8, rect: Rect, alloc: std.mem.Allocator) AccessNode {
        const value: []const u8 = if (self.ime_active and self.ime_composition.items.len > 0) blk: {
            // Concatenate committed text + composition into the scratch buffer.
            const total = self.text.items.len + self.ime_composition.items.len;
            self._value_scratch.resize(alloc, total) catch {
                // On allocation failure fall back to committed text only.
                break :blk self.text.items;
            };
            @memcpy(self._value_scratch.items[0..self.text.items.len], self.text.items);
            @memcpy(self._value_scratch.items[self.text.items.len..], self.ime_composition.items);
            break :blk self._value_scratch.items;
        } else self.text.items;

        return .{
            .role   = .text_field,
            .name   = name,
            .value  = value,
            .bounds = rect,
            .state  = .{ .focused = self.focused },
        };
    }

    pub fn draw(self: *TextField, r: *Renderer, rect: Rect, theme: Theme) void {
        // Rounded background
        r.fillRoundRect(rect, 6, theme.input_bg);

        // Border — brighter when focused
        const border = if (self.focused) theme.input_border_focused else theme.input_border;
        r.fillRoundRect(rect, 6, border);
        r.fillRoundRect(Rect.init(rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2), 5, theme.input_bg);

        const tx = rect.x + 10;
        const ty = rect.y + @as(i32, @intCast(rect.height / 2)) - 7;
        const usable_w = rect.width -| 20;

        const committed = self.text.items;
        const composition = if (self.ime_active) self.ime_composition.items else "";
        const has_text = committed.len > 0 or composition.len > 0;

        if (has_text) {
            // Scroll view_start forward until pre-cursor text fits in usable_w.
            // The virtual cursor sits at the end of committed text when IME is active.
            while (self.view_start < self.cursor) {
                const pre = committed[self.view_start..self.cursor];
                if (r.textWidth(pre) <= usable_w) break;
                self.view_start += nextCharLen(committed, self.view_start);
            }
            // Scroll view_start backward if cursor moved left of view
            while (self.view_start > 0 and self.view_start > self.cursor) {
                self.view_start -= prevCharLen(committed, self.view_start);
            }
            r.drawText(committed[self.view_start..], tx, ty, theme.fg);

            // Draw the provisional composition string after the committed text,
            // using a slightly dimmed colour so users can distinguish it.
            if (composition.len > 0) {
                const committed_w = @as(i32, @intCast(r.textWidth(committed[self.view_start..])));
                const comp_x = tx + committed_w;
                r.drawText(composition, comp_x, ty, theme.input_hint);
                // Underline under the composition span (1 px, 2 px below text baseline).
                const comp_w = r.textWidth(composition);
                r.fillRect(Rect.init(comp_x, ty + 16, @intCast(comp_w), 1), theme.input_hint);
            }
        } else {
            r.drawText("Type here...", tx, ty, theme.input_hint);
        }

        if (self.focused) {
            // While IME is active the text cursor is suppressed — the IME candidate
            // window shows its own cursor position indicator.
            if (!self.ime_active) {
                const pre = if (self.cursor > self.view_start)
                    committed[self.view_start..self.cursor]
                else
                    "";
                const cursor_x = tx + @as(i32, @intCast(r.textWidth(pre)));
                r.fillRect(Rect.init(cursor_x, ty, 1, 16), theme.fg);
            }
        }
    }

    pub fn preferredSize(_: *const TextField) Size {
        return .{ .width = 200, .height = 34 };
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
                // When an IME session is active the committed text arrives via
                // WM_IME_COMPOSITION's GCS_RESULTSTR — which the platform layer
                // converts to one or more char_input events after clearing the
                // composition.  Clear IME state then insert the committed char.
                self.ime_active = false;
                self.ime_composition.clearRetainingCapacity();
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(cp, &buf) catch return false;
                self.text.insertSlice(alloc, self.cursor, buf[0..len]) catch return false;
                self.cursor += len;
                return true;
            },
            .ime_composition => |*ic| {
                if (!self.focused) return false;
                // Replace the current provisional composition with the new one.
                self.ime_active = true;
                self.ime_composition.clearRetainingCapacity();
                self.ime_composition.appendSlice(alloc, ic.text()) catch {};
                return true;
            },
            .ime_cancel => {
                if (!self.focused) return false;
                // IME cancelled without committing — clear composition state.
                self.ime_active = false;
                self.ime_composition.clearRetainingCapacity();
                return true;
            },
            .key_press => |k| {
                if (!self.focused) return false;

                // Ctrl shortcuts
                if (k.modifiers.ctrl) {
                    switch (k.key) {
                        .a => { self.cursor = self.text.items.len; return true; },
                        .c => {
                            cb.setText(self.text.items, alloc);
                            return true;
                        },
                        .v => {
                            if (cb.getText(alloc)) |pasted| {
                                defer alloc.free(pasted);
                                self.text.insertSlice(alloc, self.cursor, pasted) catch {};
                                self.cursor += pasted.len;
                            }
                            return true;
                        },
                        else => {},
                    }
                }

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
                    .left  => { if (self.cursor > 0)                    self.cursor -= prevCharLen(self.text.items, self.cursor); return true; },
                    .right => { if (self.cursor < self.text.items.len)  self.cursor += nextCharLen(self.text.items, self.cursor); return true; },
                    .home  => { self.cursor = 0;                         return true; },
                    .end   => { self.cursor = self.text.items.len;       return true; },
                    .escape, .tab => { self.focused = false;             return true; },
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
        if (std.unicode.utf8ByteSequenceLength(bytes[pos - i]) catch null) |_| return i;
    }
    return 1;
}

fn nextCharLen(bytes: []const u8, pos: usize) usize {
    if (pos >= bytes.len) return 0;
    return std.unicode.utf8ByteSequenceLength(bytes[pos]) catch 1;
}
