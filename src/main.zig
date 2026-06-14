// zui Showcase — WPF UI–style component gallery
// Demonstrates: Theme, Navigation, Buttons, TextField, Checkbox, Slider,
//               BoxLayout, GridLayout, Signal(T), Color palette, Animations.

const std = @import("std");
const zui = @import("zui");

// ── Fluent dark palette ──────────────────────────────────────────────────────
const BG        = zui.Color.rgb( 20,  20,  20);
const BG_NAV    = zui.Color.rgb( 28,  28,  30);
const BG_CARD   = zui.Color.rgb( 36,  36,  38);
const BG_INPUT  = zui.Color.rgb( 30,  30,  32);
const ACCENT    = zui.Color.rgb(  0, 103, 192);
const ACCENT_HV = zui.Color.rgb(  0, 120, 215);
const ACCENT_PR = zui.Color.rgb(  0,  80, 160);
const FG        = zui.Color.rgb(255, 255, 255);
const FG_SEC    = zui.Color.rgb(178, 178, 185);
const FG_TER    = zui.Color.rgb(110, 110, 118);
const SEP       = zui.Color.rgb( 55,  55,  60);
const NAV_ITEM_H = zui.Color.rgb( 48,  48,  52);
const NAV_ITEM_A = zui.Color.rgb( 42,  42,  48);

const NAV_W: i32 = 220;
const HDR_H: i32 = 48;
var W: u32 = 1000;
var H: u32 = 620;

const Page = enum { dashboard, controls, colors, layout, about };

const NAV_ITEMS = [_]struct { label: []const u8, page: Page, icon: []const u8 }{
    .{ .label = "Dashboard", .page = .dashboard, .icon = "D" },
    .{ .label = "Controls",  .page = .controls,  .icon = "C" },
    .{ .label = "Colors",    .page = .colors,    .icon = "P" },
    .{ .label = "Layout",    .page = .layout,    .icon = "L" },
    .{ .label = "About",     .page = .about,     .icon = "A" },
};

// y of the "Architecture notes" label — must match drawAbout computation:
// expand_y = (HDR_H+16+144) + 9*22 + 16  = HDR_H + 374
const ABOUT_EXPAND_Y: i32 = HDR_H + 16 + 144 + 9 * 22 + 16;

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    var app = try zui.Application.init(alloc, .{
        .title  = "zui — Component Gallery",
        .width  = W,
        .height = H,
    });
    defer app.deinit();

    // ── State ─────────────────────────────────────────────────────────────────
    var page: Page = .dashboard;
    var dark_mode  = true;
    var counter: i32 = 0;
    var about_expanded = false;

    // ── Controls page widgets ─────────────────────────────────────────────────
    var field_search = zui.TextField{};
    defer field_search.deinit(alloc);
    var field_name = zui.TextField{};
    defer field_name.deinit(alloc);
    var slider_vol = zui.Slider{ .value = 0.62 };
    defer slider_vol.deinit(alloc);
    var cb_notify  = zui.Checkbox{ .label = "Enable notifications", .checked = true };
    defer cb_notify.deinit(alloc);
    var cb_compact = zui.Checkbox{ .label = "Compact mode" };
    defer cb_compact.deinit(alloc);

    // ── Buttons ────────────────────────────────────────────────────────────────
    var btn_inc   = zui.Button{ .label = "Increment" };
    var btn_reset = zui.Button{ .label = "Reset" };
    var btn_theme = zui.Button{ .label = "Toggle theme" };
    var btn_close = zui.Button{ .label = "Close" };
    defer btn_inc.deinit(alloc);
    defer btn_reset.deinit(alloc);
    defer btn_theme.deinit(alloc);
    defer btn_close.deinit(alloc);

    try btn_inc.clicked.connect(alloc, &counter,
        struct { fn f(p: *i32,  _: void) void { p.* += 1; } }.f);
    try btn_reset.clicked.connect(alloc, &counter,
        struct { fn f(p: *i32,  _: void) void { p.* = 0; } }.f);
    try btn_theme.clicked.connect(alloc, &dark_mode,
        struct { fn f(p: *bool, _: void) void { p.* = !p.*; } }.f);
    try btn_close.clicked.connect(alloc, &about_expanded,
        struct { fn f(p: *bool, _: void) void { p.* = false; } }.f);

    // ── Fixed widget rects (Controls page) ────────────────────────────────────
    const cx: i32 = NAV_W + 24;
    const cy: i32 = HDR_H + 60;
    const search_rect = zui.Rect.init(cx,       cy + 40,  320, 34);
    const name_rect   = zui.Rect.init(cx,       cy + 120, 280, 34);
    const inc_rect    = zui.Rect.init(cx,       cy + 200, 130, 34);
    const rst_rect    = zui.Rect.init(cx + 140, cy + 200, 100, 34);
    const theme_rect  = zui.Rect.init(cx,       cy + 250, 150, 34);
    const vol_rect    = zui.Rect.init(cx,       cy + 310, 300, 30);
    const cb1_y: i32 = cy + 360;
    const cb2_y: i32 = cy + 395;

    // ── Nav rects ─────────────────────────────────────────────────────────────
    var nav_rects: [NAV_ITEMS.len]zui.Rect = undefined;
    for (0..NAV_ITEMS.len) |i| {
        nav_rects[i] = zui.Rect.init(
            8,
            HDR_H + 8 + @as(i32, @intCast(i)) * 44,
            @intCast(NAV_W - 16),
            38);
    }
    var nav_hover_t: [NAV_ITEMS.len]f32 = .{0.0} ** NAV_ITEMS.len;
    var nav_hovered: [NAV_ITEMS.len]bool = .{false} ** NAV_ITEMS.len;

    // ── Main loop ─────────────────────────────────────────────────────────────
    while (!app.window.should_close) {
        const dt_s = app.deltaSeconds();

        // Close button rect — computed once per frame before events; refreshed after syncSize
        var close_rect = zui.Rect.init(
            @as(i32, @intCast(W)) - 130,
            @as(i32, @intCast(H)) - 56,
            110, 34);

        // ── Event processing ─────────────────────────────────────────────────
        while (app.pollEvent()) |ev| {
            switch (ev) {
                .close     => app.window.should_close = true,
                .key_press => |k| { if (k.key == .escape) app.window.should_close = true; },
                .mouse_move => |m| {
                    for (nav_rects, 0..) |nr, i| {
                        nav_hovered[i] = nr.contains(.{ .x = m.x, .y = m.y });
                    }
                },
                .mouse_press => |m| {
                    for (NAV_ITEMS, 0..) |item, i| {
                        if (nav_rects[i].contains(.{ .x = m.x, .y = m.y }) and m.button == .left)
                            page = item.page;
                    }
                    if (page == .about and m.button == .left) {
                        const exp_rect = zui.Rect.init(NAV_W + 24, ABOUT_EXPAND_Y, 500, 22);
                        if (exp_rect.contains(.{ .x = m.x, .y = m.y }))
                            about_expanded = !about_expanded;
                    }
                },
                else => {},
            }
            if (page == .controls) {
                _ = field_search.handleEvent(ev, search_rect, alloc);
                _ = field_name.handleEvent(ev, name_rect, alloc);
                _ = btn_inc.handleEvent(ev, inc_rect);
                _ = btn_reset.handleEvent(ev, rst_rect);
                _ = btn_theme.handleEvent(ev, theme_rect);
                _ = slider_vol.handleEvent(ev, vol_rect);
                _ = cb_notify.handleEvent(ev, cx, cb1_y);
                _ = cb_compact.handleEvent(ev, cx, cb2_y);
            }
            if (about_expanded) _ = btn_close.handleEvent(ev, close_rect);
        }

        // ── Sync size, refresh W/H and close_rect ────────────────────────────
        app.syncSize();
        W = app.window.width;
        H = app.window.height;
        close_rect = zui.Rect.init(
            @as(i32, @intCast(W)) - 130,
            @as(i32, @intCast(H)) - 56,
            110, 34);

        // ── Animate ───────────────────────────────────────────────────────────
        btn_inc.update(dt_s);
        btn_reset.update(dt_s);
        btn_theme.update(dt_s);
        btn_close.update(dt_s);
        cb_notify.update(dt_s);
        cb_compact.update(dt_s);
        for (0..NAV_ITEMS.len) |i| {
            const target: f32 = if (nav_hovered[i]) 1.0 else 0.0;
            const k = 1.0 - @exp(-10.0 * dt_s);
            nav_hover_t[i] += (target - nav_hover_t[i]) * k;
        }

        // ── Button styles ─────────────────────────────────────────────────────
        const theme = if (dark_mode) zui.Theme.dark else zui.Theme.light;
        btn_inc.style   = .{ .bg = ACCENT,       .bg_hover = ACCENT_HV,      .bg_press = ACCENT_PR, .fg = FG };
        btn_reset.style = .{ .bg = theme.btn_bg, .bg_hover = theme.btn_hover, .bg_press = theme.btn_press, .fg = theme.fg };
        btn_theme.style = .{ .bg = theme.btn_bg, .bg_hover = theme.btn_hover, .bg_press = theme.btn_press, .fg = theme.fg };
        btn_close.style = .{ .bg = ACCENT,       .bg_hover = ACCENT_HV,      .bg_press = ACCENT_PR, .fg = FG };

        // ── Background ────────────────────────────────────────────────────────
        const bg = if (dark_mode) BG else zui.Color.rgb(240, 240, 245);
        app.renderer.clear(bg);

        // ════════════════════════════════════════════════════════════════════
        // SIDEBAR
        // ════════════════════════════════════════════════════════════════════
        const nav_bg = if (dark_mode) BG_NAV else zui.Color.rgb(235, 235, 240);
        app.renderer.fillRect(zui.Rect.init(0, 0, @intCast(NAV_W), H), nav_bg);
        app.renderer.fillRect(zui.Rect.init(NAV_W, 0, 1, H), SEP);

        const hdr_bg = if (dark_mode) zui.Color.rgb(22, 22, 26) else zui.Color.rgb(220, 220, 228);
        app.renderer.fillRect(zui.Rect.init(0, 0, @intCast(NAV_W), @intCast(HDR_H)), hdr_bg);
        app.renderer.drawTextScaled("zui", 16, 10, ACCENT, 2);
        const zui_logo_w: i32 = @intCast(app.renderer.textWidthScaled("zui", 2));
        app.renderer.drawText("gallery", 16 + zui_logo_w + 8, 20, FG_TER);

        // Nav items
        for (NAV_ITEMS, 0..) |item, i| {
            const nr = nav_rects[i];
            const is_active = item.page == page;
            if (is_active) {
                app.renderer.fillRoundRect(nr, 6, NAV_ITEM_A);
                app.renderer.fillRect(zui.Rect.init(nr.x, nr.y + 6, 4, nr.height - 12), ACCENT);
            } else if (nav_hover_t[i] > 0.02) {
                app.renderer.fillRoundRect(nr, 6, BG_NAV.lerp(NAV_ITEM_H, nav_hover_t[i]));
            }
            app.renderer.drawText(item.icon,  nr.x + 10, nr.y + 10, if (is_active) ACCENT else FG_TER);
            app.renderer.drawText(item.label, nr.x + 28, nr.y + 10, if (is_active) FG    else FG_SEC);
        }

        // Search hint below nav items
        const nav_sx: i32 = HDR_H + 8 + @as(i32, NAV_ITEMS.len) * 44 + 8;
        const nav_search = zui.Rect.init(8, nav_sx, @intCast(NAV_W - 16), 30);
        app.renderer.fillRoundRect(nav_search, 6, SEP);
        app.renderer.fillRoundRect(
            zui.Rect.init(nav_search.x + 1, nav_search.y + 1, nav_search.width - 2, nav_search.height - 2),
            5, if (dark_mode) BG_INPUT else zui.Color.rgb(250, 250, 255));
        app.renderer.drawText("Search...", nav_search.x + 10, nav_search.y + 7, FG_TER);

        app.renderer.drawText("v0.6  M10-M13", 10, @as(i32, @intCast(H)) - 22, FG_TER);

        // ════════════════════════════════════════════════════════════════════
        // CONTENT HEADER
        // ════════════════════════════════════════════════════════════════════
        const content_w = W -| @as(u32, @intCast(NAV_W));
        const top_bar_bg = if (dark_mode) zui.Color.rgb(24, 24, 28) else zui.Color.rgb(248, 248, 252);
        app.renderer.fillRect(zui.Rect.init(NAV_W, 0, content_w, @intCast(HDR_H)), top_bar_bg);
        app.renderer.fillRect(zui.Rect.init(NAV_W, HDR_H, content_w, 1), SEP);

        const page_name = switch (page) {
            .dashboard => "Dashboard", .controls => "Controls", .colors => "Colors",
            .layout => "Layout", .about => "About",
        };
        const crumb_x = NAV_W + 20;
        const crumb_gw: i32 = @intCast(app.renderer.textWidth("zui Gallery"));
        app.renderer.drawText("zui Gallery", crumb_x, 14, FG_TER);
        app.renderer.drawText(">", crumb_x + crumb_gw + 6, 14, FG_TER);
        app.renderer.drawText(page_name, crumb_x + crumb_gw + 24, 14, FG_SEC);

        // ════════════════════════════════════════════════════════════════════
        // PAGE CONTENT
        // ════════════════════════════════════════════════════════════════════
        switch (page) {
            .dashboard => drawDashboard(&app.renderer, &counter, dark_mode),
            .controls  => drawControls(
                &app.renderer,
                &field_search, &field_name,
                &btn_inc, &btn_reset, &btn_theme,
                &slider_vol, &cb_notify, &cb_compact,
                search_rect, name_rect, inc_rect, rst_rect, theme_rect, vol_rect,
                cb1_y, cb2_y, cy, dark_mode, theme),
            .colors  => drawColors(&app.renderer, dark_mode),
            .layout  => drawLayout(&app.renderer, dark_mode, theme),
            .about   => drawAbout(&app.renderer, about_expanded, dark_mode),
        }

        if (about_expanded) btn_close.draw(&app.renderer, close_rect);

        app.present();
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: DASHBOARD
// ══════════════════════════════════════════════════════════════════════════════
fn drawDashboard(r: *zui.Renderer, counter: *i32, dark_mode: bool) void {
    const lcx: i32 = NAV_W + 24;
    const lcy: i32 = HDR_H + 16;

    r.drawTextScaled("Dashboard", lcx, lcy, if (dark_mode) FG else zui.Color.rgb(20, 20, 20), 2);
    r.drawText("Welcome to the zui component gallery", lcx, lcy + 30, FG_SEC);

    const card_y: i32 = lcy + 60;
    const avail_w: u32 = W -| @as(u32, @intCast(lcx + 24));

    // ── 3 stat cards via GridLayout ───────────────────────────────────────────
    const stat_grid = zui.GridLayout{ .cols = 3, .rows = 1, .gap = 12, .padding = 0 };
    var stat_rects: [3]zui.Rect = undefined;
    stat_grid.compute(zui.Rect.init(lcx, card_y, avail_w, 100), &stat_rects);

    const stats = [3]struct { label: []const u8, value: []const u8, color: zui.Color }{
        .{ .label = "Widgets",  .value = "7",  .color = ACCENT },
        .{ .label = "Backends", .value = "2",  .color = zui.Color.rgb(16, 140, 16) },
        .{ .label = "Signals",  .value = "ok", .color = zui.Color.rgb(200, 140, 0) },
    };
    for (stats, 0..) |stat, i| {
        drawCard(r, stat_rects[i], dark_mode);
        r.fillRect(zui.Rect.init(stat_rects[i].x, stat_rects[i].y, stat_rects[i].width, 3), stat.color);
        r.drawTextScaled(stat.value, stat_rects[i].x + 16, stat_rects[i].y + 16, stat.color, 3);
        r.drawText(stat.label, stat_rects[i].x + 16, stat_rects[i].y + 70, FG_SEC);
    }

    // ── Counter card ─────────────────────────────────────────────────────────
    const cnt_card = zui.Rect.init(lcx, card_y + 116, 360, 90);
    drawCard(r, cnt_card, dark_mode);
    r.drawText("Counter  (Signal demo)", cnt_card.x + 16, cnt_card.y + 12, FG_SEC);
    r.fillRect(zui.Rect.init(cnt_card.x + 16, cnt_card.y + 32, cnt_card.width - 32, 1), SEP);
    var buf: [16]u8 = undefined;
    const val_str = std.fmt.bufPrint(&buf, "{d}", .{counter.*}) catch "?";
    const val_w = r.textWidthScaled(val_str, 4);
    const vx = cnt_card.x + 16 + @as(i32, @intCast((cnt_card.width - 32 -| val_w) / 2));
    r.drawTextScaled(val_str, vx, cnt_card.y + 38, ACCENT, 4);

    // ── Feature list card ─────────────────────────────────────────────────────
    const feat_x: i32 = lcx + 376;
    const feat_w: u32 = W -| @as(u32, @intCast(feat_x + 24));
    const feat_card = zui.Rect.init(feat_x, card_y + 116, feat_w, 220);
    drawCard(r, feat_card, dark_mode);
    r.drawText("Completed milestones", feat_card.x + 16, feat_card.y + 12, FG_SEC);
    r.fillRect(zui.Rect.init(feat_card.x + 16, feat_card.y + 32, feat_card.width - 32, 1), SEP);
    const features = [_][]const u8{
        "M0  Foundations + geometry",      "M1  Win32 platform backend",
        "M2  Widgets + Signal(T)",          "M3  Theming + TextField + Grid",
        "M4  OpenGL 3.3 core backend",      "M8  Showcase gallery",
        "M9  Mica + rounded corners",       "M10 GDI Segoe UI typography",
        "M11 Animation (hover / tween)",    "M12 Checkbox + Slider",
        "M13 Clipboard + modifiers",
    };
    for (features, 0..) |feat, i| {
        r.fillRect(zui.Rect.init(feat_card.x + 16, feat_card.y + 40 + @as(i32, @intCast(i)) * 16, 5, 5), ACCENT);
        r.drawText(feat, feat_card.x + 28, feat_card.y + 38 + @as(i32, @intCast(i)) * 16,
            if (dark_mode) FG else zui.Color.rgb(20, 20, 20));
    }

    // ── BoxLayout strip ───────────────────────────────────────────────────────
    const box_card = zui.Rect.init(lcx, card_y + 222, 360, 60);
    drawCard(r, box_card, dark_mode);
    r.drawText("BoxLayout (horizontal)", box_card.x + 12, box_card.y + 8, FG_TER);
    const box_layout = zui.BoxLayout{
        .direction = .horizontal, .spacing = 8,
        .padding = .{ .top = 26, .bottom = 8, .left = 12, .right = 12 },
    };
    const box_sizes = [4]zui.Size{
        .{ .width = 40, .height = 30 }, .{ .width = 60, .height = 30 },
        .{ .width = 50, .height = 30 }, .{ .width = 45, .height = 30 },
    };
    var box_rects: [4]zui.Rect = undefined;
    box_layout.compute(box_card, &box_sizes, &box_rects);
    const strip_cols = [4]zui.Color{
        ACCENT, zui.Color.rgb(16, 140, 16), zui.Color.rgb(200, 60, 20), zui.Color.rgb(140, 20, 200),
    };
    for (box_rects, 0..) |br, i| {
        r.fillRect(br, strip_cols[i]);
        r.drawText(&[1]u8{@as(u8, 'A') + @as(u8, @intCast(i))},
            br.x + @as(i32, @intCast((br.width -| 8) / 2)), br.y + 6, FG);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: CONTROLS
// ══════════════════════════════════════════════════════════════════════════════
fn drawControls(
    r: *zui.Renderer,
    field_search: *zui.TextField, field_name: *zui.TextField,
    btn_inc: *zui.Button, btn_reset: *zui.Button, btn_theme: *zui.Button,
    slider_vol: *zui.Slider, cb_notify: *zui.Checkbox, cb_compact: *zui.Checkbox,
    search_rect: zui.Rect, name_rect: zui.Rect,
    inc_rect: zui.Rect, rst_rect: zui.Rect, theme_rect: zui.Rect, vol_rect: zui.Rect,
    cb1_y: i32, cb2_y: i32, content_y: i32, dark_mode: bool, theme: zui.Theme,
) void {
    const lx: i32 = NAV_W + 24;
    const ly: i32 = HDR_H + 16;
    const base = content_y;

    r.drawTextScaled("Controls", lx, ly, if (dark_mode) FG else zui.Color.rgb(20, 20, 20), 2);
    r.drawText("Interactive widgets and inputs", lx, ly + 30, FG_SEC);

    // ── Text inputs ───────────────────────────────────────────────────────────
    sectionLabel(r, lx, base, "Text Input");
    r.drawText("Search:", lx, base + 42, FG_SEC);
    field_search.draw(r, search_rect, theme);
    if (field_search.text.items.len > 0) {
        r.drawText("Query:", lx + 330, base + 51, FG_TER);
        r.drawText(field_search.text.items,
            lx + 330 + @as(i32, @intCast(r.textWidth("Query:"))) + 6, base + 51, ACCENT);
    }
    r.drawText("Name:", lx, base + 122, FG_SEC);
    field_name.draw(r, name_rect, theme);
    if (field_name.text.items.len > 0) {
        var greet_buf: [80]u8 = undefined;
        const greet = std.fmt.bufPrint(&greet_buf, "Hello, {s}!", .{field_name.text.items}) catch "";
        r.drawText(greet, lx, base + 168, ACCENT);
    }

    // ── Buttons ───────────────────────────────────────────────────────────────
    sectionLabel(r, lx, base + 190, "Buttons");
    btn_inc.draw(r, inc_rect);
    btn_reset.draw(r, rst_rect);
    btn_theme.draw(r, theme_rect);

    // ── Slider ────────────────────────────────────────────────────────────────
    sectionLabel(r, lx, base + 290, "Slider");
    slider_vol.draw(r, vol_rect);
    var vol_buf: [8]u8 = undefined;
    const vol_str = std.fmt.bufPrint(&vol_buf, "{d:.0}%", .{slider_vol.value * 100.0}) catch "";
    r.drawText(vol_str, vol_rect.right() + 12, vol_rect.y + 6, FG_SEC);

    // ── Checkboxes ────────────────────────────────────────────────────────────
    sectionLabel(r, lx, base + 340, "Checkbox");
    cb_notify.draw(r, lx, cb1_y);
    cb_compact.draw(r, lx, cb2_y);

    // ── Right column ─────────────────────────────────────────────────────────
    const rx: i32 = lx + 400;
    sectionLabel(r, rx, base, "Progress bars");
    const pb1 = zui.Rect.init(rx, base + 22, 300, 8);
    r.fillRoundRect(pb1, 4, zui.Color.rgb(60, 60, 65));
    r.fillRoundRect(zui.Rect.init(pb1.x, pb1.y, @intFromFloat(300.0 * 0.62), pb1.height), 4, ACCENT);
    r.drawText("62%  deterministic", rx, base + 38, FG_TER);

    const pb2 = zui.Rect.init(rx, base + 62, 300, 8);
    r.fillRoundRect(pb2, 4, zui.Color.rgb(60, 60, 65));
    r.fillRoundRect(zui.Rect.init(pb2.x, pb2.y, 120, pb2.height), 4, zui.Color.rgb(0, 160, 140));
    r.drawText("indeterminate", rx, base + 78, FG_TER);

    sectionLabel(r, rx, base + 110, "Accent variants");
    const swatches = [_]zui.Color{
        zui.Color.rgb(0, 80, 160), ACCENT, ACCENT_HV,
        zui.Color.rgb(0, 153, 255), zui.Color.rgb(80, 180, 255),
    };
    for (swatches, 0..) |c, i| {
        r.fillRoundRect(zui.Rect.init(rx + @as(i32, @intCast(i)) * 56, base + 132, 48, 48), 6, c);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: COLORS
// ══════════════════════════════════════════════════════════════════════════════
fn drawColors(r: *zui.Renderer, dark_mode: bool) void {
    const lcx: i32 = NAV_W + 24;
    const lcy: i32 = HDR_H + 16;

    r.drawTextScaled("Colors", lcx, lcy, if (dark_mode) FG else zui.Color.rgb(20, 20, 20), 2);
    r.drawText("Theme palette and named colors", lcx, lcy + 30, FG_SEC);

    const base = lcy + 60;

    sectionLabel(r, lcx, base, "Accent ramp");
    const blues = [_]zui.Color{
        zui.Color.rgb(0, 40, 100),   zui.Color.rgb(0, 60, 140),
        zui.Color.rgb(0, 80, 160),   ACCENT,
        zui.Color.rgb(0, 120, 215),  zui.Color.rgb(0, 153, 255),
        zui.Color.rgb(80, 180, 255), zui.Color.rgb(160, 210, 255),
    };
    for (blues, 0..) |c, i| {
        r.fillRoundRect(zui.Rect.init(lcx + @as(i32, @intCast(i)) * 70, base + 20, 62, 62), 6, c);
    }

    sectionLabel(r, lcx, base + 100, "System colors");
    const sys_colors = [_]struct { name: []const u8, color: zui.Color }{
        .{ .name = "Red",    .color = zui.Color.rgb(196, 43, 28)  },
        .{ .name = "Orange", .color = zui.Color.rgb(202, 80, 16)  },
        .{ .name = "Yellow", .color = zui.Color.rgb(255, 185, 0)  },
        .{ .name = "Green",  .color = zui.Color.rgb(16, 124, 16)  },
        .{ .name = "Teal",   .color = zui.Color.rgb(0, 153, 153)  },
        .{ .name = "Blue",   .color = ACCENT                       },
        .{ .name = "Purple", .color = zui.Color.rgb(136, 23, 152) },
        .{ .name = "Pink",   .color = zui.Color.rgb(195, 0, 82)   },
    };
    for (sys_colors, 0..) |sc, i| {
        const sx = lcx + @as(i32, @intCast(i)) * 70;
        r.fillRoundRect(zui.Rect.init(sx, base + 122, 62, 52), 6, sc.color);
        r.drawText(sc.name, sx, base + 180, FG_SEC);
    }

    sectionLabel(r, lcx, base + 210, "Neutral ramp");
    for (0..8) |ni| {
        const lum: u8 = @intCast(ni * 30 + 20);
        r.fillRoundRect(zui.Rect.init(lcx + @as(i32, @intCast(ni)) * 70, base + 230, 62, 40), 6,
            zui.Color.rgb(lum, lum, lum));
    }

    sectionLabel(r, lcx, base + 290, "Color.lerp demo");
    for (0..16) |li| {
        const t: f32 = @as(f32, @floatFromInt(li)) / 15.0;
        r.fillRoundRect(zui.Rect.init(lcx + @as(i32, @intCast(li)) * 34, base + 310, 32, 28), 4,
            ACCENT.lerp(zui.Color.rgb(196, 43, 28), t));
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: LAYOUT
// ══════════════════════════════════════════════════════════════════════════════
fn drawLayout(r: *zui.Renderer, dark_mode: bool, theme: zui.Theme) void {
    const lcx: i32 = NAV_W + 24;
    const lcy: i32 = HDR_H + 16;

    r.drawTextScaled("Layout", lcx, lcy, if (dark_mode) FG else zui.Color.rgb(20, 20, 20), 2);
    r.drawText("BoxLayout and GridLayout engines", lcx, lcy + 30, FG_SEC);

    const base = lcy + 60;
    const rx: i32 = lcx + 380;

    const box_cols = [3]zui.Color{
        ACCENT, zui.Color.rgb(16, 124, 16), zui.Color.rgb(200, 80, 20),
    };

    sectionLabel(r, lcx, base, "BoxLayout  vertical");
    const vbox_bounds = zui.Rect.init(lcx, base + 20, 200, 190);
    drawCard(r, vbox_bounds, dark_mode);
    const vbox = zui.BoxLayout{
        .direction = .vertical, .spacing = 8,
        .padding = .{ .top = 10, .bottom = 10, .left = 10, .right = 10 },
    };
    const vsizes = [3]zui.Size{
        .{ .width = 180, .height = 42 }, .{ .width = 180, .height = 42 }, .{ .width = 180, .height = 42 },
    };
    var vrects: [3]zui.Rect = undefined;
    vbox.compute(vbox_bounds, &vsizes, &vrects);
    for (vrects, 0..) |vr, i| {
        r.fillRoundRect(vr, 4, box_cols[i]);
        r.drawText(&[1]u8{@as(u8, 'A') + @as(u8, @intCast(i))}, vr.x + 8, vr.y + 13, FG);
    }

    sectionLabel(r, lcx, base + 220, "BoxLayout  horizontal");
    const hbox_bounds = zui.Rect.init(lcx, base + 240, 340, 60);
    drawCard(r, hbox_bounds, dark_mode);
    const hbox = zui.BoxLayout{
        .direction = .horizontal, .spacing = 8,
        .padding = .{ .top = 10, .bottom = 10, .left = 10, .right = 10 },
    };
    const hsizes = [3]zui.Size{
        .{ .width = 80, .height = 40 }, .{ .width = 120, .height = 40 }, .{ .width = 80, .height = 40 },
    };
    var hrects: [3]zui.Rect = undefined;
    hbox.compute(hbox_bounds, &hsizes, &hrects);
    for (hrects, 0..) |hr, i| {
        r.fillRoundRect(hr, 4, box_cols[i]);
        r.drawText(&[1]u8{@as(u8, 'A') + @as(u8, @intCast(i))}, hr.x + 8, hr.y + 12, FG);
    }

    sectionLabel(r, rx, base, "GridLayout  2×3");
    const grid_bounds = zui.Rect.init(rx, base + 20, 340, 190);
    drawCard(r, grid_bounds, dark_mode);
    const grid = zui.GridLayout{ .cols = 2, .rows = 3, .gap = 8, .padding = 10 };
    const gcontent = zui.Container{};
    const ginner = gcontent.contentRect(grid_bounds);
    var grects: [6]zui.Rect = undefined;
    grid.compute(ginner, &grects);
    const gcols = [6]zui.Color{
        ACCENT,                    zui.Color.rgb(16, 124, 16),
        zui.Color.rgb(200, 80, 20), zui.Color.rgb(136, 23, 152),
        zui.Color.rgb(0, 153, 153), zui.Color.rgb(200, 140, 0),
    };
    const glabels = [6][]const u8{ "Rect", "Color", "Layout", "Signal", "Event", "Style" };
    for (grects, 0..) |gr, i| {
        r.fillRoundRect(gr, 4, gcols[i]);
        r.drawText(glabels[i], gr.x + 4, gr.y + 4, FG);
    }

    sectionLabel(r, rx, base + 220, "GridLayout  3×1  (stat strip)");
    const sg_bounds = zui.Rect.init(rx, base + 240, 340, 60);
    const sgrid = zui.GridLayout{ .cols = 3, .rows = 1, .gap = 8, .padding = 0 };
    var sgrects: [3]zui.Rect = undefined;
    sgrid.compute(sg_bounds, &sgrects);
    const sg_vals = [3][]const u8{ "42", "7", "99" };
    for (sgrects, 0..) |sgr, i| {
        drawCard(r, sgr, dark_mode);
        r.fillRect(zui.Rect.init(sgr.x, sgr.y, sgr.width, 2), box_cols[i]);
        r.drawTextScaled(sg_vals[i], sgr.x + 8, sgr.y + 12, box_cols[i], 2);
    }

    sectionLabel(r, lcx, base + 320, "Container  (titled panel)");
    const con = zui.Container{ .title = "Panel title" };
    const con_bounds = zui.Rect.init(lcx, base + 340, 700, 80);
    con.draw(r, con_bounds, theme);
    const con_inner = con.contentRect(con_bounds);
    r.drawText("Content area rendered inside contentRect()", con_inner.x + 8, con_inner.y + 10, FG_SEC);
    r.drawText("contentRect clips to the area below the title bar.", con_inner.x + 8, con_inner.y + 30, FG_TER);
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: ABOUT
// ══════════════════════════════════════════════════════════════════════════════
fn drawAbout(r: *zui.Renderer, about_expanded: bool, dark_mode: bool) void {
    const lcx: i32 = NAV_W + 24;
    const lcy: i32 = HDR_H + 16;

    r.drawTextScaled("zui", lcx, lcy + 10, ACCENT, 5);
    const logo_w: i32 = @intCast(r.textWidthScaled("zui", 5));
    r.drawTextScaled("gallery", lcx + logo_w + 16, lcy + 36,
        if (dark_mode) FG_SEC else zui.Color.rgb(80, 80, 90), 2);

    r.drawText("A Qt/WPF-inspired UI framework for Zig 0.16", lcx, lcy + 90, FG_SEC);
    r.drawText("Milestones 0–13 complete", lcx, lcy + 110, FG_TER);
    r.fillRect(zui.Rect.init(lcx, lcy + 130, 500, 1), SEP);

    const info_y = lcy + 144;
    const items = [_][]const u8{
        "Platform:  Win32 native (no dependencies)",
        "Renderer:  Software DIB  or  OpenGL 3.3 core",
        "Widgets:   Button  Label  TextField  Checkbox  Slider  Container",
        "Layout:    BoxLayout  GridLayout",
        "Signals:   Signal(T)  connect  emit  (comptime-typed)",
        "Theming:   Theme.dark  /  Theme.light  (runtime toggle)",
        "Font:      Segoe UI Variable via GDI (ClearType / antialiased)",
        "Anim:      Tween (exponential decay, 150ms hover fades)",
        "Build:     zig build  /  zig build -Dbackend=opengl",
    };
    for (items, 0..) |item, i| {
        r.fillRect(zui.Rect.init(lcx, info_y + @as(i32, @intCast(i)) * 22 + 5, 4, 12), ACCENT);
        r.drawText(item, lcx + 12, info_y + @as(i32, @intCast(i)) * 22,
            if (dark_mode) FG else zui.Color.rgb(20, 20, 20));
    }

    // expand_y must match ABOUT_EXPAND_Y used for click detection
    const expand_y: i32 = info_y + @as(i32, items.len) * 22 + 16;
    r.fillRect(zui.Rect.init(lcx, expand_y, 500, 1), SEP);
    r.drawText(if (about_expanded) "▾  Architecture notes"
               else "▸  Architecture notes  (click to expand)",
               lcx, expand_y + 8, FG_SEC);

    if (about_expanded) {
        const arch_lines = [_][]const u8{
            "Strictly layered: core → events/signals/style/layout → graphics/platform → widgets",
            "No hidden allocations: every fn that allocates takes std.mem.Allocator",
            "Comptime backend selection: -Dbackend= switches renderer at compile time",
            "Signal(T): typed, comptime-verified slots; no string-based dispatch",
        };
        for (arch_lines, 0..) |line, i| {
            r.drawText(line, lcx + 12, expand_y + 28 + @as(i32, @intCast(i)) * 20, FG_TER);
        }
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════════════════════════════

fn drawCard(r: *zui.Renderer, rect: zui.Rect, dark_mode: bool) void {
    const bg = if (dark_mode) BG_CARD else zui.Color.rgb(255, 255, 255);
    r.fillRoundRect(rect, 9, SEP);
    r.fillRoundRect(zui.Rect.init(rect.x + 1, rect.y + 1, rect.width - 2, rect.height - 2), 8, bg);
}

fn sectionLabel(r: *zui.Renderer, x: i32, y: i32, label: []const u8) void {
    r.drawText(label, x, y, FG_TER);
    r.fillRect(zui.Rect.init(x, y + 16, @intCast(r.textWidth(label) + 8), 1), SEP);
}
