const std    = @import("std");
const builtin = @import("builtin");
const event_mod = @import("../../events/event.zig");
const node_mod  = @import("../../accessibility/node.zig");

comptime {
    if (builtin.os.tag != .macos) @compileError("cocoa platform backend is macOS-only");
}

const Event = event_mod.Event;

// ── Cocoa / AppKit opaque handle types ──────────────────────────────────────
//
// These are declared as opaque pointer types so we do not need to @cInclude
// Objective-C headers.  The fields that hold them are typed as ?*anyopaque and
// are only meaningful when a real Cocoa implementation is wired up.
//
// On a real macOS build the window would hold an NSWindow*, NSView*, and a
// pixel buffer (CGBitmapContext / MTKView, etc.).  For now all methods stub
// out with @panic so the skeleton compiles without pulling in any framework.

const MAX_EVENTS = 128;

/// Cocoa platform window skeleton.  Interface mirrors src/platform/win32/window.zig
/// so src/core/app.zig can select this backend via a comptime os.tag switch.
pub const Window = struct {
    /// Raw pixel buffer — software renderer writes here.
    pixels:       [*]u32   = undefined,
    /// Logical (device-independent) width in points.
    width:        u32      = 0,
    /// Logical (device-independent) height in points.
    height:       u32      = 0,
    /// True after a resize event is processed; cleared by app.syncSize().
    size_changed: bool     = false,
    /// Backing scale factor (1.0 on non-Retina, 2.0 on Retina, etc.).
    dpi_scale:    f32      = 1.0,
    /// Mirrors win32 should_close for portable app loop.
    should_close: bool     = false,

    // Opaque Cocoa handles — untyped until a real implementation is provided.
    /// NSWindow* (opaque until impl lands).
    nswindow: ?*anyopaque = null,
    /// NSView* / custom CALayer-backed view (opaque until impl lands).
    nsview:   ?*anyopaque = null,
    /// dc_mem equivalent — unused on Cocoa; present for cross-platform field
    /// compatibility in app.zig guards.
    dc_mem:   *anyopaque  = undefined,
    /// hwnd equivalent — points to nswindow for renderer backends that need it.
    hwnd:     *anyopaque  = undefined,

    ev_buf:  [MAX_EVENTS]Event = undefined,
    ev_head: u32 = 0,
    ev_tail: u32 = 0,

    /// Create a new window with the given title and logical size.
    ///
    /// On macOS this would call:
    ///   NSApplication.sharedApplication, NSWindow initWithContentRect:...,
    ///   set the delegate, make key and order front, and allocate a pixel buffer.
    pub fn create(
        alloc: std.mem.Allocator,
        title: []const u8,
        width: u32,
        height: u32,
    ) !*Window {
        _ = alloc; _ = title; _ = width; _ = height;
        @panic("Cocoa backend not yet implemented");
    }

    /// Destroy the window and free all associated resources.
    pub fn deinit(self: *Window, alloc: std.mem.Allocator) void {
        _ = self; _ = alloc;
        @panic("Cocoa backend not yet implemented");
    }

    /// Drain pending NSEvents and translate them into zui Events.
    /// Returns null when the queue is empty.
    pub fn pollEvent(self: *Window) ?Event {
        _ = self;
        @panic("Cocoa backend not yet implemented");
    }

    /// For the software backend: blit the pixel buffer to screen.
    /// Returns null — Cocoa software path does not use a GDI DC for text.
    pub fn present(self: *Window) ?*anyopaque {
        _ = self;
        @panic("Cocoa backend not yet implemented");
    }

    /// Called after present() to complete the frame blit.
    pub fn releasePresent(self: *Window, dc: *anyopaque) void {
        _ = self; _ = dc;
        @panic("Cocoa backend not yet implemented");
    }

    /// Resize the backing pixel buffer to the new physical dimensions.
    /// Called internally when a resize NSEvent is received.
    pub fn resizeDIB(self: *Window, new_w: u32, new_h: u32) void {
        _ = self; _ = new_w; _ = new_h;
        @panic("Cocoa backend not yet implemented");
    }

    // ── Accessibility (NSAccessibility / AXUIElement) ────────────────────────
    // These are no-ops until macOS accessibility support is implemented.

    pub fn initUia(self: *Window, alloc: std.mem.Allocator, title: []const u8) !void {
        _ = self; _ = alloc; _ = title;
        // No-op skeleton — macOS accessibility wired separately via NSAccessibility.
    }

    pub fn deinitUia(self: *Window) void {
        _ = self;
    }

    pub fn updateAccessibility(self: *Window, nodes: []const node_mod.AccessNode) void {
        _ = self; _ = nodes;
    }

    // ── Internal helpers ─────────────────────────────────────────────────────

    fn popEvent(self: *Window) Event {
        const ev = self.ev_buf[self.ev_head & (MAX_EVENTS - 1)];
        self.ev_head +%= 1;
        return ev;
    }

    fn pushEvent(self: *Window, ev: Event) void {
        const next = (self.ev_tail +% 1) & (MAX_EVENTS - 1);
        if (next == self.ev_head & (MAX_EVENTS - 1)) return; // drop when full
        self.ev_buf[self.ev_tail & (MAX_EVENTS - 1)] = ev;
        self.ev_tail +%= 1;
    }
};
