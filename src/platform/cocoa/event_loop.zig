const std    = @import("std");
const builtin = @import("builtin");
const window_mod = @import("window.zig");

comptime {
    if (builtin.os.tag != .macos) @compileError("cocoa platform backend is macOS-only");
}

/// Cocoa event loop skeleton.
///
/// On a real macOS build this would call:
///   [NSApplication run] for a blocking loop, or
///   [NSApp nextEventMatchingMask:...] in a polling loop to match the
///   zui pollEvent() model.
///
/// For now all methods @panic so the skeleton compiles without a real
/// NSRunLoop integration.
pub const EventLoop = struct {
    /// Reference to the application window whose event queue receives events.
    window: *window_mod.Window,

    pub fn init(window: *window_mod.Window) EventLoop {
        return .{ .window = window };
    }

    /// Poll for a single pending event without blocking.
    /// Translates the next NSEvent into a zui Event and pushes it into the
    /// window event queue, then returns the event (or null if none pending).
    pub fn poll(self: *EventLoop) bool {
        _ = self;
        @panic("Cocoa backend not yet implemented");
    }

    /// Run the NSRunLoop until the window's should_close flag is set.
    /// Equivalent to [NSApp run] but yields after each event so the caller
    /// can interleave rendering.
    pub fn run(self: *EventLoop) void {
        _ = self;
        @panic("Cocoa backend not yet implemented");
    }

    pub fn deinit(self: *EventLoop) void {
        _ = self;
    }
};
