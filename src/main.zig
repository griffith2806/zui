const std = @import("std");
const zui = @import("zui");

// ── WinUI-style dark theme palette ──────────────────────────────────────────
const BG        = zui.Color.rgb(32,  32,  32);   // window background
const BG_CARD   = zui.Color.rgb(44,  44,  44);   // card / panel surface
const BG_HEADER = zui.Color.rgb(24,  24,  24);   // title-bar strip
const ACCENT    = zui.Color.rgb( 0, 120, 212);   // Windows 11 accent blue
const FG        = zui.Color.rgb(255, 255, 255);  // primary text
const FG_MUTED  = zui.Color.rgb(160, 160, 160);  // secondary text
const DIVIDER   = zui.Color.rgb( 60,  60,  60);  // subtle dividers

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    var app = try zui.Application.init(alloc, .{
        .title  = "zui — Dashboard",
        .width  = 720,
        .height = 500,
    });
    defer app.deinit();

    // ── Widgets ──────────────────────────────────────────────────────────────
    var btn_increment = zui.Button{
        .label = "Increment",
        .style = .{ .bg = ACCENT, .bg_hover = zui.Color.rgb(0, 140, 240),
                    .bg_press = zui.Color.rgb(0, 100, 180), .fg = FG },
    };
    var btn_reset = zui.Button{ .label = "Reset" };
    var btn_about = zui.Button{ .label = "About" };

    // ── State ────────────────────────────────────────────────────────────────
    var counter: i32 = 0;
    var about_visible = false;

    try btn_increment.clicked.connect(alloc, &counter, struct {
        fn inc(p: *i32, _: void) void { p.* += 1; }
    }.inc);
    try btn_reset.clicked.connect(alloc, &counter, struct {
        fn rst(p: *i32, _: void) void { p.* = 0; }
    }.rst);
    try btn_about.clicked.connect(alloc, &about_visible, struct {
        fn tog(p: *bool, _: void) void { p.* = !p.*; }
    }.tog);

    // ── Layout constants ─────────────────────────────────────────────────────
    const HEADER_H: u32 = 40;
    const NAV_W:    u32 = 160;
    const PAD:      i32 = 24;

    const inc_rect  = zui.Rect.init(PAD, 220, 120, 32);
    const rst_rect  = zui.Rect.init(PAD + 128, 220, 80, 32);
    const about_rect = zui.Rect.init(720 - 96 - PAD, 220, 88, 32);

    while (!app.window.should_close) {
        // ── Events ───────────────────────────────────────────────────────────
        while (app.pollEvent()) |ev| {
            switch (ev) {
                .close     => app.window.should_close = true,
                .key_press => |k| { if (k.key == .escape) app.window.should_close = true; },
                else => {},
            }
            _ = btn_increment.handleEvent(ev, inc_rect);
            _ = btn_reset.handleEvent(ev, rst_rect);
            _ = btn_about.handleEvent(ev, about_rect);
        }

        // ── Draw background ───────────────────────────────────────────────────
        app.renderer.clear(BG);

        // ── Header bar ────────────────────────────────────────────────────────
        app.renderer.fillRect(zui.Rect.init(0, 0, 720, HEADER_H), BG_HEADER);
        app.renderer.fillRect(zui.Rect.init(0, HEADER_H, 720, 1), DIVIDER);
        app.renderer.drawText("zui", 16, 16, FG);
        app.renderer.drawText("Dashboard", 60, 16, FG_MUTED);

        // ── Left nav strip ────────────────────────────────────────────────────
        app.renderer.fillRect(zui.Rect.init(0, HEADER_H, NAV_W, 500 - HEADER_H), zui.Color.rgb(40, 40, 40));
        app.renderer.fillRect(zui.Rect.init(NAV_W, HEADER_H, 1, 500 - HEADER_H), DIVIDER);
        app.renderer.drawText("Home",     12, 60,  FG);
        app.renderer.drawText("Counter",  12, 84,  ACCENT);  // active item
        app.renderer.drawText("Settings", 12, 108, FG_MUTED);

        // Active item indicator
        app.renderer.fillRect(zui.Rect.init(0, 80, 3, 16), ACCENT);

        // ── Main content area ─────────────────────────────────────────────────
        const cx: i32 = NAV_W + PAD;

        // Page title
        app.renderer.drawText("Counter", cx, 60, FG);
        app.renderer.fillRect(zui.Rect.init(cx, 72, 400, 1), DIVIDER);

        // Card background
        const card = zui.Rect.init(cx, 90, 400, 160);
        app.renderer.fillRect(card, BG_CARD);
        // Card border
        app.renderer.fillRect(zui.Rect.init(card.x, card.y, card.width, 1), DIVIDER);
        app.renderer.fillRect(zui.Rect.init(card.x, card.bottom() - 1, card.width, 1), DIVIDER);
        app.renderer.fillRect(zui.Rect.init(card.x, card.y, 1, card.height), DIVIDER);
        app.renderer.fillRect(zui.Rect.init(card.right() - 1, card.y, 1, card.height), DIVIDER);

        // Counter value — large display
        var count_buf: [32]u8 = undefined;
        const count_str = std.fmt.bufPrint(&count_buf, "{d}", .{counter}) catch "?";
        // Scale up by repeating the digit 3× for a bolder look
        const digit_x = card.x + @as(i32, @intCast((card.width - count_str.len * 24) / 2));
        drawLarge(&app.renderer, count_str, digit_x, card.y + 30, FG);

        app.renderer.drawText("click Increment to count up", cx + 12, card.y + 100, FG_MUTED);

        // ── Buttons ───────────────────────────────────────────────────────────
        btn_increment.draw(&app.renderer, inc_rect);
        btn_reset.draw(&app.renderer, rst_rect);
        btn_about.draw(&app.renderer, about_rect);

        // ── About overlay ─────────────────────────────────────────────────────
        if (about_visible) {
            const overlay = zui.Rect.init(180, 130, 360, 160);
            app.renderer.fillRect(overlay, zui.Color.rgb(50, 50, 55));
            app.renderer.fillRect(zui.Rect.init(overlay.x, overlay.y, overlay.width, 1), ACCENT);
            app.renderer.drawText("About zui",          overlay.x + 16, overlay.y + 16,  FG);
            app.renderer.drawText("A Qt-inspired UI",   overlay.x + 16, overlay.y + 40,  FG_MUTED);
            app.renderer.drawText("framework for Zig.", overlay.x + 16, overlay.y + 56,  FG_MUTED);
            app.renderer.drawText("Milestone 2",        overlay.x + 16, overlay.y + 80,  FG_MUTED);
            app.renderer.drawText("Press About to close.", overlay.x + 16, overlay.y + 120, FG_MUTED);
        }

        app.present();
    }
}

// Draw text scaled 3× horizontally and 3× vertically for a large counter display.
fn drawLarge(r: *zui.Renderer, text: []const u8, x: i32, y: i32, color: zui.Color) void {
    const scale = 3;
    for (text, 0..) |_, i| {
        r.drawText(text[i .. i + 1], x + @as(i32, @intCast(i * 8 * scale)), y, color);
        // repeat rows to scale vertically
        var row: i32 = 1;
        while (row < scale) : (row += 1) {
            r.drawText(text[i .. i + 1], x + @as(i32, @intCast(i * 8 * scale)), y + row, color);
        }
    }
}
