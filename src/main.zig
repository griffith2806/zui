const std = @import("std");
const zui = @import("zui");

// ── Palette ──────────────────────────────────────────────────────────────────
const BG         = zui.Color.rgb( 20,  20,  20);
const BG_NAV     = zui.Color.rgb( 28,  28,  30);
const BG_CARD    = zui.Color.rgb( 36,  36,  38);
const BG_INPUT   = zui.Color.rgb( 30,  30,  32);
const ACCENT     = zui.Color.rgb(  0, 103, 192);
const ACCENT_HV  = zui.Color.rgb(  0, 120, 215);
const ACCENT_PR  = zui.Color.rgb(  0,  80, 160);
const FG         = zui.Color.rgb(255, 255, 255);
const FG_SEC     = zui.Color.rgb(178, 178, 185);
const FG_TER     = zui.Color.rgb(110, 110, 118);
const SEP        = zui.Color.rgb( 55,  55,  60);
const NAV_ITEM_H = zui.Color.rgb( 48,  48,  52);
const NAV_ITEM_A = zui.Color.rgb( 42,  42,  48);

const NAV_W: i32 = 220;
const HDR_H: i32 = 48;
var W: u32 = 1060;
var H: u32 = 680;

// ── Navigation ───────────────────────────────────────────────────────────────
const Page = enum { dashboard, controls, inputs, overlays, colors, layout, about };

const NAV_ITEMS = [_]struct { label: []const u8, page: Page, icon: []const u8 }{
    .{ .label = "Dashboard", .page = .dashboard, .icon = "D" },
    .{ .label = "Controls",  .page = .controls,  .icon = "C" },
    .{ .label = "Inputs",    .page = .inputs,    .icon = "I" },
    .{ .label = "Overlays",  .page = .overlays,  .icon = "O" },
    .{ .label = "Colors",    .page = .colors,    .icon = "P" },
    .{ .label = "Layout",    .page = .layout,    .icon = "L" },
    .{ .label = "About",     .page = .about,     .icon = "A" },
};

// ── Shared sample data ────────────────────────────────────────────────────────
const LANG_ITEMS = [_][]const u8{ "Zig", "Rust", "C", "C++", "Go", "Swift", "Kotlin", "Python" };
const TAB_LABELS = [_][]const u8{ "Accent", "Standard", "Ghost" };
const MENU_ITEMS = [_]zui.MenuItem{
    .{ .label = "New File" },
    .{ .label = "Open..." },
    .{ .label = "", .separator = true },
    .{ .label = "Save" },
    .{ .label = "Save As..." },
    .{ .label = "", .separator = true },
    .{ .label = "Exit", .enabled = false },
};

// ── Content-area origin helpers ───────────────────────────────────────────────
fn cx() i32 { return NAV_W + 24; }
fn cy() i32 { return HDR_H + 60; }

// ══════════════════════════════════════════════════════════════════════════════
// PAGE STATE: Controls
// ══════════════════════════════════════════════════════════════════════════════
const ControlsState = struct {
    field_search: zui.TextField   = .{},
    field_name:   zui.TextField   = .{},
    slider_vol:   zui.Slider      = .{ .value = 0.62 },
    cb_notify:    zui.Checkbox    = .{ .label = "Enable notifications", .checked = true },
    cb_compact:   zui.Checkbox    = .{ .label = "Compact mode" },
    btn_inc:      zui.Button      = .{ .label = "Increment" },
    btn_reset:    zui.Button      = .{ .label = "Reset" },
    btn_theme:    zui.Button      = .{ .label = "Toggle Theme" },
    pb:           zui.ProgressBar = .{},
    pb_time:      f32             = 0,
    tabs:         zui.TabView     = .{ .tabs = &TAB_LABELS },
    counter:      i32             = 0,

    pub fn init(self: *ControlsState, alloc: std.mem.Allocator, dark_mode: *bool) !void {
        _ = try self.btn_inc.clicked.connect(alloc, &self.counter,
            struct { fn f(p: *i32, _: void) void { p.* += 1; } }.f);
        _ = try self.btn_reset.clicked.connect(alloc, &self.counter,
            struct { fn f(p: *i32, _: void) void { p.* = 0; } }.f);
        _ = try self.btn_theme.clicked.connect(alloc, dark_mode,
            struct { fn f(p: *bool, _: void) void { p.* = !p.*; } }.f);
    }

    pub fn deinit(self: *ControlsState, alloc: std.mem.Allocator) void {
        self.field_search.deinit(alloc);
        self.field_name.deinit(alloc);
        self.slider_vol.deinit(alloc);
        self.cb_notify.deinit(alloc);
        self.cb_compact.deinit(alloc);
        self.btn_inc.deinit(alloc);
        self.btn_reset.deinit(alloc);
        self.btn_theme.deinit(alloc);
        self.tabs.deinit(alloc);
    }

    pub fn handleEvent(self: *ControlsState, ev: zui.Event, alloc: std.mem.Allocator) void {
        const lx = cx(); const base = cy();
        _ = self.field_search.handleEvent(ev, zui.Rect.init(lx, base + 40, 300, 34), alloc);
        _ = self.field_name.handleEvent(ev, zui.Rect.init(lx, base + 100, 280, 34), alloc);
        _ = self.btn_inc.handleEvent(ev, zui.Rect.init(lx, base + 170, 130, 34));
        _ = self.btn_reset.handleEvent(ev, zui.Rect.init(lx + 140, base + 170, 100, 34));
        _ = self.btn_theme.handleEvent(ev, zui.Rect.init(lx, base + 214, 160, 34));
        _ = self.slider_vol.handleEvent(ev, zui.Rect.init(lx, base + 278, 300, 30));
        _ = self.cb_notify.handleEvent(ev, lx, base + 328);
        _ = self.cb_compact.handleEvent(ev, lx, base + 363);
        _ = self.tabs.handleEvent(ev, zui.Rect.init(lx + 420, base + 20, 340, 40));
    }

    pub fn update(self: *ControlsState, dt_s: f32, theme: zui.Theme) void {
        self.btn_inc.update(dt_s);
        self.btn_reset.update(dt_s);
        self.btn_theme.update(dt_s);
        self.cb_notify.update(dt_s);
        self.cb_compact.update(dt_s);
        self.pb_time = @mod(self.pb_time + dt_s, 5.0);
        self.pb.setValue(@min(1.0, self.pb_time / 4.0));
        self.pb.update(dt_s);
        self.btn_inc.style   = .{ .bg = ACCENT,       .bg_hover = ACCENT_HV,       .bg_press = ACCENT_PR,      .fg = FG };
        self.btn_reset.style = .{ .bg = theme.btn_bg, .bg_hover = theme.btn_hover,  .bg_press = theme.btn_press, .fg = theme.fg };
        self.btn_theme.style = .{ .bg = theme.btn_bg, .bg_hover = theme.btn_hover,  .bg_press = theme.btn_press, .fg = theme.fg };
    }

    pub fn draw(self: *const ControlsState, r: *zui.Renderer, dark_mode: bool, theme: zui.Theme) void {
        const lx = cx(); const base = cy(); const ly = HDR_H + 16;
        const rx: i32 = lx + 420;

        r.drawTextScaled("Controls", lx, ly, if (dark_mode) FG else zui.Color.rgb(20,20,20), 2);
        r.drawText("Interactive widgets and inputs", lx, ly + 30, FG_SEC);

        // Text inputs
        sectionLabel(r, lx, base, "Text Input");
        r.drawText("Search:", lx, base + 42, FG_SEC);
        self.field_search.draw(r, zui.Rect.init(lx, base + 40, 300, 34), theme);
        if (self.field_search.text.items.len > 0)
            r.drawText(self.field_search.text.items, lx + 310, base + 51, ACCENT);
        r.drawText("Name:", lx, base + 102, FG_SEC);
        self.field_name.draw(r, zui.Rect.init(lx, base + 100, 280, 34), theme);
        if (self.field_name.text.items.len > 0) {
            var buf: [80]u8 = undefined;
            const greet = std.fmt.bufPrint(&buf, "Hello, {s}!", .{self.field_name.text.items}) catch "";
            r.drawText(greet, lx, base + 144, ACCENT);
        }

        // Buttons
        sectionLabel(r, lx, base + 158, "Buttons");
        self.btn_inc.draw(r, zui.Rect.init(lx, base + 170, 130, 34));
        self.btn_reset.draw(r, zui.Rect.init(lx + 140, base + 170, 100, 34));
        self.btn_theme.draw(r, zui.Rect.init(lx, base + 214, 160, 34));
        var cnt_buf: [16]u8 = undefined;
        const cnt_str = std.fmt.bufPrint(&cnt_buf, "count: {d}", .{self.counter}) catch "";
        r.drawText(cnt_str, lx + 170, base + 222, FG_SEC);

        // Slider
        sectionLabel(r, lx, base + 256, "Slider");
        const vol_r = zui.Rect.init(lx, base + 278, 300, 30);
        self.slider_vol.draw(r, vol_r);
        var vol_buf: [8]u8 = undefined;
        const vol_str = std.fmt.bufPrint(&vol_buf, "{d:.0}%", .{self.slider_vol.value * 100.0}) catch "";
        r.drawText(vol_str, vol_r.right() + 12, vol_r.y + 6, FG_SEC);

        // Checkboxes
        sectionLabel(r, lx, base + 316, "Checkbox");
        self.cb_notify.draw(r, lx, base + 328);
        self.cb_compact.draw(r, lx, base + 363);

        // ── Right column ─────────────────────────────────────────────────────
        // Tab view
        sectionLabel(r, rx, base, "Tab View");
        const tab_r = zui.Rect.init(rx, base + 20, 340, 40);
        self.tabs.draw(r, tab_r);
        const tc = self.tabs.contentRect(tab_r);
        drawCard(r, zui.Rect.init(tc.x, tc.y, tc.width, 60), dark_mode);
        const tab_desc = [_][]const u8{
            "Accent-colored primary action button",
            "Neutral style for secondary actions",
            "Minimal ghost button — no background fill",
        };
        r.drawText(tab_desc[@min(self.tabs.active, tab_desc.len - 1)], tc.x + 12, tc.y + 8, FG_SEC);
        r.drawText("Click tabs to switch", tc.x + 12, tc.y + 30, FG_TER);

        // Progress bar
        sectionLabel(r, rx, base + 120, "Progress Bar");
        const pb_r = zui.Rect.init(rx, base + 142, 320, 8);
        self.pb.draw(r, pb_r);
        var pct_buf: [12]u8 = undefined;
        const pct_str = std.fmt.bufPrint(&pct_buf, "{d:.0}%", .{self.pb.display_t.value * 100.0}) catch "";
        r.drawText(pct_str, pb_r.right() + 8, pb_r.y - 4, FG_SEC);
        r.drawText("Cycles 0 -> 100% over 4s (animated)", rx, base + 158, FG_TER);

        // Accent swatches
        sectionLabel(r, rx, base + 200, "Accent variants");
        const swatches = [_]zui.Color{
            zui.Color.rgb(0, 80, 160), ACCENT, ACCENT_HV,
            zui.Color.rgb(0, 153, 255), zui.Color.rgb(80, 180, 255),
        };
        for (swatches, 0..) |c, i| {
            r.fillRoundRect(zui.Rect.init(rx + @as(i32, @intCast(i)) * 62, base + 220, 54, 54), 6, c);
        }
    }
};

// ══════════════════════════════════════════════════════════════════════════════
// PAGE STATE: Inputs
// ══════════════════════════════════════════════════════════════════════════════
const InputsState = struct {
    text_area: zui.TextArea,
    list_view: zui.ListView = .{ .items = &LANG_ITEMS },
    dropdown:  zui.DropDown = .{ .items = &LANG_ITEMS },

    pub fn init(alloc: std.mem.Allocator) !InputsState {
        var ta = try zui.TextArea.init(alloc);
        ta.placeholder = "Type notes here...";
        return .{ .text_area = ta };
    }

    pub fn deinit(self: *InputsState, alloc: std.mem.Allocator) void {
        self.text_area.deinit(alloc);
        self.list_view.deinit(alloc);
        self.dropdown.deinit(alloc);
    }

    pub fn handleEvent(self: *InputsState, ev: zui.Event, alloc: std.mem.Allocator) void {
        const lx = cx(); const base = cy();
        const rx: i32 = lx + 380;
        _ = self.text_area.handleEvent(ev, zui.Rect.init(lx, base + 40, 330, 220), alloc);
        _ = self.list_view.handleEvent(ev, zui.Rect.init(rx, base + 40, 260, 180));
        _ = self.dropdown.handleEvent(ev, zui.Rect.init(rx, base + 278, 260, 36));
    }

    pub fn draw(self: *const InputsState, r: *zui.Renderer, dark_mode: bool) void {
        const lx = cx(); const base = cy(); const ly = HDR_H + 16;
        const rx: i32 = lx + 380;
        _ = dark_mode;

        r.drawTextScaled("Inputs", lx, ly, FG, 2);
        r.drawText("Text area, list selection, and dropdown picker", lx, ly + 30, FG_SEC);

        sectionLabel(r, lx, base, "Text Area");
        r.drawText("Multiline editor — Enter, Backspace, arrow keys", lx, base + 20, FG_TER);
        self.text_area.draw(r, zui.Rect.init(lx, base + 40, 330, 220));

        sectionLabel(r, rx, base, "List View");
        r.drawText("Click to select, scroll wheel to browse", rx, base + 20, FG_TER);
        self.list_view.draw(r, zui.Rect.init(rx, base + 40, 260, 180));
        if (self.list_view.selected) |sel| {
            var buf: [48]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "Selected: {s}", .{LANG_ITEMS[sel]}) catch "";
            r.drawText(s, rx, base + 228, FG_SEC);
        }

        sectionLabel(r, rx, base + 238, "Drop Down");
        r.drawText("Click to open, select a language", rx, base + 258, FG_TER);
        self.dropdown.draw(r, zui.Rect.init(rx, base + 278, 260, 36));
        var dd_buf: [48]u8 = undefined;
        const dd_str = std.fmt.bufPrint(&dd_buf, "Picked: {s}", .{LANG_ITEMS[self.dropdown.selected]}) catch "";
        r.drawText(dd_str, rx, base + 324, FG_SEC);
    }
};

// ══════════════════════════════════════════════════════════════════════════════
// PAGE STATE: Overlays
// ══════════════════════════════════════════════════════════════════════════════
const OverlaysState = struct {
    dialog_btn:    zui.Button  = .{ .label = "Open Dialog" },
    menu_btn:      zui.Button  = .{ .label = "Open Menu" },
    dialog:        zui.Dialog,
    menu:          zui.Menu    = .{ .items = &MENU_ITEMS },
    tooltip:       zui.Tooltip = .{ .text = "Tooltip: hover 0.5s to trigger" },
    tip_hovered:   bool        = false,
    dialog_result: ?bool       = null,
    menu_result:   ?usize      = null,

    pub fn initDefault() OverlaysState {
        return .{ .dialog = zui.Dialog.init("Confirm Action", "Confirm", "Cancel") };
    }

    pub fn initSignals(self: *OverlaysState, alloc: std.mem.Allocator) !void {
        _ = try self.dialog_btn.clicked.connect(alloc, &self.dialog,
            struct { fn f(d: *zui.Dialog, _: void) void { d.show(); } }.f);
        _ = try self.dialog.ok_clicked.connect(alloc, &self.dialog_result,
            struct { fn f(r: *?bool, _: void) void { r.* = true; } }.f);
        _ = try self.dialog.cancel_clicked.connect(alloc, &self.dialog_result,
            struct { fn f(r: *?bool, _: void) void { r.* = false; } }.f);
        _ = try self.menu.selected.connect(alloc, &self.menu_result,
            struct { fn f(r: *?usize, idx: usize) void { r.* = idx; } }.f);
    }

    pub fn deinit(self: *OverlaysState, alloc: std.mem.Allocator) void {
        self.dialog_btn.deinit(alloc);
        self.menu_btn.deinit(alloc);
        self.dialog.deinit(alloc);
        self.menu.deinit(alloc);
    }

    pub fn handleEvent(self: *OverlaysState, ev: zui.Event, win_rect: zui.Rect) void {
        const lx = cx(); const base = cy();
        const rx: i32 = lx + 420;
        const tip_area = zui.Rect.init(lx, base + 160, 220, 70);

        // Modal/overlay events take priority
        if (self.dialog.visible) { _ = self.dialog.handleEvent(ev, win_rect); return; }
        if (self.menu.open)      { _ = self.menu.handleEvent(ev); return; }

        _ = self.dialog_btn.handleEvent(ev, zui.Rect.init(lx, base + 40, 140, 34));

        // Open menu on click: handleEvent returns true on press (pressed=true) and
        // on release (pressed=false). Only show menu on release (!pressed).
        if (self.menu_btn.handleEvent(ev, zui.Rect.init(rx, base + 40, 140, 34))) {
            if (!self.menu_btn.pressed) self.menu.show(zui.Rect.init(rx, base + 40, 140, 34));
        }

        switch (ev) {
            .mouse_move => |m| { self.tip_hovered = tip_area.contains(.{ .x = m.x, .y = m.y }); },
            else => {},
        }
    }

    pub fn update(self: *OverlaysState, dt_s: f32) void {
        self.dialog_btn.update(dt_s);
        self.menu_btn.update(dt_s);
        self.tooltip.update(dt_s, self.tip_hovered);
        self.dialog_btn.style = .{ .bg = ACCENT, .bg_hover = ACCENT_HV, .bg_press = ACCENT_PR, .fg = FG };
        self.menu_btn.style   = .{ .bg = ACCENT, .bg_hover = ACCENT_HV, .bg_press = ACCENT_PR, .fg = FG };
    }

    pub fn draw(self: *const OverlaysState, r: *zui.Renderer, dark_mode: bool, win_rect: zui.Rect) void {
        const lx = cx(); const base = cy(); const ly = HDR_H + 16;
        const rx: i32 = lx + 420;
        _ = dark_mode;

        r.drawTextScaled("Overlays", lx, ly, FG, 2);
        r.drawText("Modal dialogs, context menus, and tooltips", lx, ly + 30, FG_SEC);

        // Dialog
        sectionLabel(r, lx, base, "Dialog");
        r.drawText("Opens a modal dialog with OK / Cancel.", lx, base + 22, FG_TER);
        self.dialog_btn.draw(r, zui.Rect.init(lx, base + 40, 140, 34));
        if (self.dialog_result) |ok| {
            r.drawText(if (ok) "You clicked Confirm." else "You clicked Cancel.", lx, base + 88, FG_SEC);
        } else {
            r.drawText("(not yet shown)", lx, base + 88, FG_TER);
        }

        // Menu
        sectionLabel(r, rx, base, "Context Menu");
        r.drawText("Opens a popup menu at the button anchor.", rx, base + 22, FG_TER);
        self.menu_btn.draw(r, zui.Rect.init(rx, base + 40, 140, 34));
        if (self.menu_result) |idx| {
            if (idx < MENU_ITEMS.len and !MENU_ITEMS[idx].separator) {
                var buf: [64]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "Last: {s}", .{MENU_ITEMS[idx].label}) catch "";
                r.drawText(s, rx, base + 88, FG_SEC);
            }
        } else {
            r.drawText("(nothing selected)", rx, base + 88, FG_TER);
        }

        // Tooltip
        sectionLabel(r, lx, base + 120, "Tooltip");
        r.drawText("Hover the box below for 0.5s.", lx, base + 140, FG_TER);
        const tip_area = zui.Rect.init(lx, base + 160, 220, 70);
        r.fillRoundRect(tip_area, 8, zui.Color.rgb(35, 55, 85));
        r.fillRoundRect(zui.Rect.init(tip_area.x + 1, tip_area.y + 1, tip_area.width - 2, tip_area.height - 2), 7,
            zui.Color.rgb(42, 65, 100));
        r.drawText("Hover me", tip_area.x + 70, tip_area.y + 26, FG_SEC);
        self.tooltip.draw(r, tip_area, win_rect);

        // Draw modal layers last so they appear on top
        self.dialog.draw(r, win_rect);
        self.menu.draw(r);
    }
};

// ══════════════════════════════════════════════════════════════════════════════
// MAIN LOOP
// ══════════════════════════════════════════════════════════════════════════════
pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    var app = try zui.Application.init(alloc, .{
        .title  = "zui — Component Gallery",
        .width  = W,
        .height = H,
    });
    defer app.deinit();

    var page: Page     = .dashboard;
    var dark_mode      = true;
    var about_expanded = false;

    var controls = ControlsState{};
    try controls.init(alloc, &dark_mode);
    defer controls.deinit(alloc);

    var inputs = try InputsState.init(alloc);
    defer inputs.deinit(alloc);

    var overlays = OverlaysState.initDefault();
    try overlays.initSignals(alloc);
    defer overlays.deinit(alloc);

    var nav_rects: [NAV_ITEMS.len]zui.Rect = undefined;
    for (0..NAV_ITEMS.len) |i|
        nav_rects[i] = zui.Rect.init(8, HDR_H + 8 + @as(i32, @intCast(i)) * 44,
                                     @intCast(NAV_W - 16), 38);
    var nav_hover_t: [NAV_ITEMS.len]f32  = .{0.0}   ** NAV_ITEMS.len;
    var nav_hovered: [NAV_ITEMS.len]bool = .{false}  ** NAV_ITEMS.len;

    while (!app.window.should_close) {
        const dt_s    = app.deltaSeconds();
        const win_rect = zui.Rect.init(0, 0, W, H);

        // ── Events ──────────────────────────────────────────────────────────
        while (app.pollEvent()) |ev| {
            switch (ev) {
                .close     => app.window.should_close = true,
                .key_press => |k| { if (k.key == .escape) app.window.should_close = true; },
                .mouse_move => |m| {
                    for (nav_rects, 0..) |nr, i|
                        nav_hovered[i] = nr.contains(.{ .x = m.x, .y = m.y });
                },
                .mouse_press => |m| {
                    for (NAV_ITEMS, 0..) |item, i| {
                        if (m.button == .left and nav_rects[i].contains(.{ .x = m.x, .y = m.y }))
                            page = item.page;
                    }
                },
                else => {},
            }
            switch (page) {
                .controls => controls.handleEvent(ev, alloc),
                .inputs   => inputs.handleEvent(ev, alloc),
                .overlays => overlays.handleEvent(ev, win_rect),
                .about    => switch (ev) {
                    .mouse_press => |m| {
                        const exp_y: i32 = HDR_H + 16 + 144 + 9 * 22 + 16;
                        if (m.button == .left and
                            zui.Rect.init(NAV_W + 24, exp_y, 500, 22).contains(.{ .x = m.x, .y = m.y }))
                            about_expanded = !about_expanded;
                    },
                    else => {},
                },
                else => {},
            }
        }

        // ── Update ──────────────────────────────────────────────────────────
        app.syncSize();
        W = app.window.width;
        H = app.window.height;

        const theme = if (dark_mode) zui.Theme.dark else zui.Theme.light;
        controls.update(dt_s, theme);
        overlays.update(dt_s);
        for (0..NAV_ITEMS.len) |i| {
            nav_hover_t[i] += (@as(f32, if (nav_hovered[i]) 1.0 else 0.0) - nav_hover_t[i]) *
                              (1.0 - @exp(-10.0 * dt_s));
        }

        // ── Draw ────────────────────────────────────────────────────────────
        app.renderer.clear(if (dark_mode) BG else zui.Color.rgb(240, 240, 245));
        drawSidebar(&app.renderer, page, &nav_rects, &nav_hover_t, dark_mode);
        drawHeader(&app.renderer, page, dark_mode);

        switch (page) {
            .dashboard => drawDashboard(&app.renderer, controls.counter, dark_mode),
            .controls  => controls.draw(&app.renderer, dark_mode, theme),
            .inputs    => inputs.draw(&app.renderer, dark_mode),
            .overlays  => overlays.draw(&app.renderer, dark_mode, zui.Rect.init(0, 0, W, H)),
            .colors    => drawColors(&app.renderer, dark_mode),
            .layout    => drawLayout(&app.renderer, dark_mode, theme),
            .about     => drawAbout(&app.renderer, about_expanded, dark_mode),
        }

        app.present();
        app.capFps(60);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// CHROME: Sidebar + Header
// ══════════════════════════════════════════════════════════════════════════════
fn drawSidebar(
    r: *zui.Renderer,
    page: Page,
    nav_rects: []const zui.Rect,
    nav_hover_t: []const f32,
    dark_mode: bool,
) void {
    const nav_bg = if (dark_mode) BG_NAV else zui.Color.rgb(235, 235, 240);
    r.fillRect(zui.Rect.init(0, 0, @intCast(NAV_W), H), nav_bg);
    r.fillRect(zui.Rect.init(NAV_W, 0, 1, H), SEP);

    const hdr_bg = if (dark_mode) zui.Color.rgb(22, 22, 26) else zui.Color.rgb(220, 220, 228);
    r.fillRect(zui.Rect.init(0, 0, @intCast(NAV_W), @intCast(HDR_H)), hdr_bg);
    r.drawTextScaled("zui", 16, 10, ACCENT, 2);
    const logo_w: i32 = @intCast(r.textWidthScaled("zui", 2));
    r.drawText("gallery", 16 + logo_w + 8, 20, FG_TER);

    for (NAV_ITEMS, 0..) |item, i| {
        const nr = nav_rects[i];
        const active = item.page == page;
        if (active) {
            r.fillRoundRect(nr, 6, NAV_ITEM_A);
            r.fillRect(zui.Rect.init(nr.x, nr.y + 6, 4, nr.height - 12), ACCENT);
        } else if (nav_hover_t[i] > 0.02) {
            r.fillRoundRect(nr, 6, BG_NAV.lerp(NAV_ITEM_H, nav_hover_t[i]));
        }
        r.drawText(item.icon,  nr.x + 10, nr.y + 10, if (active) ACCENT else FG_TER);
        r.drawText(item.label, nr.x + 28, nr.y + 10, if (active) FG    else FG_SEC);
    }

    const sx: i32 = HDR_H + 8 + @as(i32, NAV_ITEMS.len) * 44 + 8;
    const search_r = zui.Rect.init(8, sx, @intCast(NAV_W - 16), 30);
    r.fillRoundRect(search_r, 6, SEP);
    r.fillRoundRect(zui.Rect.init(search_r.x + 1, search_r.y + 1, search_r.width - 2, search_r.height - 2),
        5, if (dark_mode) BG_INPUT else zui.Color.rgb(250, 250, 255));
    r.drawText("Search...", search_r.x + 10, search_r.y + 7, FG_TER);

    r.drawText("v0.7  gap-close", 10, @as(i32, @intCast(H)) - 22, FG_TER);
}

fn drawHeader(r: *zui.Renderer, page: Page, dark_mode: bool) void {
    const content_w = W -| @as(u32, @intCast(NAV_W));
    const top_bg = if (dark_mode) zui.Color.rgb(24, 24, 28) else zui.Color.rgb(248, 248, 252);
    r.fillRect(zui.Rect.init(NAV_W, 0, content_w, @intCast(HDR_H)), top_bg);
    r.fillRect(zui.Rect.init(NAV_W, HDR_H, content_w, 1), SEP);

    const page_name = switch (page) {
        .dashboard => "Dashboard", .controls => "Controls", .inputs => "Inputs",
        .overlays  => "Overlays",  .colors   => "Colors",   .layout => "Layout",
        .about     => "About",
    };
    const bx = NAV_W + 20;
    const gw: i32 = @intCast(r.textWidth("zui Gallery"));
    r.drawText("zui Gallery", bx,          14, FG_TER);
    r.drawText(">",           bx + gw + 6, 14, FG_TER);
    r.drawText(page_name,     bx + gw + 24, 14, FG_SEC);
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: Dashboard
// ══════════════════════════════════════════════════════════════════════════════
fn drawDashboard(r: *zui.Renderer, counter: i32, dark_mode: bool) void {
    const lx = cx(); const lcy = HDR_H + 16;

    r.drawTextScaled("Dashboard", lx, lcy, if (dark_mode) FG else zui.Color.rgb(20,20,20), 2);
    r.drawText("Welcome to the zui component gallery", lx, lcy + 30, FG_SEC);

    const card_y: i32 = lcy + 60;
    const avail_w: u32 = W -| @as(u32, @intCast(lx + 24));

    // Stat cards
    const stat_grid = zui.GridLayout{ .cols = 3, .rows = 1, .gap = 12, .padding = 0 };
    var stat_rects: [3]zui.Rect = undefined;
    stat_grid.compute(zui.Rect.init(lx, card_y, avail_w, 100), &stat_rects);
    const stats = [3]struct { label: []const u8, value: []const u8, color: zui.Color }{
        .{ .label = "Widgets",  .value = "15", .color = ACCENT },
        .{ .label = "Backends", .value = "2",  .color = zui.Color.rgb(16, 140, 16) },
        .{ .label = "Signals",  .value = "ok", .color = zui.Color.rgb(200, 140, 0) },
    };
    for (stats, 0..) |stat, i| {
        drawCard(r, stat_rects[i], dark_mode);
        r.fillRect(zui.Rect.init(stat_rects[i].x, stat_rects[i].y, stat_rects[i].width, 3), stat.color);
        r.drawTextScaled(stat.value, stat_rects[i].x + 16, stat_rects[i].y + 16, stat.color, 3);
        r.drawText(stat.label, stat_rects[i].x + 16, stat_rects[i].y + 70, FG_SEC);
    }

    // Counter card
    const cnt_card = zui.Rect.init(lx, card_y + 116, 360, 90);
    drawCard(r, cnt_card, dark_mode);
    r.drawText("Counter  (Signal demo)", cnt_card.x + 16, cnt_card.y + 12, FG_SEC);
    r.fillRect(zui.Rect.init(cnt_card.x + 16, cnt_card.y + 32, cnt_card.width - 32, 1), SEP);
    var buf: [16]u8 = undefined;
    const val_str = std.fmt.bufPrint(&buf, "{d}", .{counter}) catch "?";
    const val_w = r.textWidthScaled(val_str, 4);
    const vx = cnt_card.x + 16 + @as(i32, @intCast((cnt_card.width - 32 -| val_w) / 2));
    r.drawTextScaled(val_str, vx, cnt_card.y + 38, ACCENT, 4);

    // Milestone card
    const feat_x: i32 = lx + 376;
    const feat_w: u32 = W -| @as(u32, @intCast(feat_x + 24));
    const feat_card = zui.Rect.init(feat_x, card_y + 116, feat_w, 260);
    drawCard(r, feat_card, dark_mode);
    r.drawText("Completed milestones", feat_card.x + 16, feat_card.y + 12, FG_SEC);
    r.fillRect(zui.Rect.init(feat_card.x + 16, feat_card.y + 32, feat_card.width - 32, 1), SEP);
    const features = [_][]const u8{
        "M0-M4   Foundations, Win32, Widgets, OpenGL",
        "M8-M9   Gallery, Mica, rounded corners",
        "M10-M13 GDI typography, animations, clipboard",
        "Gap:     FocusManager, Font descriptor",
        "Gap:     FlowLayout, BoxLayout flex",
        "Gap:     Signal Connection safety",
        "Gap:     ProgressBar, TabView, ScrollArea",
        "Gap:     TextArea, ListView, DropDown",
        "Gap:     Tooltip, Dialog, Menu",
        "Gap:     Image type + drawImageRaw",
        "Gap:     X11 platform stub (Linux)",
    };
    for (features, 0..) |feat, i| {
        r.fillRect(zui.Rect.init(feat_card.x + 16, feat_card.y + 40 + @as(i32, @intCast(i)) * 18 + 5, 4, 4), ACCENT);
        r.drawText(feat, feat_card.x + 28, feat_card.y + 40 + @as(i32, @intCast(i)) * 18,
            if (dark_mode) FG else zui.Color.rgb(20,20,20));
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: Colors
// ══════════════════════════════════════════════════════════════════════════════
fn drawColors(r: *zui.Renderer, dark_mode: bool) void {
    const lx = cx(); const lcy = HDR_H + 16;
    const base = lcy + 60;

    r.drawTextScaled("Colors", lx, lcy, if (dark_mode) FG else zui.Color.rgb(20,20,20), 2);
    r.drawText("Theme palette and named colors", lx, lcy + 30, FG_SEC);

    sectionLabel(r, lx, base, "Accent ramp");
    const blues = [_]zui.Color{
        zui.Color.rgb(0,40,100), zui.Color.rgb(0,60,140), zui.Color.rgb(0,80,160), ACCENT,
        zui.Color.rgb(0,120,215), zui.Color.rgb(0,153,255), zui.Color.rgb(80,180,255), zui.Color.rgb(160,210,255),
    };
    for (blues, 0..) |c, i|
        r.fillRoundRect(zui.Rect.init(lx + @as(i32, @intCast(i)) * 70, base + 20, 62, 62), 6, c);

    sectionLabel(r, lx, base + 100, "System colors");
    const sys = [_]struct { name: []const u8, color: zui.Color }{
        .{ .name = "Red",    .color = zui.Color.rgb(196, 43, 28)  },
        .{ .name = "Orange", .color = zui.Color.rgb(202, 80, 16)  },
        .{ .name = "Yellow", .color = zui.Color.rgb(255, 185, 0)  },
        .{ .name = "Green",  .color = zui.Color.rgb(16, 124, 16)  },
        .{ .name = "Teal",   .color = zui.Color.rgb(0, 153, 153)  },
        .{ .name = "Blue",   .color = ACCENT                       },
        .{ .name = "Purple", .color = zui.Color.rgb(136, 23, 152) },
        .{ .name = "Pink",   .color = zui.Color.rgb(195, 0, 82)   },
    };
    for (sys, 0..) |sc, i| {
        const sx = lx + @as(i32, @intCast(i)) * 70;
        r.fillRoundRect(zui.Rect.init(sx, base + 122, 62, 52), 6, sc.color);
        r.drawText(sc.name, sx, base + 180, FG_SEC);
    }

    sectionLabel(r, lx, base + 210, "Neutral ramp");
    for (0..8) |ni| {
        const lum: u8 = @intCast(ni * 30 + 20);
        r.fillRoundRect(zui.Rect.init(lx + @as(i32, @intCast(ni)) * 70, base + 230, 62, 40), 6,
            zui.Color.rgb(lum, lum, lum));
    }

    sectionLabel(r, lx, base + 290, "Color.lerp  demo");
    for (0..16) |li| {
        const t: f32 = @as(f32, @floatFromInt(li)) / 15.0;
        r.fillRoundRect(zui.Rect.init(lx + @as(i32, @intCast(li)) * 34, base + 310, 32, 28), 4,
            ACCENT.lerp(zui.Color.rgb(196, 43, 28), t));
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: Layout
// ══════════════════════════════════════════════════════════════════════════════
fn drawLayout(r: *zui.Renderer, dark_mode: bool, theme: zui.Theme) void {
    const lx = cx(); const lcy = HDR_H + 16;
    const base = lcy + 60;
    const rx: i32 = lx + 380;
    const cols = [3]zui.Color{ ACCENT, zui.Color.rgb(16,124,16), zui.Color.rgb(200,80,20) };

    r.drawTextScaled("Layout", lx, lcy, if (dark_mode) FG else zui.Color.rgb(20,20,20), 2);
    r.drawText("BoxLayout, GridLayout, FlowLayout", lx, lcy + 30, FG_SEC);

    // BoxLayout vertical
    sectionLabel(r, lx, base, "BoxLayout  vertical");
    const vbox_b = zui.Rect.init(lx, base + 20, 200, 190);
    drawCard(r, vbox_b, dark_mode);
    const vbox = zui.BoxLayout{ .direction = .vertical, .spacing = 8,
        .padding = .{ .top = 10, .bottom = 10, .left = 10, .right = 10 } };
    const vsizes = [3]zui.Size{ .{.width=180,.height=42}, .{.width=180,.height=42}, .{.width=180,.height=42} };
    var vrects: [3]zui.Rect = undefined;
    vbox.compute(vbox_b, &vsizes, &vrects);
    for (vrects, 0..) |vr, i| {
        r.fillRoundRect(vr, 4, cols[i]);
        r.drawText(&[1]u8{@as(u8,'A') + @as(u8,@intCast(i))}, vr.x + 8, vr.y + 13, FG);
    }

    // BoxLayout horizontal
    sectionLabel(r, lx, base + 220, "BoxLayout  horizontal");
    const hbox_b = zui.Rect.init(lx, base + 240, 340, 60);
    drawCard(r, hbox_b, dark_mode);
    const hbox = zui.BoxLayout{ .direction = .horizontal, .spacing = 8,
        .padding = .{ .top = 10, .bottom = 10, .left = 10, .right = 10 } };
    const hsizes = [3]zui.Size{ .{.width=80,.height=40}, .{.width=120,.height=40}, .{.width=80,.height=40} };
    var hrects: [3]zui.Rect = undefined;
    hbox.compute(hbox_b, &hsizes, &hrects);
    for (hrects, 0..) |hr, i| {
        r.fillRoundRect(hr, 4, cols[i]);
        r.drawText(&[1]u8{@as(u8,'A') + @as(u8,@intCast(i))}, hr.x + 8, hr.y + 12, FG);
    }

    // FlowLayout
    sectionLabel(r, lx, base + 322, "FlowLayout  (wrap)");
    const flow_b = zui.Rect.init(lx, base + 342, 340, 88);
    drawCard(r, flow_b, dark_mode);
    const flow = zui.FlowLayout{ .gap_x = 8, .gap_y = 8,
        .padding = .{ .top = 8, .bottom = 8, .left = 8, .right = 8 } };
    const fsizes = [6]zui.Size{
        .{.width=70,.height=30}, .{.width=70,.height=30}, .{.width=70,.height=30},
        .{.width=70,.height=30}, .{.width=70,.height=30}, .{.width=70,.height=30},
    };
    var frects: [6]zui.Rect = undefined;
    flow.compute(flow_b, &fsizes, &frects);
    const fcols = [6]zui.Color{ ACCENT, zui.Color.rgb(16,124,16), zui.Color.rgb(200,80,20),
        zui.Color.rgb(136,23,152), zui.Color.rgb(0,153,153), zui.Color.rgb(200,140,0) };
    for (frects, 0..) |fr, i|
        r.fillRoundRect(fr, 4, fcols[i]);

    // GridLayout 2×3
    sectionLabel(r, rx, base, "GridLayout  2x3");
    const grid_b = zui.Rect.init(rx, base + 20, 340, 190);
    drawCard(r, grid_b, dark_mode);
    const grid = zui.GridLayout{ .cols = 2, .rows = 3, .gap = 8, .padding = 10 };
    const con = zui.Container{};
    var grects: [6]zui.Rect = undefined;
    grid.compute(con.contentRect(grid_b), &grects);
    const glabels = [6][]const u8{ "Rect", "Color", "Layout", "Signal", "Event", "Style" };
    for (grects, 0..) |gr, i| {
        r.fillRoundRect(gr, 4, fcols[i]);
        r.drawText(glabels[i], gr.x + 4, gr.y + 4, FG);
    }

    // Container panel
    sectionLabel(r, rx, base + 220, "Container  (titled panel)");
    const cpanel = zui.Container{ .title = "Panel title" };
    const cpanel_b = zui.Rect.init(rx, base + 240, 340, 80);
    cpanel.draw(r, cpanel_b, theme);
    const inner = cpanel.contentRect(cpanel_b);
    r.drawText("Content rendered inside contentRect()", inner.x + 8, inner.y + 10, FG_SEC);
    r.drawText("Title bar is drawn by Container.draw()", inner.x + 8, inner.y + 30, FG_TER);
}

// ══════════════════════════════════════════════════════════════════════════════
// PAGE: About
// ══════════════════════════════════════════════════════════════════════════════
fn drawAbout(r: *zui.Renderer, about_expanded: bool, dark_mode: bool) void {
    const lx = cx(); const lcy = HDR_H + 16;

    r.drawTextScaled("zui", lx, lcy + 10, ACCENT, 5);
    const logo_w: i32 = @intCast(r.textWidthScaled("zui", 5));
    r.drawTextScaled("gallery", lx + logo_w + 16, lcy + 36,
        if (dark_mode) FG_SEC else zui.Color.rgb(80,80,90), 2);

    r.drawText("A Qt/WPF-inspired UI framework for Zig 0.16", lx, lcy + 90, FG_SEC);
    r.drawText("Milestones 0-13 + gap-close complete", lx, lcy + 110, FG_TER);
    r.fillRect(zui.Rect.init(lx, lcy + 130, 500, 1), SEP);

    const info_y = lcy + 144;
    const items = [_][]const u8{
        "Platform:  Win32 native (no dependencies); X11 stub",
        "Renderer:  Software DIB  or  OpenGL 3.3 core",
        "Widgets:   15 widgets including TextArea, ListView, Dialog, Menu",
        "Layout:    BoxLayout (flex)  GridLayout  FlowLayout",
        "Signals:   Signal(T)  connect -> Connection  disconnectHandle",
        "Theming:   Theme.dark  /  Theme.light  (runtime toggle)",
        "Font:      Segoe UI Variable via GDI + Font descriptor type",
        "Anim:      Tween (exponential decay, hover fades, progress bar)",
        "Build:     zig build  /  zig build -Dbackend=opengl",
    };
    for (items, 0..) |item, i| {
        r.fillRect(zui.Rect.init(lx, info_y + @as(i32, @intCast(i)) * 22 + 5, 4, 12), ACCENT);
        r.drawText(item, lx + 12, info_y + @as(i32, @intCast(i)) * 22,
            if (dark_mode) FG else zui.Color.rgb(20,20,20));
    }

    const expand_y: i32 = info_y + @as(i32, items.len) * 22 + 16;
    r.fillRect(zui.Rect.init(lx, expand_y, 500, 1), SEP);
    r.drawText(if (about_expanded) "v  Architecture notes"
               else ">  Architecture notes  (click to expand)",
               lx, expand_y + 8, FG_SEC);

    if (about_expanded) {
        const arch = [_][]const u8{
            "Strictly layered: core -> events/signals/style/layout -> graphics/platform -> widgets",
            "No hidden allocations: every fn that allocates takes std.mem.Allocator",
            "Comptime backend selection: -Dbackend= switches renderer at compile time",
            "Signal(T): typed, comptime-verified; connect returns Connection for safe disconnect",
            "Page structs: each page owns its state; main() is a lean event/update/draw loop",
        };
        for (arch, 0..) |line, i|
            r.drawText(line, lx + 12, expand_y + 28 + @as(i32, @intCast(i)) * 20, FG_TER);
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
