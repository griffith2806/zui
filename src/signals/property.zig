const std = @import("std");
const Signal = @import("signal.zig").Signal;

// ---------------------------------------------------------------------------
// Property(T) — a Signal-backed observable value.
//
// A Property wraps a value of type T and fires its `changed` signal whenever
// the stored value transitions to a new value.  Equal assignments (same value)
// are silently dropped — the signal is NOT emitted.
//
// Equality rules (resolved at comptime):
//   - Slices ([]T / []const T)   → std.mem.eql on the element type
//   - All other types            → == operator
//
// Allocation contract:
//   - init()  — no allocation; the Signal slot list starts empty
//   - get()   — no allocation
//   - set()   — no allocation (emit is synchronous)
//   - bind()  — allocates one slot in `source.changed.slots`
//   - deinit()— frees the signal's slot list
//
// Typical usage:
//
//   var username: Property([]const u8) = Property([]const u8).init("alice");
//   defer username.deinit(alloc);
//
//   // React to changes
//   _ = try username.changed.connect(alloc, &label, struct {
//       fn f(l: *Label, v: []const u8) void { l.text = v; }
//   }.f);
//
//   username.set("bob");  // fires changed("bob")
//
// Binding to a TextField (one-directional, source → target):
//
//   try model.username_prop.bind(alloc, &text_field_username_prop);
//
// ---------------------------------------------------------------------------
pub fn Property(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The payload type of this Property.  Used by Computed(T).addSource().
        pub const Payload = T;

        value:   T,
        changed: Signal(T) = .{},

        /// Create a Property with an initial value.  No allocation.
        pub fn init(initial: T) Self {
            return .{ .value = initial };
        }

        /// Free the signal's slot list.  Must be called with the same allocator
        /// that was passed to bind() / changed.connect() calls.
        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.changed.deinit(alloc);
        }

        /// Read the current value.  Never allocates.
        pub fn get(self: *const Self) T {
            return self.value;
        }

        /// Write a new value.  If the new value differs from the stored value,
        /// stores it and fires `changed`.  Equal writes are silent no-ops.
        pub fn set(self: *Self, new_val: T) void {
            if (valuesEqual(self.value, new_val)) return;
            self.value = new_val;
            self.changed.emit(new_val);
        }

        /// One-directional binding: whenever `self` changes, set `target` to
        /// the new value.  Allocates one slot in `self.changed`.
        ///
        /// The binding is permanent for the lifetime of both Properties.
        /// To unbind, call `self.changed.disconnectHandle(alloc, handle)` using
        /// the Connection returned by the underlying connect() call, or use
        /// `self.changed.disconnect(alloc, target)`.
        pub fn bind(self: *Self, alloc: std.mem.Allocator, target: *Self) !void {
            _ = try self.changed.connect(alloc, target, struct {
                fn setter(t: *Self, v: T) void {
                    t.set(v);
                }
            }.setter);
        }

        // ------------------------------------------------------------------
        // Internal helpers
        // ------------------------------------------------------------------

        fn valuesEqual(a: T, b: T) bool {
            const info = @typeInfo(T);
            // Slice types — compare element-by-element
            if (info == .pointer and info.pointer.size == .slice) {
                return std.mem.eql(info.pointer.child, a, b);
            }
            return a == b;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Property get/set scalar" {
    var prop: Property(i32) = Property(i32).init(0);
    defer prop.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(i32, 0), prop.get());
    prop.set(42);
    try std.testing.expectEqual(@as(i32, 42), prop.get());
}

test "Property set fires changed signal" {
    const alloc = std.testing.allocator;
    var prop: Property(i32) = Property(i32).init(0);
    defer prop.deinit(alloc);

    var seen: i32 = -1;
    _ = try prop.changed.connect(alloc, &seen, struct {
        fn f(p: *i32, v: i32) void { p.* = v; }
    }.f);

    prop.set(7);
    try std.testing.expectEqual(@as(i32, 7), seen);
}

test "Property equal set is silent" {
    const alloc = std.testing.allocator;
    var prop: Property(i32) = Property(i32).init(5);
    defer prop.deinit(alloc);

    var count: u32 = 0;
    _ = try prop.changed.connect(alloc, &count, struct {
        fn f(p: *u32, _: i32) void { p.* += 1; }
    }.f);

    prop.set(5); // same value — should not fire
    try std.testing.expectEqual(@as(u32, 0), count);

    prop.set(6); // different — should fire
    try std.testing.expectEqual(@as(u32, 1), count);
}

test "Property bind propagates value" {
    const alloc = std.testing.allocator;
    var src: Property(f32) = Property(f32).init(0.0);
    defer src.deinit(alloc);
    var dst: Property(f32) = Property(f32).init(0.0);
    defer dst.deinit(alloc);

    try src.bind(alloc, &dst);

    src.set(3.14);
    try std.testing.expectApproxEqAbs(@as(f32, 3.14), dst.get(), 1e-6);
}

test "Property slice equality" {
    const alloc = std.testing.allocator;
    var prop: Property([]const u8) = Property([]const u8).init("hello");
    defer prop.deinit(alloc);

    var count: u32 = 0;
    _ = try prop.changed.connect(alloc, &count, struct {
        fn f(p: *u32, _: []const u8) void { p.* += 1; }
    }.f);

    prop.set("hello"); // same content — silent
    try std.testing.expectEqual(@as(u32, 0), count);

    prop.set("world"); // different content — fires
    try std.testing.expectEqual(@as(u32, 1), count);
}
