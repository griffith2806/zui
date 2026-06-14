const std = @import("std");
const KeyEvent = @import("../events/event.zig").KeyEvent;

pub const FocusManager = struct {
    slots: std.ArrayListUnmanaged(usize) = .empty,
    focused: ?usize = null,
    next_id: usize = 0,

    pub fn init() FocusManager {
        return .{};
    }

    pub fn deinit(self: *FocusManager, alloc: std.mem.Allocator) void {
        self.slots.deinit(alloc);
    }

    pub fn register(self: *FocusManager, alloc: std.mem.Allocator) !usize {
        const id = self.next_id;
        self.next_id += 1;
        try self.slots.append(alloc, id);
        return id;
    }

    pub fn unregister(self: *FocusManager, alloc: std.mem.Allocator, id: usize) void {
        _ = alloc;
        for (self.slots.items, 0..) |slot_id, i| {
            if (slot_id == id) {
                _ = self.slots.orderedRemove(i);
                break;
            }
        }
        if (self.focused == id) self.focused = null;
    }

    pub fn setFocus(self: *FocusManager, id: usize) void {
        self.focused = id;
    }

    pub fn clearFocus(self: *FocusManager) void {
        self.focused = null;
    }

    pub fn hasFocus(self: *const FocusManager, id: usize) bool {
        return self.focused == id;
    }

    pub fn nextFocus(self: *FocusManager) void {
        if (self.slots.items.len == 0) return;
        if (self.focused) |current| {
            for (self.slots.items, 0..) |slot_id, i| {
                if (slot_id == current) {
                    const next_i = (i + 1) % self.slots.items.len;
                    self.focused = self.slots.items[next_i];
                    return;
                }
            }
        }
        self.focused = self.slots.items[0];
    }

    pub fn prevFocus(self: *FocusManager) void {
        if (self.slots.items.len == 0) return;
        if (self.focused) |current| {
            for (self.slots.items, 0..) |slot_id, i| {
                if (slot_id == current) {
                    const prev_i = if (i == 0) self.slots.items.len - 1 else i - 1;
                    self.focused = self.slots.items[prev_i];
                    return;
                }
            }
        }
        self.focused = self.slots.items[self.slots.items.len - 1];
    }

    pub fn handleKey(self: *FocusManager, ev: KeyEvent) bool {
        if (ev.key == .tab) {
            if (ev.modifiers.shift) {
                self.prevFocus();
            } else {
                self.nextFocus();
            }
            return true;
        }
        return false;
    }
};

test "FocusManager register and tab" {
    const alloc = std.testing.allocator;
    var fm = FocusManager.init();
    defer fm.deinit(alloc);

    const a = try fm.register(alloc);
    const b = try fm.register(alloc);
    const c = try fm.register(alloc);

    try std.testing.expectEqual(@as(?usize, null), fm.focused);

    _ = fm.handleKey(.{ .key = .tab });
    try std.testing.expectEqual(@as(?usize, a), fm.focused);

    _ = fm.handleKey(.{ .key = .tab });
    try std.testing.expectEqual(@as(?usize, b), fm.focused);

    _ = fm.handleKey(.{ .key = .tab });
    try std.testing.expectEqual(@as(?usize, c), fm.focused);

    _ = fm.handleKey(.{ .key = .tab });
    try std.testing.expectEqual(@as(?usize, a), fm.focused);

    _ = fm.handleKey(.{ .key = .tab, .modifiers = .{ .shift = true } });
    try std.testing.expectEqual(@as(?usize, c), fm.focused);

    fm.unregister(alloc, b);
    try std.testing.expect(!fm.hasFocus(b));

    fm.setFocus(a);
    try std.testing.expect(fm.hasFocus(a));

    fm.clearFocus();
    try std.testing.expectEqual(@as(?usize, null), fm.focused);

    const consumed = fm.handleKey(.{ .key = .enter });
    try std.testing.expect(!consumed);
}
