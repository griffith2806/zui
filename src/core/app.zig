const std          = @import("std");
const builtin      = @import("builtin");
const build_options = @import("build_options");
const event_mod    = @import("../events/event.zig");

extern "kernel32" fn GetTickCount64() callconv(std.builtin.CallingConvention.winapi) u64;
extern "kernel32" fn Sleep(dwMs: u32) callconv(std.builtin.CallingConvention.winapi) void;

const Window = switch (builtin.os.tag) {
    .windows => @import("../platform/win32/window.zig").Window,
    .linux   => @import("../platform/x11/window.zig").Window,
    else     => @compileError("unsupported platform"),
};

const RendererMod = switch (build_options.backend) {
    .software => @import("../graphics/software/renderer.zig"),
    .opengl   => @import("../graphics/opengl/renderer.zig"),
};
pub const Renderer = RendererMod.Renderer;

pub const Config = struct {
    title:  []const u8 = "zui",
    width:  u32 = 800,
    height: u32 = 600,
};

pub const Application = struct {
    alloc:         std.mem.Allocator,
    window:        *Window,
    renderer:      Renderer,
    last_tick_ms:  i64 = 0,

    pub fn init(alloc: std.mem.Allocator, config: Config) !Application {
        const win = try Window.create(alloc, config.title, config.width, config.height);
        errdefer win.deinit(alloc);

        var renderer = switch (build_options.backend) {
            .software => Renderer.init(win.pixels, win.width, win.height),
            .opengl   => try Renderer.init(win.hwnd, win.width, win.height),
        };

        // GDI text is Win32-only; on other platforms the bitmap font fallback is used.
        if (comptime (builtin.os.tag == .windows and build_options.backend == .software)) {
            renderer.initGdi(@ptrCast(win.dc_mem), win.dpi_scale);
        }

        return .{ .alloc = alloc, .window = win, .renderer = renderer };
    }

    pub fn deinit(self: *Application) void {
        switch (build_options.backend) {
            .software => self.renderer.deinit(),
            .opengl   => self.renderer.deinit(),
        }
        self.window.deinit(self.alloc);
    }

    pub fn pollEvent(self: *Application) ?event_mod.Event {
        return self.window.pollEvent();
    }

    /// Returns seconds elapsed since the previous call (capped at 0.1 s).
    pub fn deltaSeconds(self: *Application) f32 {
        const now: i64 = @intCast(GetTickCount64());
        const dt: f32 = if (self.last_tick_ms == 0) 0.016
                        else @as(f32, @floatFromInt(now - self.last_tick_ms)) / 1000.0;
        self.last_tick_ms = now;
        return @min(dt, 0.1);
    }

    /// Propagate a window resize to the renderer.  Call once per frame before drawing.
    pub fn syncSize(self: *Application) void {
        if (!self.window.size_changed) return;
        self.window.size_changed = false;
        switch (build_options.backend) {
            .software => self.renderer.resize(self.window.pixels, self.window.width, self.window.height),
            .opengl   => self.renderer.resize(self.window.width, self.window.height),
        }
    }

    pub fn present(self: *Application) void {
        switch (build_options.backend) {
            .software => {
                if (comptime builtin.os.tag == .windows) {
                    // BitBlt DIB → screen DC, flush queued GDI text with ClearType.
                    if (self.window.present()) |screen_dc| {
                        self.renderer.flushText(screen_dc);
                        self.window.releasePresent(screen_dc);
                    }
                } else {
                    _ = self.window.present();
                }
            },
            .opengl => self.renderer.present(),
        }
    }

    /// Sleep until the next frame slot to cap at `target_fps`.
    /// Call immediately after present().  Uses the timestamp recorded by
    /// deltaSeconds() at the start of the frame as the reference point.
    pub fn capFps(self: *const Application, target_fps: u32) void {
        if (target_fps == 0) return;
        const target_ms: i64 = @intCast(1000 / target_fps);
        const now: i64 = @intCast(GetTickCount64());
        const elapsed = now - self.last_tick_ms;
        if (elapsed < target_ms) {
            Sleep(@intCast(target_ms - elapsed));
        }
    }
};
