const std = @import("std");
const builtin = @import("builtin");
const event_mod    = @import("../events/event.zig");
const color_mod    = @import("../style/color.zig");
const renderer_mod = @import("../graphics/software/renderer.zig");

const Window = switch (builtin.os.tag) {
    .windows => @import("../platform/win32/window.zig").Window,
    else     => @compileError("no platform backend for this OS yet — add src/platform/<os>/window.zig"),
};

pub const Config = struct {
    title:  []const u8 = "zui",
    width:  u32 = 800,
    height: u32 = 600,
};

pub const Application = struct {
    alloc:    std.mem.Allocator,
    window:   *Window,
    renderer: renderer_mod.Renderer,

    pub fn init(alloc: std.mem.Allocator, config: Config) !Application {
        const win = try Window.create(alloc, config.title, config.width, config.height);
        return .{
            .alloc    = alloc,
            .window   = win,
            .renderer = renderer_mod.Renderer.init(win.pixels, win.width, win.height),
        };
    }

    pub fn deinit(self: *Application) void {
        self.window.deinit(self.alloc);
    }

    pub fn pollEvent(self: *Application) ?event_mod.Event {
        return self.window.pollEvent();
    }

    pub fn present(self: *Application) void {
        self.window.present();
    }
};
