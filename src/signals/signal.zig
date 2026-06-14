const std = @import("std");

pub fn Signal(comptime T: type) type {
    return struct {
        const Self = @This();
        const SlotFn = *const fn (*anyopaque, T) void;

        const Slot = struct { ctx: *anyopaque, func: SlotFn };

        slots: std.ArrayListUnmanaged(Slot) = .empty,

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.slots.deinit(alloc);
        }

        pub fn connect(
            self: *Self,
            alloc: std.mem.Allocator,
            ctx: anytype,
            comptime func: fn (@TypeOf(ctx), T) void,
        ) !void {
            const Ctx = @TypeOf(ctx);
            const wrapper = struct {
                fn call(raw: *anyopaque, val: T) void {
                    func(@as(Ctx, @ptrCast(@alignCast(raw))), val);
                }
            };
            try self.slots.append(alloc, .{ .ctx = ctx, .func = wrapper.call });
        }

        pub fn emit(self: *const Self, value: T) void {
            for (self.slots.items) |s| s.func(s.ctx, value);
        }

        pub fn disconnect(self: *Self, alloc: std.mem.Allocator, ctx: *anyopaque) void {
            var i: usize = 0;
            while (i < self.slots.items.len) {
                if (self.slots.items[i].ctx == ctx) {
                    _ = self.slots.orderedRemove(i);
                } else i += 1;
            }
            _ = alloc;
        }
    };
}

test "Signal connect and emit" {
    const alloc = std.testing.allocator;
    var sig: Signal(i32) = .{};
    defer sig.deinit(alloc);

    var sum: i32 = 0;
    try sig.connect(alloc, &sum, struct {
        fn add(p: *i32, v: i32) void { p.* += v; }
    }.add);

    sig.emit(10);
    sig.emit(5);
    try std.testing.expectEqual(@as(i32, 15), sum);
}

test "Signal void payload" {
    const alloc = std.testing.allocator;
    var sig: Signal(void) = .{};
    defer sig.deinit(alloc);

    var count: u32 = 0;
    try sig.connect(alloc, &count, struct {
        fn inc(p: *u32, _: void) void { p.* += 1; }
    }.inc);

    sig.emit({});
    sig.emit({});
    try std.testing.expectEqual(@as(u32, 2), count);
}
