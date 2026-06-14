const std     = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const event_mod = @import("../events/event.zig");

const Window = switch (builtin.os.tag) {
    .windows => @import("../platform/win32/window.zig").Window,
    else     => @compileError("no platform backend for this OS yet — add src/platform/<os>/window.zig"),
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
    alloc:    std.mem.Allocator,
    window:   *Window,
    renderer: Renderer,

    pub fn init(alloc: std.mem.Allocator, config: Config) !Application {
        const win = try Window.create(alloc, config.title, config.width, config.height);
        errdefer win.deinit(alloc);

        const renderer = switch (build_options.backend) {
            .software => Renderer.init(win.pixels, win.width, win.height),
            .opengl   => try Renderer.init(win.hwnd, win.width, win.height),
        };

        return .{ .alloc = alloc, .window = win, .renderer = renderer };
    }

    pub fn deinit(self: *Application) void {
        self.window.deinit(self.alloc);
    }

    pub fn pollEvent(self: *Application) ?event_mod.Event {
        return self.window.pollEvent();
    }

    pub fn present(self: *Application) void {
        switch (build_options.backend) {
            .software => self.window.present(),
            .opengl   => self.renderer.present(),
        }
    }
};
