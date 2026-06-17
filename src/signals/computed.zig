const std = @import("std");
const Signal = @import("signal.zig").Signal;

// ---------------------------------------------------------------------------
// Computed(T) — a lazily-evaluated derived value.
//
// A Computed holds a cached value of type T and a user-supplied compute
// function.  When any registered source Property changes, the Computed is
// marked dirty.  The cached value is NOT recomputed immediately; it is
// recomputed on the next call to `get()`.
//
// This avoids a full runtime dependency graph: the user wires sources
// manually via `addSource()`.
//
// Design constraints (matching zui "no hidden allocations" rule):
//   - The compute function is a comptime-known fn pointer + a type-erased
//     context pointer stored at construction time.
//   - Sources are registered via `addSource()` which allocates one Signal
//     slot per source Property.
//   - `get()` never allocates.
//   - `deinit()` must be called with the same allocator used in addSource().
//
// Typical usage:
//
//   var x: Property(i32) = Property(i32).init(2);
//
//   const Ctx = struct { src: *Property(i32) };
//   var ctx = Ctx{ .src = &x };
//
//   var doubled = Computed(i32).init(@ptrCast(&ctx), struct {
//       fn f(raw: *anyopaque) i32 {
//           const c: *Ctx = @ptrCast(@alignCast(raw));
//           return c.src.get() * 2;
//       }
//   }.f);
//
//   try doubled.addSource(alloc, &x);
//   defer doubled.deinit(alloc);
//
//   _ = doubled.get();  // 4
//   x.set(5);
//   _ = doubled.get();  // 10 — dirty, recomputed
//
// ---------------------------------------------------------------------------
pub fn Computed(comptime T: type) type {
    return struct {
        const Self = @This();

        // Bookkeeping entry for a single source connection.
        // We only need to remember the ctx pointer (Self) used for the Signal
        // connection so that deinit can call disconnect on each source.
        const SourceEntry = struct {
            // Type-erased pointer to the source Signal (Signal(S) for some S).
            signal_ptr: *anyopaque,
            // Disconnect function: removes `self` from the source signal.
            disconnect_fn: *const fn (*anyopaque, *anyopaque, std.mem.Allocator) void,
        };

        // Fixed at init time
        ctx:        *anyopaque,
        compute_fn: *const fn (*anyopaque) T,

        // Cache
        cached: T,
        dirty:  bool,

        // Source registrations
        sources: std.ArrayListUnmanaged(SourceEntry),

        /// Create a Computed with the given context and compute function.
        /// The initial cached value is obtained by calling compute_fn immediately.
        /// No allocation — sources list starts empty.
        pub fn init(ctx: *anyopaque, compute_fn: *const fn (*anyopaque) T) Self {
            return .{
                .ctx        = ctx,
                .compute_fn = compute_fn,
                .cached     = compute_fn(ctx),
                .dirty      = false,
                .sources    = .empty,
            };
        }

        /// Free all resources.  Must be called with the same allocator that
        /// was passed to addSource() calls.
        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            for (self.sources.items) |entry| {
                entry.disconnect_fn(entry.signal_ptr, self, alloc);
            }
            self.sources.deinit(alloc);
        }

        /// Return the cached (possibly recomputed) value.  Never allocates.
        pub fn get(self: *Self) T {
            if (self.dirty) {
                self.cached = self.compute_fn(self.ctx);
                self.dirty  = false;
            }
            return self.cached;
        }

        /// Manually mark the computed value as dirty, forcing a recompute on
        /// the next get() call.  Useful when the compute function reads
        /// mutable state that isn't itself a Property.
        pub fn invalidate(self: *Self) void {
            self.dirty = true;
        }

        /// Wire up a source Property so that any change to `source` marks
        /// this Computed dirty.  Allocates one Signal slot.
        ///
        /// `source` must be `*Property(S)` for some type S.  S does NOT need
        /// to match T.  The compute_fn is responsible for reading the updated
        /// value from its ctx.
        pub fn addSource(
            self: *Self,
            alloc: std.mem.Allocator,
            source: anytype,
        ) !void {
            // Determine S = the payload type of the source Property.
            // Property(T) exposes `pub const Payload = T` for exactly this purpose.
            const SourceProp = @typeInfo(@TypeOf(source)).pointer.child;
            const S = SourceProp.Payload;

            // Connect a slot that marks us dirty on any source change.
            _ = try source.changed.connect(alloc, self, struct {
                fn markDirty(computed_ptr: *Self, _: S) void {
                    computed_ptr.dirty = true;
                }
            }.markDirty);

            // Build a typed disconnect closure for deinit.
            const entry = SourceEntry{
                .signal_ptr = &source.changed,
                .disconnect_fn = struct {
                    fn disconnect(sig_raw: *anyopaque, ctx_raw: *anyopaque, a: std.mem.Allocator) void {
                        const sig: *Signal(S) = @ptrCast(@alignCast(sig_raw));
                        sig.disconnect(a, ctx_raw);
                    }
                }.disconnect,
            };
            try self.sources.append(alloc, entry);
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const Property = @import("property.zig").Property;

test "Computed basic derive" {
    const alloc = std.testing.allocator;

    var x: Property(i32) = Property(i32).init(2);
    defer x.deinit(alloc);

    // Compute: x.value * 3
    const Ctx = struct { src: *Property(i32) };
    var ctx = Ctx{ .src = &x };

    var doubled = Computed(i32).init(@ptrCast(&ctx), struct {
        fn f(raw: *anyopaque) i32 {
            const c: *Ctx = @ptrCast(@alignCast(raw));
            return c.src.get() * 3;
        }
    }.f);

    try doubled.addSource(alloc, &x);
    defer doubled.deinit(alloc);

    try std.testing.expectEqual(@as(i32, 6), doubled.get());

    x.set(5);
    try std.testing.expectEqual(@as(i32, 15), doubled.get());
}

test "Computed stays cached until source changes" {
    const alloc = std.testing.allocator;

    var count: u32 = 0; // track recompute calls
    var x: Property(i32) = Property(i32).init(1);
    defer x.deinit(alloc);

    const Ctx = struct { src: *Property(i32), calls: *u32 };
    var ctx = Ctx{ .src = &x, .calls = &count };

    var c = Computed(i32).init(@ptrCast(&ctx), struct {
        fn f(raw: *anyopaque) i32 {
            const p: *Ctx = @ptrCast(@alignCast(raw));
            p.calls.* += 1;
            return p.src.get();
        }
    }.f);

    try c.addSource(alloc, &x);
    defer c.deinit(alloc);

    // init already called compute once (count == 1)
    _ = c.get(); // cache hit — no extra call
    _ = c.get(); // cache hit — no extra call
    try std.testing.expectEqual(@as(u32, 1), count);

    x.set(2); // marks dirty
    _ = c.get(); // recompute
    try std.testing.expectEqual(@as(u32, 2), count);
    _ = c.get(); // cache hit again
    try std.testing.expectEqual(@as(u32, 2), count);
}

test "Computed manual invalidate" {
    const alloc = std.testing.allocator;

    var x: Property(i32) = Property(i32).init(10);
    defer x.deinit(alloc);

    const Ctx = struct { src: *Property(i32) };
    var ctx = Ctx{ .src = &x };

    var c = Computed(i32).init(@ptrCast(&ctx), struct {
        fn f(raw: *anyopaque) i32 {
            const p: *Ctx = @ptrCast(@alignCast(raw));
            return p.src.get();
        }
    }.f);
    defer c.deinit(alloc);

    try std.testing.expectEqual(@as(i32, 10), c.get());

    c.invalidate();
    try std.testing.expect(c.dirty);
    try std.testing.expectEqual(@as(i32, 10), c.get()); // recompute, still 10
    try std.testing.expect(!c.dirty);
}
