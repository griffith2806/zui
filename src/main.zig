// zui Showcase — WPF UI–style component gallery
// Demonstrates: Theme, Navigation, Buttons, TextField, Container,
//               BoxLayout, GridLayout, Signal(T), Color palette.

const std = @import("std");
const zui = @import("zui");

// ── Fluent dark palette ──────────────────────────────────────────────────────
const BG        = zui.Color.rgb( 20,  20,  20);   // true dark base
const BG_NAV    = zui.Color.rgb( 28,  28,  30);   // sidebar
const BG_CARD   = zui.Color.rgb( 36,  36,  38);   // card surface
const BG_CARD2  = zui.Color.rgb( 44,  44,  48);   // elevated card
const BG_INPUT  = zui.Color.rgb( 30,  30,  32);   // input fields
const ACCENT    = zui.Color.rgb(  0, 103, 192);   // Windows 11 blue
const ACCENT_HV = zui.Color.rgb(  0, 120, 215);
const ACCENT_PR = zui.Color.rgb(  0,  80, 160);
const FG        = zui.Color.rgb(255, 255, 255);
const FG_SEC    = zui.Color.rgb(178, 178, 185);   // secondary text
const FG_TER    = zui.Color.rgb(110, 110, 118);   // tertiary / hint
const SEP       = zui.Color.rgb( 55,  55,  60);   // separator
const NAV_ITEM_H = zui.Color.rgb( 48,  48,  52);   // nav hover
const NAV_ITEM_A = zui.Color.rgb( 42,  42,  48);   // nav active bg

const NAV_W: i32 = 220;
const HDR_H: i32 = 48;
const W: u32     = 1000;
const H: u32     = 620;

const Page = enum { dashboard, controls, colors, layout, about };

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

    // ── Controls page state ────────────────────────────────────────────────────
    var field_search = zui.TextField{};
    defer field_search.deinit(alloc);
    var field_name = zui.TextField{};
    defer field_name.deinit(alloc);
    const progress_val: f32 = 0.62;
    var toggle_a = true;
    var toggle_b = false;

    // ── Buttons ────────────────────────────────────────────────────────────────
    var btn_inc   = zui.Button{ .label = "Increment" };
    var btn_reset = zui.Button{ .label = "Reset" };
    var btn_theme = zui.Button{ .label = "Toggle theme" };
    var btn_about_close = zui.Button{ .label = "Close" };
    defer btn_inc.deinit(alloc);
    defer btn_reset.deinit(alloc);
    defer btn_theme.deinit(alloc);
    defer btn_about_close.deinit(alloc);

    try btn_inc.clicked.connect   (alloc, &counter,        struct { fn f(p: *i32,  _: void) void { p.* += 1; } }.f);
    try btn_reset.clicked.connect (alloc, &counter,        struct { fn f(p: *i32,  _: void) void { p.* = 0;  } }.f);
    try btn_theme.clicked.connect (alloc, &dark_mode,      struct { fn f(p: *bool, _: void) void { p.* = !p.*; } }.f);
    try btn_about_close.clicked.connect(alloc, &about_expanded, struct { fn f(p: *bool, _: void) void { p.* = false; } }.f);

    // ── Layout: sidebar nav items (y positions) ───────────────────────────────
    const NAV_ITEMS = [_]struct { label: []const u8, page: Page, icon: []const u8 }{
        .{ .label = "Dashboard",  .page = .dashboard, .icon = "D" },
        .{ .label = "Controls",   .page = .controls,  .icon = "C" },
        .{ .label = "Colors",     .page = .colors,    .icon = "P" },
        .{ .label = "Layout",     .page = .layout,    .icon = "L" },
        .{ .label = "About",      .page = .about,     .icon = "A" },
    };

    // Precalculate nav item rects (fixed layout)
    var nav_rects: [NAV_ITEMS.len]zui.Rect = undefined;
    for (0..NAV_ITEMS.len) |i| {
        nav_rects[i] = zui.Rect.init(8, HDR_H + 8 + @as(i32, @intCast(i)) * 44, NAV_W - 16, 38);
    }

    // ── Controls page widget rects (relative to content area) ─────────────────
    const cx: i32 = NAV_W + 24;   // content x start
    const cy: i32 = HDR_H + 60;   // content y start (below page title)

    const search_rect  = zui.Rect.init(cx,       cy + 40,  320, 34);
    const name_rect    = zui.Rect.init(cx,       cy + 120, 280, 34);
    const inc_rect     = zui.Rect.init(cx,       cy + 200, 130, 34);
    const rst_rect     = zui.Rect.init(cx + 140, cy + 200, 100, 34);
    const theme_rect   = zui.Rect.init(cx,       cy + 250, 150, 34);
    const tog_a_rect   = zui.Rect.init(cx,       cy + 310, 44,  24);
    const tog_b_rect   = zui.Rect.init(cx,       cy + 350, 44,  24);
    const close_rect   = zui.Rect.init(@as(i32,W) - 120, @as(i32,H) - 56, 100, 34);

    while (!app.window.should_close) {
        const theme = if (dark_mode) zui.Theme.dark else zui.Theme.light;

        // ── Restyle buttons from theme ────────────────────────────────────────
        btn_inc.style   = .{ .bg = ACCENT,       .bg_hover = ACCENT_HV, .bg_press = ACCENT_PR, .fg = FG };
        btn_reset.style = .{ .bg = theme.btn_bg, .bg_hover = theme.btn_hover, .bg_press = theme.btn_press, .fg = theme.fg };
        btn_theme.style = .{ .bg = theme.btn_bg, .bg_hover = theme.btn_hover, .bg_press = theme.btn_press, .fg = theme.fg };
        btn_about_close.style = .{ .bg = ACCENT, .bg_hover = ACCENT_HV, .bg_press = ACCENT_PR, .fg = FG };

        // ── Events ────────────────────────────────────────────────────────────
        while (app.pollEvent()) |ev| {
            switch (ev) {
                .close     => app.window.should_close = true,
                .key_press => |k| { if (k.key == .escape) app.window.should_close = true; },
                .mouse_press => |m| {
                    for (NAV_ITEMS, 0..) |item, i| {
                        if (nav_rects[i].contains(.{ .x = m.x, .y = m.y }) and m.button == .left) {
                            page = item.page;
                        }
                    }
                    if (tog_a_rect.contains(.{ .x = m.x, .y = m.y }) and m.button == .left) toggle_a = !toggle_a;
                    if (tog_b_rect.contains(.{ .x = m.x, .y = m.y }) and m.button == .left) toggle_b = !toggle_b;
                    // About page: expand section click
                    if (page == .about and m.button == .left) {
                        const exp_y: i32 = HDR_H + 16 + @as(i32,8) * 22 + 16 + 50 + 8;
                        const exp_rect = zui.Rect.init(NAV_W + 24, exp_y, 500, 20);
                        if (exp_rect.contains(.{ .x = m.x, .y = m.y })) about_expanded = !about_expanded;
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
            }
            _ = btn_about_close.handleEvent(ev, close_rect);
        }

        // ── Background ────────────────────────────────────────────────────────
        const bg = if (dark_mode) BG else zui.Color.rgb(240, 240, 245);
        app.renderer.clear(bg);

        // ════════════════════════════════════════════════════════════════════
        // SIDEBAR
        // ════════════════════════════════════════════════════════════════════
        const nav_bg = if (dark_mode) BG_NAV else zui.Color.rgb(235, 235, 240);
        app.renderer.fillRect(zui.Rect.init(0, 0, @intCast(NAV_W), H), nav_bg);
        app.renderer.fillRect(zui.Rect.init(NAV_W, 0, 1, H), SEP);

        // App branding
        app.renderer.fillRect(zui.Rect.init(0, 0, @intCast(NAV_W), HDR_H), if (dark_mode) zui.Color.rgb(22, 22, 26) else zui.Color.rgb(220,220,228));
        app.renderer.drawTextScaled("zui", 16, 12, ACCENT, 2);
        app.renderer.drawText("gallery", 16 + 3 * 8 * 2 + 8, 20, FG_TER);

        // Search bar at top of nav — rounded pill style
        const nav_search = zui.Rect.init(8, HDR_H + 8 + @as(i32, NAV_ITEMS.len) * 44 + 8, NAV_W - 16, 30);
        app.renderer.fillRoundRect(nav_search, 6, SEP);
        app.renderer.fillRoundRect(zui.Rect.init(nav_search.x+1, nav_search.y+1, nav_search.width-2, nav_search.height-2), 5, if (dark_mode) BG_INPUT else zui.Color.rgb(250,250,255));
        app.renderer.drawText("Search...", nav_search.x + 10, nav_search.y + 10, FG_TER);

        // Nav items
        for (NAV_ITEMS, 0..) |item, i| {
            const nr = nav_rects[i];
            const is_active = item.page == page;
            if (is_active) {
                app.renderer.fillRoundRect(nr, 6, NAV_ITEM_A);
                app.renderer.fillRoundRect(zui.Rect.init(nr.x, nr.y + 6, 4, nr.height - 12), 2, ACCENT);
            }
            const ic_color = if (is_active) ACCENT else FG_TER;
            const tx_color = if (is_active) FG else FG_SEC;
            app.renderer.drawText(item.icon, nr.x + 10, nr.y + 11, ic_color);
            app.renderer.drawText(item.label, nr.x + 28, nr.y + 11, tx_color);
        }

        // Version at bottom of nav
        app.renderer.drawText("v0.5 - M9 Visual Polish", 10, @as(i32,H) - 20, FG_TER);

        // ════════════════════════════════════════════════════════════════════
        // CONTENT AREA — top bar
        // ════════════════════════════════════════════════════════════════════
        const top_bar_bg = if (dark_mode) zui.Color.rgb(24,24,28) else zui.Color.rgb(248,248,252);
        app.renderer.fillRect(zui.Rect.init(NAV_W, 0, W - @as(u32,@intCast(NAV_W)), @intCast(HDR_H)), top_bar_bg);
        app.renderer.fillRect(zui.Rect.init(NAV_W, HDR_H, W - @as(u32,@intCast(NAV_W)), 1), SEP);

        // Page breadcrumb
        const page_name = switch (page) {
            .dashboard => "Dashboard",
            .controls  => "Controls",
            .colors    => "Colors",
            .layout    => "Layout",
            .about     => "About",
        };
        app.renderer.drawText("zui Gallery", NAV_W + 20, 8, FG_TER);
        app.renderer.drawText(">", NAV_W + 20 + 8 * 11 + 4, 8, FG_TER);
        app.renderer.drawText(page_name, NAV_W + 20 + 8 * 13 + 4, 8, FG_SEC);

        // Theme toggle top-right
        const theme_label = if (dark_mode) "Light" else "Dark";
        const tl_x: i32 = @as(i32,W) - 8 * @as(i32, @intCast(theme_label.len)) - 20;
        app.renderer.drawText(theme_label, tl_x, 16, FG_TER);

        // ════════════════════════════════════════════════════════════════════
        // PAGE CONTENT
        // ════════════════════════════════════════════════════════════════════
        switch (page) {
            .dashboard => drawDashboard(&app.renderer, &counter, dark_mode, theme),
            .controls  => drawControls(&app.renderer, &field_search, &field_name, &btn_inc, &btn_reset, &btn_theme,
                                       &toggle_a, &toggle_b, progress_val, search_rect, name_rect,
                                       inc_rect, rst_rect, theme_rect, tog_a_rect, tog_b_rect, dark_mode, theme),
            .colors    => drawColors(&app.renderer, dark_mode),
            .layout    => drawLayout(&app.renderer, dark_mode, theme),
            .about     => drawAbout(&app.renderer, &about_expanded, dark_mode),
        }

        // ── About close button (global overlay) ───────────────────────────────
        if (about_expanded) {
            btn_about_close.draw(&app.renderer, close_rect);
        }

        app.present();
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: DASHBOARD
// ══════════════════════════════════════════════════════════════════════════════
fn drawDashboard(r: *zui.Renderer, counter: *i32, dark_mode: bool, _: zui.Theme) void {
    const cx: i32 = NAV_W + 24;
    const cy: i32 = HDR_H + 16;

    // Page title
    r.drawTextScaled("Dashboard", cx, cy, if (dark_mode) FG else zui.Color.rgb(20,20,20), 2);
    r.drawText("Welcome to the zui component gallery", cx, cy + 22, FG_SEC);

    const card_y: i32 = cy + 50;

    // ── 3 stat cards (GridLayout 3x1) ────────────────────────────────────────
    const grid_bounds = zui.Rect.init(cx, card_y, @as(u32,@intCast(@as(i32,W) - cx - 24)), 100);
    const stat_grid = zui.GridLayout{ .cols = 3, .rows = 1, .gap = 12, .padding = 0 };
    var stat_rects: [3]zui.Rect = undefined;
    stat_grid.compute(grid_bounds, &stat_rects);

    const stats = [3]struct { label: []const u8, value: []const u8, color: zui.Color }{
        .{ .label = "Widgets",  .value = "5",  .color = ACCENT },
        .{ .label = "Backends", .value = "2",  .color = zui.Color.rgb(16, 140, 16) },
        .{ .label = "Signals",  .value = "ok", .color = zui.Color.rgb(200, 140, 0) },
    };
    for (stats, 0..) |stat, i| {
        drawCard(r, stat_rects[i], dark_mode);
        r.fillRect(zui.Rect.init(stat_rects[i].x, stat_rects[i].y, stat_rects[i].width, 3), stat.color);
        r.drawTextScaled(stat.value, stat_rects[i].x + 16, stat_rects[i].y + 18, stat.color, 3);
        r.drawText(stat.label, stat_rects[i].x + 16, stat_rects[i].y + 74, FG_SEC);
    }

    // ── Counter card ─────────────────────────────────────────────────────────
    const cnt_card = zui.Rect.init(cx, card_y + 116, 360, 90);
    drawCard(r, cnt_card, dark_mode);
    r.drawText("Counter (Signal demo)", cnt_card.x + 16, cnt_card.y + 12, FG_SEC);
    r.fillRect(zui.Rect.init(cnt_card.x + 16, cnt_card.y + 26, cnt_card.width - 32, 1), SEP);

    var buf: [16]u8 = undefined;
    const val_str = std.fmt.bufPrint(&buf, "{d}", .{counter.*}) catch "?";
    const vx = cnt_card.x + 16 + @as(i32, @intCast((cnt_card.width - 32 - zui.Renderer.textWidthScaled(val_str, 4)) / 2));
    r.drawTextScaled(val_str, vx, cnt_card.y + 34, ACCENT, 4);

    // ── Feature list card ────────────────────────────────────────────────────
    const feat_card = zui.Rect.init(cx + 376, card_y + 116, @as(u32,@intCast(@as(i32,W) - cx - 376 - 24)), 200);
    drawCard(r, feat_card, dark_mode);
    r.drawText("Completed subsystems", feat_card.x + 16, feat_card.y + 12, FG_SEC);
    r.fillRect(zui.Rect.init(feat_card.x + 16, feat_card.y + 26, feat_card.width - 32, 1), SEP);

    const features = [_][]const u8{
        "M0  Foundations + geometry",
        "M1  Win32 platform backend",
        "M2  Widgets + Signal(T)",
        "M3  Theming + TextField + Grid",
        "M4  OpenGL 3.3 core backend",
        "M8  Showcase gallery",
        "M9  Mica + rounded corners",
    };
    for (features, 0..) |feat, i| {
        r.fillRect(zui.Rect.init(feat_card.x + 16, feat_card.y + 36 + @as(i32,@intCast(i)) * 24, 6, 6), ACCENT);
        r.drawText(feat, feat_card.x + 30, feat_card.y + 34 + @as(i32,@intCast(i)) * 24, if (dark_mode) FG else zui.Color.rgb(20,20,20));
    }

    // ── BoxLayout demo strip ─────────────────────────────────────────────────
    const box_card = zui.Rect.init(cx, card_y + 222, 360, 60);
    drawCard(r, box_card, dark_mode);
    r.drawText("BoxLayout (horizontal)", box_card.x + 12, box_card.y + 8, FG_TER);
    const box_layout = zui.BoxLayout{ .direction = .horizontal, .spacing = 8, .padding = .{ .top=26,.bottom=8,.left=12,.right=12 } };
    const box_sizes = [4]zui.Size{ .{.width=40,.height=30}, .{.width=60,.height=30}, .{.width=50,.height=30}, .{.width=45,.height=30} };
    var box_rects: [4]zui.Rect = undefined;
    box_layout.compute(box_card, &box_sizes, &box_rects);
    const strip_colors = [4]zui.Color{ ACCENT, zui.Color.rgb(16,140,16), zui.Color.rgb(200,60,20), zui.Color.rgb(140,20,200) };
    for (0..4) |i| {
        r.fillRect(box_rects[i], strip_colors[i]);
        r.drawText(&[1]u8{@as(u8,'A'+@as(u8,@intCast(i)))}, box_rects[i].x + @as(i32,@intCast((box_rects[i].width-8)/2)), box_rects[i].y + 10, FG);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: CONTROLS
// ══════════════════════════════════════════════════════════════════════════════
fn drawControls(
    r: *zui.Renderer,
    field_search: *zui.TextField, field_name: *zui.TextField,
    btn_inc: *zui.Button, btn_reset: *zui.Button, btn_theme: *zui.Button,
    toggle_a: *bool, toggle_b: *bool,
    progress_val: f32,
    search_rect: zui.Rect, name_rect: zui.Rect,
    inc_rect: zui.Rect, rst_rect: zui.Rect, theme_rect: zui.Rect,
    tog_a_rect: zui.Rect, tog_b_rect: zui.Rect,
    dark_mode: bool, theme: zui.Theme,
) void {
    const cx: i32 = NAV_W + 24;
    const cy: i32 = HDR_H + 16;

    r.drawTextScaled("Controls", cx, cy, if (dark_mode) FG else zui.Color.rgb(20,20,20), 2);
    r.drawText("Interactive widgets and inputs", cx, cy + 22, FG_SEC);

    const lx = cx;
    const base = cy + 50;

    // ── TextInput section ─────────────────────────────────────────────────────
    sectionLabel(r, lx, base, "Text Input");
    r.drawText("Search:", lx, base + 42, FG_SEC);
    field_search.draw(r, search_rect, theme);
    if (field_search.text.items.len > 0) {
        r.drawText("Searching for:", lx + 330, base + 51, FG_TER);
        r.drawText(field_search.text.items, lx + 330 + 8 * 14 + 4, base + 51, ACCENT);
    }

    r.drawText("Name:", lx, base + 122, FG_SEC);
    field_name.draw(r, name_rect, theme);
    if (field_name.text.items.len > 0) {
        var greet_buf: [64]u8 = undefined;
        const greet = std.fmt.bufPrint(&greet_buf, "Hello, {s}!", .{field_name.text.items}) catch "";
        r.drawText(greet, lx, base + 165, ACCENT);
    }

    // ── Buttons section ────────────────────────────────────────────────────────
    sectionLabel(r, lx, base + 190, "Buttons");
    btn_inc.draw(r, inc_rect);
    btn_reset.draw(r, rst_rect);
    btn_theme.draw(r, theme_rect);

    r.drawText("^ Accent", lx, base + 248, FG_TER);
    r.drawText("^ Secondary", lx + 140, base + 248, FG_TER);

    // ── Toggle section ─────────────────────────────────────────────────────────
    sectionLabel(r, lx, base + 290, "Toggle");
    drawToggle(r, tog_a_rect, toggle_a.*, "Notifications enabled");
    drawToggle(r, tog_b_rect, toggle_b.*, "Compact mode");

    // ── Progress bar section ──────────────────────────────────────────────────
    sectionLabel(r, lx + 400, base, "Progress");
    const pb_track = zui.Rect.init(lx + 400, base + 30, 300, 8);
    r.fillRect(pb_track, zui.Color.rgb(60,60,65));
    r.fillRect(zui.Rect.init(pb_track.x, pb_track.y, @intFromFloat(@as(f32,@floatFromInt(pb_track.width)) * progress_val), pb_track.height), ACCENT);
    var pct_buf: [8]u8 = undefined;
    const pct_str = std.fmt.bufPrint(&pct_buf, "{d}%", .{@as(u32,@intFromFloat(progress_val * 100))}) catch "";
    r.drawText(pct_str, lx + 400, base + 46, FG_SEC);

    // Indeterminate-style bar
    const pb2 = zui.Rect.init(lx + 400, base + 70, 300, 8);
    r.fillRect(pb2, zui.Color.rgb(60,60,65));
    r.fillRect(zui.Rect.init(pb2.x, pb2.y, 120, pb2.height), zui.Color.rgb(0,160,140));
    r.drawText("Indeterminate", lx + 400, base + 86, FG_TER);

    // ── Color preview row ─────────────────────────────────────────────────────
    sectionLabel(r, lx + 400, base + 110, "Accent variants");
    const accent_swatches = [_]zui.Color{
        zui.Color.rgb(0,80,160), zui.Color.rgb(0,103,192), zui.Color.rgb(0,120,215),
        zui.Color.rgb(0,153,255), zui.Color.rgb(80,180,255),
    };
    for (accent_swatches, 0..) |c, i| {
        r.fillRect(zui.Rect.init(lx + 400 + @as(i32,@intCast(i)) * 56, base + 130, 48, 48), c);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: COLORS
// ══════════════════════════════════════════════════════════════════════════════
fn drawColors(r: *zui.Renderer, dark_mode: bool) void {
    const cx: i32 = NAV_W + 24;
    const cy: i32 = HDR_H + 16;

    r.drawTextScaled("Colors", cx, cy, if (dark_mode) FG else zui.Color.rgb(20,20,20), 2);
    r.drawText("Theme palette and named colors", cx, cy + 22, FG_SEC);

    const base = cy + 50;

    // Fluent design accent ramp
    sectionLabel(r, cx, base, "Accent ramp");
    const blues = [_]zui.Color{
        zui.Color.rgb(0,40,100),   zui.Color.rgb(0,60,140),
        zui.Color.rgb(0,80,160),   zui.Color.rgb(0,103,192),
        zui.Color.rgb(0,120,215),  zui.Color.rgb(0,153,255),
        zui.Color.rgb(80,180,255), zui.Color.rgb(160,210,255),
    };
    for (blues, 0..) |c, i| {
        r.fillRect(zui.Rect.init(cx + @as(i32,@intCast(i)) * 70, base + 20, 62, 62), c);
    }

    // System colors
    sectionLabel(r, cx, base + 100, "System colors");
    const sys_colors = [_]struct{ name: []const u8, color: zui.Color }{
        .{ .name = "Red",    .color = zui.Color.rgb(196, 43, 28)  },
        .{ .name = "Orange", .color = zui.Color.rgb(202, 80,  16) },
        .{ .name = "Yellow", .color = zui.Color.rgb(255, 185,  0) },
        .{ .name = "Green",  .color = zui.Color.rgb( 16, 124, 16) },
        .{ .name = "Teal",   .color = zui.Color.rgb(  0, 153, 153)},
        .{ .name = "Blue",   .color = ACCENT },
        .{ .name = "Purple", .color = zui.Color.rgb(136, 23, 152) },
        .{ .name = "Pink",   .color = zui.Color.rgb(195, 0, 82)   },
    };
    for (sys_colors, 0..) |sc, i| {
        const sx = cx + @as(i32,@intCast(i)) * 70;
        r.fillRect(zui.Rect.init(sx, base + 120, 62, 52), sc.color);
        r.drawText(sc.name, sx, base + 178, FG_SEC);
    }

    // Neutral ramp
    sectionLabel(r, cx, base + 200, "Neutral ramp");
    var ni: u32 = 0;
    while (ni < 8) : (ni += 1) {
        const lum: u8 = @intCast(ni * 30 + 20);
        r.fillRect(zui.Rect.init(cx + @as(i32, @intCast(ni)) * 70, base + 220, 62, 40), zui.Color.rgb(lum, lum, lum));
    }

    // lerp demo
    sectionLabel(r, cx, base + 278, "Color.lerp demo");
    const c_from = zui.Color.rgb(0, 103, 192);
    const c_to   = zui.Color.rgb(196, 43, 28);
    var li: u32 = 0;
    while (li < 16) : (li += 1) {
        const t: f32 = @as(f32,@floatFromInt(li)) / 15.0;
        const lc = c_from.lerp(c_to, t);
        r.fillRect(zui.Rect.init(cx + @as(i32,@intCast(li)) * 34, base + 298, 32, 28), lc);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: LAYOUT
// ══════════════════════════════════════════════════════════════════════════════
fn drawLayout(r: *zui.Renderer, dark_mode: bool, theme: zui.Theme) void {
    const cx: i32 = NAV_W + 24;
    const cy: i32 = HDR_H + 16;

    r.drawTextScaled("Layout", cx, cy, if (dark_mode) FG else zui.Color.rgb(20,20,20), 2);
    r.drawText("BoxLayout and GridLayout engines", cx, cy + 22, FG_SEC);

    const base = cy + 50;
    const right_cx: i32 = cx + 380;

    // ── BoxLayout demos ────────────────────────────────────────────────────────
    sectionLabel(r, cx, base, "BoxLayout  vertical");
    const vbox_bounds = zui.Rect.init(cx, base + 20, 200, 180);
    drawCard(r, vbox_bounds, dark_mode);
    const vbox = zui.BoxLayout{ .direction = .vertical, .spacing = 8, .padding = .{.top=10,.bottom=10,.left=10,.right=10} };
    const vsizes = [3]zui.Size{ .{.width=180,.height=40}, .{.width=180,.height=40}, .{.width=180,.height=40} };
    var vrects: [3]zui.Rect = undefined;
    vbox.compute(vbox_bounds, &vsizes, &vrects);
    const vcols = [3]zui.Color{ ACCENT, zui.Color.rgb(16,124,16), zui.Color.rgb(200,80,20) };
    for (0..3) |i| {
        r.fillRect(vrects[i], vcols[i]);
        r.drawText(&[1]u8{@as(u8,'A'+@as(u8,@intCast(i)))}, vrects[i].x + 8, vrects[i].y + 14, FG);
    }

    sectionLabel(r, cx, base + 210, "BoxLayout  horizontal");
    const hbox_bounds = zui.Rect.init(cx, base + 230, 340, 60);
    drawCard(r, hbox_bounds, dark_mode);
    const hbox = zui.BoxLayout{ .direction = .horizontal, .spacing = 8, .padding = .{.top=10,.bottom=10,.left=10,.right=10} };
    const hsizes = [3]zui.Size{ .{.width=80,.height=40}, .{.width=120,.height=40}, .{.width=80,.height=40} };
    var hrects: [3]zui.Rect = undefined;
    hbox.compute(hbox_bounds, &hsizes, &hrects);
    for (0..3) |i| {
        r.fillRect(hrects[i], vcols[i]);
        r.drawText(&[1]u8{@as(u8,'A'+@as(u8,@intCast(i)))}, hrects[i].x + 8, hrects[i].y + 14, FG);
    }

    // ── GridLayout demos ────────────────────────────────────────────────────────
    sectionLabel(r, right_cx, base, "GridLayout  2x3");
    const grid_bounds = zui.Rect.init(right_cx, base + 20, 340, 180);
    drawCard(r, grid_bounds, dark_mode);
    const grid = zui.GridLayout{ .cols = 2, .rows = 3, .gap = 8, .padding = 10 };
    var grects: [6]zui.Rect = undefined;
    const gcontent = zui.Container{};
    const ginner = gcontent.contentRect(grid_bounds);
    grid.compute(ginner, &grects);
    const gcols = [6]zui.Color{
        ACCENT, zui.Color.rgb(16,124,16), zui.Color.rgb(200,80,20),
        zui.Color.rgb(136,23,152), zui.Color.rgb(0,153,153), zui.Color.rgb(200,140,0),
    };
    const glabels = [6][]const u8{ "Rect", "Color", "Layout", "Signal", "Event", "Style" };
    for (0..6) |i| {
        r.fillRect(grects[i], gcols[i]);
        r.drawText(glabels[i], grects[i].x + 4, grects[i].y + 4, FG);
    }

    sectionLabel(r, right_cx, base + 210, "GridLayout  3x1  (stat cards)");
    const sg_bounds = zui.Rect.init(right_cx, base + 230, 340, 60);
    const sgrid = zui.GridLayout{ .cols = 3, .rows = 1, .gap = 8, .padding = 0 };
    var sgrects: [3]zui.Rect = undefined;
    sgrid.compute(sg_bounds, &sgrects);
    const sgvals = [3][]const u8{"42", "7", "99"};
    for (0..3) |i| {
        drawCard(r, sgrects[i], dark_mode);
        r.fillRect(zui.Rect.init(sgrects[i].x, sgrects[i].y, sgrects[i].width, 2), vcols[i]);
        r.drawTextScaled(sgvals[i], sgrects[i].x + 8, sgrects[i].y + 12, vcols[i], 2);
    }

    // ── Container demo ──────────────────────────────────────────────────────────
    sectionLabel(r, cx, base + 310, "Container  (titled panel)");
    const con = zui.Container{ .title = "Panel title" };
    const con_bounds = zui.Rect.init(cx, base + 330, 700, 80);
    con.draw(r, con_bounds, theme);
    const con_inner = con.contentRect(con_bounds);
    r.drawText("Content area rendered inside contentRect()", con_inner.x + 8, con_inner.y + 10, FG_SEC);
    r.drawText("contentRect clips to the area below the title bar.", con_inner.x + 8, con_inner.y + 26, FG_TER);
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: ABOUT
// ══════════════════════════════════════════════════════════════════════════════
fn drawAbout(r: *zui.Renderer, about_expanded: *bool, dark_mode: bool) void {
    const cx: i32 = NAV_W + 24;
    const cy: i32 = HDR_H + 16;

    // Big logo
    r.drawTextScaled("zui", cx, cy + 10, ACCENT, 5);
    r.drawTextScaled("gallery", cx + 5 * 8 * 3 + 12, cy + 30, if (dark_mode) FG_SEC else zui.Color.rgb(80,80,90), 2);

    r.drawText("A Qt/WPF-inspired UI framework for Zig 0.16", cx, cy + 70, FG_SEC);
    r.drawText("Milestone 8 - Showcase Demo", cx, cy + 86, FG_TER);
    r.fillRect(zui.Rect.init(cx, cy + 102, 500, 1), SEP);

    const info_y = cy + 116;
    const items = [_][]const u8{
        "Platform:   Win32 native (no dependencies)",
        "Renderer:   Software DIB  or  OpenGL 3.3 core",
        "Widgets:    Button  Label  TextField  Container",
        "Layout:     BoxLayout  GridLayout",
        "Signals:    Signal(T)  connect  emit  (comptime-typed)",
        "Theming:    Theme.dark  /  Theme.light  (runtime toggle)",
        "Font:       8x8 VGA bitmap glyph atlas",
        "Build:      zig build  /  zig build -Dbackend=opengl",
    };
    for (items, 0..) |item, i| {
        r.fillRect(zui.Rect.init(cx, info_y + @as(i32,@intCast(i)) * 22 + 6, 4, 12), ACCENT);
        r.drawText(item, cx + 12, info_y + @as(i32,@intCast(i)) * 22, if (dark_mode) FG else zui.Color.rgb(20,20,20));
    }

    // Expandable section
    const expand_y = info_y + @as(i32, items.len) * 22 + 16;
    r.fillRect(zui.Rect.init(cx, expand_y, 500, 1), SEP);
    r.drawText(if (about_expanded.*) "v  Architecture notes" else ">  Architecture notes (click to expand)",
               cx, expand_y + 8, FG_SEC);

    if (about_expanded.*) {
        const arch_lines = [_][]const u8{
            "Strictly layered: core -> events/signals/style/layout -> graphics/platform -> widgets",
            "No hidden allocations: every fn that allocates takes std.mem.Allocator",
            "Comptime backend selection: -Dbackend= switches renderer at compile time",
            "Signal(T): typed, comptime-verified slots; no string-based dispatch",
        };
        for (arch_lines, 0..) |line, i| {
            r.drawText(line, cx + 12, expand_y + 28 + @as(i32,@intCast(i)) * 18, FG_TER);
        }
    }

    // Expand toggle is handled in the main event loop via mouse_press
}

// ══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════════════════════════════

fn drawCard(r: *zui.Renderer, rect: zui.Rect, dark_mode: bool) void {
    const bg  = if (dark_mode) BG_CARD else zui.Color.rgb(255,255,255);
    // 1px rounded outline then filled rounded body
    r.fillRoundRect(rect, 9, SEP);
    r.fillRoundRect(zui.Rect.init(rect.x+1, rect.y+1, rect.width-2, rect.height-2), 8, bg);
}

fn sectionLabel(r: *zui.Renderer, x: i32, y: i32, label: []const u8) void {
    r.drawText(label, x, y, FG_TER);
    r.fillRect(zui.Rect.init(x, y + 12, @intCast(zui.Renderer.textWidth(label) + 8), 1), SEP);
}

fn drawToggle(r: *zui.Renderer, rect: zui.Rect, on: bool, label: []const u8) void {
    const track_color = if (on) ACCENT else zui.Color.rgb(80, 80, 85);
    r.fillRect(rect, track_color);
    // knob
    const kx = if (on) rect.right() - 22 else rect.x + 2;
    r.fillRect(zui.Rect.init(kx, rect.y + 2, 20, rect.height - 4), FG);
    r.drawText(label, rect.right() + 12, rect.y + 8, FG_SEC);
}
