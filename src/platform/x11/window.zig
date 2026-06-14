const std    = @import("std");
const builtin = @import("builtin");
const event_mod = @import("../../events/event.zig");

comptime {
    if (builtin.os.tag != .linux) @compileError("x11 platform backend is Linux-only");
}

const Event = event_mod.Event;

/// Stub X11 window — interface mirrors win32/window.zig so src/core/app.zig
/// can switch on builtin.os.tag at comptime.  All methods panic until a real
/// X11 implementation is provided.
pub const Window = struct {
    pixels:       [*]u32          = undefined,
    width:        u32             = 0,
    height:       u32             = 0,
    size_changed: bool            = false,
    /// Unused on X11 (Win32 GDI memory DC); present to satisfy app.zig field
    /// access that is guarded by a comptime os.tag check.
    dc_mem:       *anyopaque      = undefined,
    /// On X11 this would be an XID or Display pointer; unused until impl lands.
    hwnd:         *anyopaque      = undefined,

    pub fn create(
        alloc: std.mem.Allocator,
        title: []const u8,
        width: u32,
        height: u32,
    ) !*Window {
        _ = alloc; _ = title; _ = width; _ = height;
        @panic("X11 backend not yet implemented");
    }

    pub fn deinit(self: *Window, alloc: std.mem.Allocator) void {
        _ = self; _ = alloc;
        @panic("X11 backend not yet implemented");
    }

    pub fn pollEvent(self: *Window) ?Event {
        _ = self;
        @panic("X11 backend not yet implemented");
    }

    /// Returns null — X11 software path does not use a GDI DC for text.
    pub fn present(self: *Window) ?*anyopaque {
        _ = self;
        @panic("X11 backend not yet implemented");
    }

    pub fn releasePresent(self: *Window, dc: *anyopaque) void {
        _ = self; _ = dc;
        @panic("X11 backend not yet implemented");
    }
};
