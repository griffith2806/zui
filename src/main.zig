const std = @import("std");
const zui = @import("zui");

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    var app = try zui.Application.init(alloc, .{
        .title  = "zui demo — Milestone 1",
        .width  = 800,
        .height = 600,
    });
    defer app.deinit();

    // Milestone 1: window appears with dark-blue background; Escape or X closes it.
    while (!app.window.should_close) {
        while (app.pollEvent()) |ev| {
            switch (ev) {
                .close     => app.window.should_close = true,
                .key_press => |k| { if (k.key == .escape) app.window.should_close = true; },
                else => {},
            }
        }
        app.renderer.clear(zui.Color.rgb(30, 30, 46));
        app.present();
    }
}
