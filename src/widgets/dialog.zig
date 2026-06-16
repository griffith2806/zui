const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Rect       = @import("../layout/geometry.zig").Rect;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const Event      = @import("../events/event.zig").Event;
const Signal     = @import("../signals/signal.zig").Signal;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

pub const Dialog = struct {
    title:          []const u8,
    visible:        bool = false,
    width:          u32  = 400,
    content_height: u32  = 120,
    ok_label:       []const u8 = "OK",
    cancel_label:   []const u8 = "Cancel",
    ok_clicked:     Signal(void) = .{},
    cancel_clicked: Signal(void) = .{},
    bg:             Color = Color.rgb(36, 36, 38),
    overlay:        Color = Color.rgba(0, 0, 0, 160),
    border:         Color = Color.rgba(255, 255, 255, 40),
    fg:             Color = Color.white,
    radius:         u32   = 8,
    pad:            u32   = 20,
    ok_hovered:     bool  = false,
    cancel_hovered: bool  = false,

    pub fn init(title: []const u8, ok_label: []const u8, cancel_label: []const u8) Dialog {
        return .{
            .title        = title,
            .ok_label     = ok_label,
            .cancel_label = cancel_label,
        };
    }

    pub fn deinit(self: *Dialog, alloc: std.mem.Allocator) void {
        self.ok_clicked.deinit(alloc);
        self.cancel_clicked.deinit(alloc);
    }

    pub fn show(self: *Dialog) void {
        self.visible = true;
    }

    pub fn hide(self: *Dialog) void {
        self.visible      = false;
        self.ok_hovered     = false;
        self.cancel_hovered = false;
    }

    fn dialogRect(self: *const Dialog, window_rect: Rect) Rect {
        const height: u32 = 40 + self.content_height + 52 + self.pad;
        const x = window_rect.x + @as(i32, @intCast((window_rect.width -| self.width) / 2));
        const y = window_rect.y + @as(i32, @intCast((window_rect.height -| height) / 2));
        return Rect.init(x, y, self.width, height);
    }

    fn buttonRects(self: *const Dialog, window_rect: Rect) struct { ok: Rect, cancel: Rect } {
        const dr = self.dialogRect(window_rect);
        const btn_y = dr.bottom() - 52 + 10;
        const ok_x = dr.right() - @as(i32, @intCast(self.pad)) - 100;
        const ok_r = Rect.init(ok_x, btn_y, 100, 34);
        const cancel_r = Rect.init(ok_x - 8 - 100, btn_y, 100, 34);
        return .{ .ok = ok_r, .cancel = cancel_r };
    }

    pub fn draw(self: *const Dialog, r: *Renderer, window_rect: Rect) void {
        if (!self.visible) return;

        // Discard page text queued before the overlay so it doesn't bleed through.
        r.clearTextQueue();
        r.fillRect(window_rect, self.overlay);

        const dr = self.dialogRect(window_rect);

        r.fillRoundRect(dr, self.radius, self.border);
        r.fillRoundRect(
            Rect.init(dr.x + 1, dr.y + 1, dr.width -| 2, dr.height -| 2),
            self.radius,
            self.bg,
        );

        r.drawText(self.title, dr.x + @as(i32, @intCast(self.pad)), dr.y + 12, self.fg);

        const divider_y = dr.y + 40;
        r.fillRect(Rect.init(dr.x + 1, divider_y, dr.width -| 2, 1), self.border);

        const btn_area_bg = Color.rgba(255, 255, 255, 8);
        const btn_hover = Color.rgb(62, 62, 66);
        const btn_normal = Color.rgb(45, 45, 48);

        const rects = self.buttonRects(window_rect);

        const ok_bg = if (self.ok_hovered) btn_hover else btn_normal;
        r.fillRoundRect(rects.ok, 6, self.border);
        r.fillRoundRect(
            Rect.init(rects.ok.x + 1, rects.ok.y + 1, rects.ok.width -| 2, rects.ok.height -| 2),
            6,
            ok_bg,
        );
        const ok_tw = r.textWidth(self.ok_label);
        r.drawText(
            self.ok_label,
            rects.ok.x + @as(i32, @intCast((rects.ok.width -| ok_tw) / 2)),
            rects.ok.y + @as(i32, @intCast(rects.ok.height / 2)) - 7,
            self.fg,
        );

        const cancel_bg = if (self.cancel_hovered) btn_hover else btn_normal;
        r.fillRoundRect(rects.cancel, 6, self.border);
        r.fillRoundRect(
            Rect.init(rects.cancel.x + 1, rects.cancel.y + 1, rects.cancel.width -| 2, rects.cancel.height -| 2),
            6,
            cancel_bg,
        );
        const cancel_tw = r.textWidth(self.cancel_label);
        r.drawText(
            self.cancel_label,
            rects.cancel.x + @as(i32, @intCast((rects.cancel.width -| cancel_tw) / 2)),
            rects.cancel.y + @as(i32, @intCast(rects.cancel.height / 2)) - 7,
            self.fg,
        );

        _ = btn_area_bg;
    }

    pub fn accessNodes(self: *const Dialog, window_rect: Rect, out: []AccessNode) usize {
        if (!self.visible) return 0;
        const rects = self.buttonRects(window_rect);
        var n: usize = 0;
        if (n < out.len) {
            out[n] = .{ .role = .button, .name = self.cancel_label, .bounds = rects.cancel, .state = .{ .enabled = true } };
            n += 1;
        }
        if (n < out.len) {
            out[n] = .{ .role = .button, .name = self.ok_label, .bounds = rects.ok, .state = .{ .enabled = true } };
            n += 1;
        }
        return n;
    }

    pub fn handleEvent(self: *Dialog, event: Event, window_rect: Rect) bool {
        if (!self.visible) return false;

        const rects = self.buttonRects(window_rect);

        switch (event) {
            .key_press => |k| {
                if (k.key == .escape) {
                    self.cancel_clicked.emit({});
                    self.hide();
                }
                return true;
            },
            .mouse_move => |m| {
                self.ok_hovered     = rects.ok.contains(.{ .x = m.x, .y = m.y });
                self.cancel_hovered = rects.cancel.contains(.{ .x = m.x, .y = m.y });
                return true;
            },
            .mouse_press => |m| {
                if (m.button == .left) {
                    if (rects.ok.contains(.{ .x = m.x, .y = m.y })) {
                        self.ok_clicked.emit({});
                        self.hide();
                    } else if (rects.cancel.contains(.{ .x = m.x, .y = m.y })) {
                        self.cancel_clicked.emit({});
                        self.hide();
                    }
                }
                return true;
            },
            .mouse_release => {
                return true;
            },
            else => return true,
        }
    }
};
