const std = @import("std");
const zui = @import("zui");

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    var app = try zui.Application.init(alloc, .{
        .title  = "zui — Dashboard",
        .width  = 800,
        .height = 560,
    });
    defer app.deinit();

    // ── Theme state ──────────────────────────────────────────────────────────
    var dark_mode = true;

    // ── Widgets ──────────────────────────────────────────────────────────────
    var btn_increment = zui.Button{ .label = "Increment" };
    var btn_reset     = zui.Button{ .label = "Reset" };
    var btn_theme     = zui.Button{ .label = "Toggle Theme" };
    var btn_about     = zui.Button{ .label = "About" };
    var field_name    = zui.TextField{};
    defer field_name.deinit(alloc);

    var counter: i32 = 0;
    var about_visible = false;

    try btn_increment.clicked.connect(alloc, &counter,        struct { fn f(p: *i32,  _: void) void { p.* += 1; }         }.f);
    try btn_reset.clicked.connect    (alloc, &counter,        struct { fn f(p: *i32,  _: void) void { p.* = 0; }          }.f);
    try btn_theme.clicked.connect    (alloc, &dark_mode,      struct { fn f(p: *bool, _: void) void { p.* = !p.*; }       }.f);
    try btn_about.clicked.connect    (alloc, &about_visible,  struct { fn f(p: *bool, _: void) void { p.* = !p.*; }       }.f);
    defer btn_increment.deinit(alloc);
    defer btn_reset.deinit(alloc);
    defer btn_theme.deinit(alloc);
    defer btn_about.deinit(alloc);

    // ── Layout constants ─────────────────────────────────────────────────────
    const W: u32   = 800;
    const H: u32   = 560;
    const HDR: u32 = 40;
    const NAV: u32 = 160;
    const PAD: i32 = 20;
    const CX:  i32 = @as(i32, NAV) + PAD;

    // Button rects (in client coords)
    const inc_rect   = zui.Rect.init(CX,           HDR + 230, 110, 30);
    const rst_rect   = zui.Rect.init(CX + 118,     HDR + 230, 80,  30);
    const theme_rect = zui.Rect.init(CX,           HDR + 270, 140, 30);
    const about_rect = zui.Rect.init(@as(i32,W) - 100 - PAD, HDR + 270, 92, 30);
    const name_rect  = zui.Rect.init(CX,           HDR + 320, 280, 30);

    // Grid demo: 4 cells in a 2×2 grid inside a container
    const grid_container = zui.Rect.init(CX, HDR + 360, 400, 120);
    const grid_layout    = zui.GridLayout{ .cols = 2, .rows = 2, .gap = 6, .padding = 10 };
    var grid_rects: [4]zui.Rect = undefined;
    const grid_labels = [4][]const u8{ "Rect", "Color", "Layout", "Signal" };

    while (!app.window.should_close) {
        const theme = if (dark_mode) zui.Theme.dark else zui.Theme.light;

        // ── Apply dynamic button colours from theme ──────────────────────────
        btn_increment.style = .{ .bg = theme.accent,   .bg_hover = zui.Color.rgb(0, 140, 240), .bg_press = zui.Color.rgb(0, 100, 180), .fg = zui.Color.white };
        btn_reset.style     = .{ .bg = theme.btn_bg,   .bg_hover = theme.btn_hover, .bg_press = theme.btn_press, .fg = theme.fg };
        btn_theme.style     = .{ .bg = theme.btn_bg,   .bg_hover = theme.btn_hover, .bg_press = theme.btn_press, .fg = theme.fg };
        btn_about.style     = .{ .bg = theme.btn_bg,   .bg_hover = theme.btn_hover, .bg_press = theme.btn_press, .fg = theme.fg };

        // ── Events ───────────────────────────────────────────────────────────
        while (app.pollEvent()) |ev| {
            switch (ev) {
                .close     => app.window.should_close = true,
                .key_press => |k| { if (k.key == .escape) app.window.should_close = true; },
                else => {},
            }
            _ = btn_increment.handleEvent(ev, inc_rect);
            _ = btn_reset.handleEvent(ev, rst_rect);
            _ = btn_theme.handleEvent(ev, theme_rect);
            _ = btn_about.handleEvent(ev, about_rect);
            _ = field_name.handleEvent(ev, name_rect, alloc);
        }

        // ── Recompute grid each frame (cheap; rects are static here) ────────
        grid_layout.compute(grid_container, &grid_rects);

        // ── Draw background ───────────────────────────────────────────────────
        app.renderer.clear(theme.bg);

        // ── Header bar ────────────────────────────────────────────────────────
        app.renderer.fillRect(zui.Rect.init(0, 0, W, HDR), theme.bg_header);
        app.renderer.fillRect(zui.Rect.init(0, HDR, W, 1), theme.divider);
        app.renderer.drawText("zui",       16, 16, theme.fg);
        app.renderer.drawText("Dashboard", 60, 16, theme.fg_muted);

        // ── Left nav strip ────────────────────────────────────────────────────
        app.renderer.fillRect(zui.Rect.init(0, HDR, NAV, H - HDR), zui.Color.rgb(
            if (dark_mode) @as(u8, 40) else @as(u8, 235),
            if (dark_mode) @as(u8, 40) else @as(u8, 235),
            if (dark_mode) @as(u8, 40) else @as(u8, 238),
        ));
        app.renderer.fillRect(zui.Rect.init(NAV, HDR, 1, H - HDR), theme.divider);
        app.renderer.drawText("Home",     12, @as(i32, HDR) + 20, theme.fg_muted);
        app.renderer.drawText("Counter",  12, @as(i32, HDR) + 44, theme.accent);
        app.renderer.drawText("Settings", 12, @as(i32, HDR) + 68, theme.fg_muted);
        app.renderer.fillRect(zui.Rect.init(0, @as(i32, HDR) + 40, 3, 16), theme.accent);

        // ── Page title ────────────────────────────────────────────────────────
        app.renderer.drawText("Counter", CX, @as(i32, HDR) + 12, theme.fg);
        app.renderer.fillRect(zui.Rect.init(CX, @as(i32, HDR) + 22, 420, 1), theme.divider);

        // ── Counter card ─────────────────────────────────────────────────────
        const card = zui.Rect.init(CX, @as(i32, HDR) + 30, 420, 100);
        const card_container = zui.Container{ .title = "Counter" };
        card_container.draw(&app.renderer, card, theme);
        const content = card_container.contentRect(card);

        var count_buf: [32]u8 = undefined;
        const count_str = std.fmt.bufPrint(&count_buf, "{d}", .{counter}) catch "?";
        const digit_x = content.x + @as(i32, @intCast((content.width -| count_str.len * 24) / 2));
        drawLarge(&app.renderer, count_str, digit_x, content.y + 8, theme.fg);
        app.renderer.drawText("click Increment to count up", content.x + 8, content.bottom() - 14, theme.fg_muted);

        // ── Buttons ───────────────────────────────────────────────────────────
        btn_increment.draw(&app.renderer, inc_rect);
        btn_reset.draw(&app.renderer, rst_rect);
        btn_theme.draw(&app.renderer, theme_rect);
        btn_about.draw(&app.renderer, about_rect);

        // ── Text field ────────────────────────────────────────────────────────
        app.renderer.drawText("Name:", CX, name_rect.y + 10, theme.fg_muted);
        const actual_name_rect = zui.Rect.init(CX + 50, name_rect.y, name_rect.width - 50, name_rect.height);
        field_name.draw(&app.renderer, actual_name_rect, theme);
        if (field_name.text.items.len > 0) {
            var greeting_buf: [64]u8 = undefined;
            const greeting = std.fmt.bufPrint(&greeting_buf, "Hello, {s}!", .{field_name.text.items}) catch "";
            app.renderer.drawText(greeting, CX + 50 + @as(i32, @intCast(name_rect.width - 50)) + 10, name_rect.y + 10, theme.accent);
        }

        // ── Grid layout demo ──────────────────────────────────────────────────
        const grid_outer = zui.Container{ .title = "GridLayout (2x2)" };
        grid_outer.draw(&app.renderer, grid_container, theme);
        const grid_inner = grid_outer.contentRect(grid_container);
        grid_layout.compute(grid_inner, &grid_rects);
        const cell_colors = [4]zui.Color{
            zui.Color.rgb(0, 120, 212),
            zui.Color.rgb(16, 124, 16),
            zui.Color.rgb(196, 43, 28),
            zui.Color.rgb(136, 23, 152),
        };
        for (&grid_rects, 0..) |cell, i| {
            app.renderer.fillRect(cell, cell_colors[i]);
            app.renderer.drawText(grid_labels[i], cell.x + 4, cell.y + 4, zui.Color.white);
        }

        // ── About overlay ─────────────────────────────────────────────────────
        if (about_visible) {
            const overlay = zui.Rect.init(200, 150, 380, 180);
            app.renderer.fillRect(overlay, zui.Color.rgb(50, 50, 55));
            app.renderer.fillRect(zui.Rect.init(overlay.x, overlay.y, overlay.width, 2), theme.accent);
            app.renderer.drawText("About zui",              overlay.x + 16, overlay.y + 16,  theme.fg);
            app.renderer.drawText("A Qt-inspired UI",       overlay.x + 16, overlay.y + 44,  theme.fg_muted);
            app.renderer.drawText("framework for Zig.",     overlay.x + 16, overlay.y + 60,  theme.fg_muted);
            app.renderer.drawText("Milestone 3: Theming,",  overlay.x + 16, overlay.y + 84,  theme.fg_muted);
            app.renderer.drawText("TextField, Container,",  overlay.x + 16, overlay.y + 100, theme.fg_muted);
            app.renderer.drawText("GridLayout.",            overlay.x + 16, overlay.y + 116, theme.fg_muted);
            app.renderer.drawText("Escape or About to close.", overlay.x + 16, overlay.y + 148, theme.fg_muted);
        }

        app.present();
    }
}

fn drawLarge(r: *zui.Renderer, text: []const u8, x: i32, y: i32, color: zui.Color) void {
    for (text, 0..) |_, i| {
        const gx = x + @as(i32, @intCast(i * 24));
        r.drawText(text[i .. i + 1], gx,     y,     color);
        r.drawText(text[i .. i + 1], gx + 1, y,     color);
        r.drawText(text[i .. i + 1], gx,     y + 1, color);
        r.drawText(text[i .. i + 1], gx + 1, y + 1, color);
        r.drawText(text[i .. i + 1], gx,     y + 2, color);
        r.drawText(text[i .. i + 1], gx + 1, y + 2, color);
    }
}
