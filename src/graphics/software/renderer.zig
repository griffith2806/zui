const std = @import("std");
const Color = @import("../../style/color.zig").Color;
const Rect  = @import("../../layout/geometry.zig").Rect;
const bfont = @import("font.zig");

// ── Win32 GDI (text rendering on the memory DC) ──────────────────────────────

const HDC    = *opaque {};
const HFONT  = *opaque {};
const DWORD  = u32;
const INT    = i32;
const BOOL   = i32;
const LONG   = i32;

const GdiSize = extern struct { cx: LONG, cy: LONG };

const TRANSPARENT_BK:     INT  = 1;
const FW_NORMAL:          INT  = 400;
const FW_SEMIBOLD:        INT  = 600;
const DEFAULT_CHARSET:    DWORD = 1;
const OUT_DEFAULT_PRECIS: DWORD = 0;
const CLIP_DEFAULT_PRECIS:DWORD = 0;
const DEFAULT_QUALITY:    DWORD = 0;
const FF_SWISS:           DWORD = 0x20;
const TA_LEFT:            UINT  = 0;
const TA_TOP:             UINT  = 0;
const UINT = u32;

const SEGOE_UI = std.unicode.utf8ToUtf16LeStringLiteral("Segoe UI Variable");

extern "gdi32" fn CreateFontW(
    cHeight: INT, cWidth: INT, cEscapement: INT, cOrientation: INT,
    cWeight: INT, bItalic: DWORD, bUnderline: DWORD, bStrikeOut: DWORD,
    iCharSet: DWORD, iOutPrecision: DWORD, iClipPrecision: DWORD,
    iQuality: DWORD, iPitchAndFamily: DWORD, pszFaceName: [*:0]const u16,
) callconv(std.builtin.CallingConvention.winapi) ?HFONT;

extern "gdi32" fn SetTextColor(hdc: HDC, color: DWORD) callconv(std.builtin.CallingConvention.winapi) DWORD;
extern "gdi32" fn SetBkMode(hdc: HDC, iBkMode: INT) callconv(std.builtin.CallingConvention.winapi) INT;
extern "gdi32" fn SetTextAlign(hdc: HDC, fMode: UINT) callconv(std.builtin.CallingConvention.winapi) UINT;
extern "gdi32" fn SelectObject(hdc: HDC, h: *anyopaque) callconv(std.builtin.CallingConvention.winapi) ?*anyopaque;
extern "gdi32" fn DeleteObject(ho: *anyopaque) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "gdi32" fn TextOutW(hdc: HDC, x: INT, y: INT, lpString: [*]const u16, c: INT) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "gdi32" fn GetTextExtentPoint32W(hdc: HDC, lpString: [*]const u16, c: INT, lpSize: *GdiSize) callconv(std.builtin.CallingConvention.winapi) BOOL;

// ── Font size table ───────────────────────────────────────────────────────────
// Indexed by `scale` (1..6).  Scale 0 is unused; scale 1 = body text.
// Pixel heights chosen so scale=1 maps to a comfortable 14px body size.
const FONT_PX = [7]INT{ 0, 14, 22, 32, 44, 60, 80 };
pub const NUM_FONT_SCALES = FONT_PX.len;

// Approximate line-height for layout purposes (scale=1 body text).
pub const LINE_H: u32 = 18;

// ── Pixel format: Win32 DIB BGRA (0x00RRGGBB little-endian) ──────────────────

pub const Renderer = struct {
    pixels: [*]u32,
    width:  u32,
    height: u32,
    // GDI text state — null until initGdi() is called
    gdi_dc:    ?HDC  = null,
    gdi_fonts: [NUM_FONT_SCALES]?HFONT = .{null} ** NUM_FONT_SCALES,

    pub fn init(pixels: [*]u32, width: u32, height: u32) Renderer {
        return .{ .pixels = pixels, .width = width, .height = height };
    }

    /// Call once after init, passing the memory DC from the Win32 window.
    pub fn initGdi(self: *Renderer, dc: *anyopaque) void {
        self.gdi_dc = @ptrCast(dc);
        _ = SetBkMode(self.gdi_dc.?, TRANSPARENT_BK);
        _ = SetTextAlign(self.gdi_dc.?, TA_LEFT | TA_TOP);
        for (FONT_PX, 0..) |px, i| {
            if (px == 0) continue;
            const weight: INT = if (px >= 32) FW_SEMIBOLD else FW_NORMAL;
            self.gdi_fonts[i] = CreateFontW(
                -px, 0, 0, 0, weight, 0, 0, 0,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, FF_SWISS, SEGOE_UI,
            );
        }
    }

    pub fn deinit(self: *Renderer) void {
        for (&self.gdi_fonts) |*hf| {
            if (hf.*) |f| _ = DeleteObject(@ptrCast(f));
            hf.* = null;
        }
    }

    pub fn clear(self: *Renderer, color: Color) void {
        const v = toPixel(color);
        for (0..self.width * self.height) |i| self.pixels[i] = v;
    }

    pub fn fillRect(self: *Renderer, rect: Rect, color: Color) void {
        const v  = toPixel(color);
        const x0 = @max(0, rect.x);
        const y0 = @max(0, rect.y);
        const x1 = @min(@as(i32, @intCast(self.width)),  rect.right());
        const y1 = @min(@as(i32, @intCast(self.height)), rect.bottom());
        if (x0 >= x1 or y0 >= y1) return;
        var y: i32 = y0;
        while (y < y1) : (y += 1) {
            const row: u32 = @as(u32, @intCast(y)) * self.width;
            var x: i32 = x0;
            while (x < x1) : (x += 1) {
                self.pixels[row + @as(u32, @intCast(x))] = v;
            }
        }
    }

    // ── Text rendering ────────────────────────────────────────────────────────

    /// Draw body text (scale=1 / 14px Segoe UI, or 8×8 bitmap fallback).
    pub fn drawText(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color) void {
        self.drawTextScale(text, x, y, color, 1);
    }

    /// Draw text at an integer scale (1=14px, 2=22px, 3=32px …).
    pub fn drawTextScaled(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color, scale: u32) void {
        self.drawTextScale(text, x, y, color, scale);
    }

    fn drawTextScale(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color, scale: u32) void {
        const idx = @min(scale, NUM_FONT_SCALES - 1);
        if (self.gdi_dc) |dc| {
            if (self.gdi_fonts[idx]) |hf| {
                _ = SelectObject(dc, @ptrCast(hf));
                const cr: DWORD = @as(DWORD, color.r) | (@as(DWORD, color.g) << 8) | (@as(DWORD, color.b) << 16);
                _ = SetTextColor(dc, cr);
                var wbuf: [1024]u16 = undefined;
                const wlen = std.unicode.utf8ToUtf16Le(&wbuf, text) catch return;
                _ = TextOutW(dc, @intCast(x), @intCast(y), wbuf[0..wlen].ptr, @intCast(wlen));
                return;
            }
        }
        // Fallback: bitmap font
        if (scale <= 1) {
            self.drawBitmapText(text, x, y, color);
        } else {
            self.drawBitmapTextScaled(text, x, y, color, scale);
        }
    }

    /// Measure text width in pixels using GDI or bitmap fallback.
    pub fn textWidth(self: *const Renderer, text: []const u8) u32 {
        return self.textWidthScaled(text, 1);
    }

    pub fn textWidthScaled(self: *const Renderer, text: []const u8, scale: u32) u32 {
        const idx = @min(scale, NUM_FONT_SCALES - 1);
        if (self.gdi_dc) |dc| {
            if (self.gdi_fonts[idx]) |hf| {
                _ = SelectObject(@constCast(dc), @ptrCast(@constCast(hf)));
                var wbuf: [1024]u16 = undefined;
                const wlen = std.unicode.utf8ToUtf16Le(&wbuf, text) catch return 0;
                var sz: GdiSize = undefined;
                _ = GetTextExtentPoint32W(@constCast(dc), wbuf[0..wlen].ptr, @intCast(wlen), &sz);
                return @intCast(@max(0, sz.cx));
            }
        }
        return @intCast(text.len * bfont.GLYPH_W * scale);
    }

    // ── Alpha blending ────────────────────────────────────────────────────────

    fn blendPixel(self: *Renderer, x: u32, y: u32, color: Color) void {
        if (x >= self.width or y >= self.height) return;
        const idx = y * self.width + x;
        if (color.a == 255) {
            self.pixels[idx] = toPixel(color);
        } else if (color.a > 0) {
            const bg    = self.pixels[idx];
            const bg_r: u32 = (bg >> 16) & 0xFF;
            const bg_g: u32 = (bg >>  8) & 0xFF;
            const bg_b: u32 =  bg        & 0xFF;
            const af  = @as(u32, color.a);
            const oma = 255 - af;
            const r = (color.r * af + bg_r * oma) / 255;
            const g = (color.g * af + bg_g * oma) / 255;
            const b = (color.b * af + bg_b * oma) / 255;
            self.pixels[idx] = (r << 16) | (g << 8) | b;
        }
    }

    // ── Rounded rect ──────────────────────────────────────────────────────────

    pub fn fillRoundRect(self: *Renderer, rect: Rect, radius: u32, color: Color) void {
        const r: i32 = @intCast(@min(radius, @min(rect.width, rect.height) / 2));
        const x0 = @max(0, rect.x);
        const y0 = @max(0, rect.y);
        const x1 = @min(@as(i32, @intCast(self.width)),  rect.right());
        const y1 = @min(@as(i32, @intCast(self.height)), rect.bottom());
        if (x0 >= x1 or y0 >= y1) return;
        var py = y0;
        while (py < y1) : (py += 1) {
            var px = x0;
            while (px < x1) : (px += 1) {
                const in_left  = px < rect.x + r;
                const in_right = px >= rect.right() - r;
                const in_top   = py < rect.y + r;
                const in_bot   = py >= rect.bottom() - r;
                if ((in_left or in_right) and (in_top or in_bot)) {
                    const cx: i32 = if (in_left) rect.x + r else rect.right() - r;
                    const cy: i32 = if (in_top)  rect.y + r else rect.bottom() - r;
                    const dx = px - cx; const dy = py - cy;
                    if (dx * dx + dy * dy > r * r) continue;
                }
                self.blendPixel(@intCast(px), @intCast(py), color);
            }
        }
    }

    // ── Resize ────────────────────────────────────────────────────────────────

    pub fn resize(self: *Renderer, pixels: [*]u32, w: u32, h: u32) void {
        self.pixels = pixels;
        self.width  = w;
        self.height = h;
    }

    // ── Bitmap font fallback ──────────────────────────────────────────────────

    fn drawBitmapText(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color) void {
        const v = toPixel(color);
        for (text, 0..) |ch, ci| {
            const gx: i32 = x + @as(i32, @intCast(ci)) * @as(i32, bfont.GLYPH_W);
            const g = bfont.glyph(ch);
            for (g, 0..) |row_bits, ry| {
                var bit: u3 = 7;
                while (true) {
                    if (row_bits & (@as(u8, 1) << bit) != 0) {
                        const fpx = gx + @as(i32, 7 - bit);
                        const fpy = y + @as(i32, @intCast(ry));
                        if (fpx >= 0 and fpx < @as(i32, @intCast(self.width)) and
                            fpy >= 0 and fpy < @as(i32, @intCast(self.height)))
                            self.pixels[@as(u32, @intCast(fpy)) * self.width + @as(u32, @intCast(fpx))] = v;
                    }
                    if (bit == 0) break;
                    bit -= 1;
                }
            }
        }
    }

    fn drawBitmapTextScaled(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color, scale: u32) void {
        const v = toPixel(color);
        const s: i32 = @intCast(scale);
        for (text, 0..) |ch, ci| {
            const gx: i32 = x + @as(i32, @intCast(ci)) * @as(i32, bfont.GLYPH_W) * s;
            const g = bfont.glyph(ch);
            for (g, 0..) |row_bits, ry| {
                var bit: u3 = 7;
                while (true) {
                    if (row_bits & (@as(u8, 1) << bit) != 0) {
                        const bx: i32 = gx + @as(i32, @intCast(7 - @as(u32, bit))) * s;
                        const by: i32 = y + @as(i32, @intCast(ry)) * s;
                        var dy: i32 = 0;
                        while (dy < s) : (dy += 1) {
                            var dx: i32 = 0;
                            while (dx < s) : (dx += 1) {
                                const fpx = bx + dx; const fpy = by + dy;
                                if (fpx >= 0 and fpx < @as(i32, @intCast(self.width)) and
                                    fpy >= 0 and fpy < @as(i32, @intCast(self.height)))
                                    self.pixels[@as(u32, @intCast(fpy)) * self.width + @as(u32, @intCast(fpx))] = v;
                            }
                        }
                    }
                    if (bit == 0) break;
                    bit -= 1;
                }
            }
        }
    }

    fn toPixel(c: Color) u32 {
        return (@as(u32, c.r) << 16) | (@as(u32, c.g) << 8) | @as(u32, c.b);
    }
};
