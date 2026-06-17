/// Cocoa platform module — re-exports Window and EventLoop so consumers can
/// write:
///
///   const cocoa = @import("platform/cocoa/platform.zig");
///   const Window    = cocoa.Window;
///   const EventLoop = cocoa.EventLoop;
///
/// This mirrors the pattern used by the win32 and x11 backends where
/// src/core/app.zig selects the right Window type via a comptime os.tag switch.

pub const Window    = @import("window.zig").Window;
pub const EventLoop = @import("event_loop.zig").EventLoop;
