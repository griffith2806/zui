const std = @import("std");
const Color = @import("../../style/color.zig").Color;
const Rect  = @import("../../layout/geometry.zig").Rect;
const bfont = @import("font.zig");

// ── Win32 GDI (text rendering on the memory DC) ──────────────────────────────

const HDC    = *opaque {};
const HFONT  = *opaque {};
const HRGN   = *opaque {};
const DWORD  = u32;
const INT    = i32;
const BOOL   = i32;
const LONG   = i32;

const GdiSize  = extern struct { cx: LONG, cy: LONG };
const GdiRect  = extern struct { left: LONG, top: LONG, right: LONG, bottom: LONG };

const TRANSPARENT_BK:     INT  = 1;
const FW_NORMAL:          INT  = 400;
const FW_SEMIBOLD:        INT  = 600;
const DEFAULT_CHARSET:    DWORD = 1;
const OUT_DEFAULT_PRECIS: DWORD = 0;
const CLIP_DEFAULT_PRECIS:DWORD = 0;
const CLEARTYPE_QUALITY:  DWORD = 5;
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
/// Replaces the current clipping region with the intersection of the current
/// region and the specified rectangle. Returns NULLREGION/SIMPLEREGION/COMPLEXREGION or ERROR.
extern "gdi32" fn IntersectClipRect(hdc: HDC, left: INT, top: INT, right: INT, bottom: INT) callconv(std.builtin.CallingConvention.winapi) INT;
/// Selects a region as the current clipping region for the DC.
/// Pass null to remove the clipping region entirely.
extern "gdi32" fn SelectClipRgn(hdc: HDC, hrgn: ?HRGN) callconv(std.builtin.CallingConvention.winapi) INT;

// ── Font size table ───────────────────────────────────────────────────────────
// Indexed by `scale` (1..6).  Scale 0 is unused; scale 1 = body text.
// Pixel heights chosen so scale=1 maps to a comfortable 14px body size.
const FONT_PX = [7]INT{ 0, 14, 22, 32, 44, 60, 80 };
pub const NUM_FONT_SCALES = FONT_PX.len;

// Approximate line-height for layout purposes (scale=1 body text).
pub const LINE_H: u32 = 18;

// ── Text command queue ────────────────────────────────────────────────────────
// Text is NOT drawn to the DIB.  Instead each call to drawTextScale() queues
// a command here.  After BitBlt the caller passes the real screen DC to
// flushText(), which renders with ClearType on the actual display surface.

const MAX_TEXT_CMDS = 256;
const TEXT_WBUF_CAP = 8192; // UTF-16 code units across all commands in one frame

const TextCmd = struct {
    wbuf_start: u32,
    wbuf_len:   u32,
    x:     i32,
    y:     i32,
    color: Color,
    scale: u32,
    /// Active clip rect at queue time, in physical DC pixels.
    /// null means no clip was active — draw without restriction.
    clip:  ?GdiRect,
};

// ── Pixel format: Win32 DIB BGRA (0x00RRGGBB little-endian) ──────────────────

pub const Renderer = struct {
    pixels:    [*]u32,
    width:     u32,    // physical pixel width of the backing buffer
    height:    u32,    // physical pixel height
    dpi_scale: f32 = 1.0,
    // GDI state — null until initGdi() is called.  The memory DC is kept only
    // for font measurement (GetTextExtentPoint32W); text is drawn on the screen DC.
    gdi_dc:    ?HDC  = null,
    gdi_fonts: [NUM_FONT_SCALES]?HFONT = .{null} ** NUM_FONT_SCALES,
    // Deferred text queue
    text_cmds:      [MAX_TEXT_CMDS]TextCmd = undefined,
    text_cmd_count: usize = 0,
    text_wbuf:      [TEXT_WBUF_CAP]u16 = undefined,
    text_wbuf_pos:  usize = 0,
    // Active clip rect in LOGICAL pixels (null = no clipping).
    clip: ?Rect = null,

    pub fn init(pixels: [*]u32, width: u32, height: u32) Renderer {
        return .{ .pixels = pixels, .width = width, .height = height };
    }

    /// Call once after init, passing the memory DC and DPI scale factor.
    /// Fonts are created at physical pixel sizes so ClearType renders at native res.
    pub fn initGdi(self: *Renderer, dc: *anyopaque, dpi_scale: f32) void {
        self.dpi_scale = dpi_scale;
        self.gdi_dc = @ptrCast(dc);
        _ = SetBkMode(self.gdi_dc.?, TRANSPARENT_BK);
        _ = SetTextAlign(self.gdi_dc.?, TA_LEFT | TA_TOP);
        for (FONT_PX, 0..) |px, i| {
            if (px == 0) continue;
            // Scale font height to physical pixels for crisp ClearType rendering
            const phys_px: INT = @intFromFloat(@round(@as(f32, @floatFromInt(px)) * dpi_scale));
            const weight: INT = if (px >= 32) FW_SEMIBOLD else FW_NORMAL;
            self.gdi_fonts[i] = CreateFontW(
                -phys_px, 0, 0, 0, weight, 0, 0, 0,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                CLEARTYPE_QUALITY, FF_SWISS, SEGOE_UI,
            );
        }
    }

    // ── Clip rect ─────────────────────────────────────────────────────────────

    /// Set an active clip rectangle in logical pixels.  All subsequent draw
    /// calls are silently constrained to this region.  Pass null to disable.
    pub fn setClip(self: *Renderer, rect: ?Rect) void {
        self.clip = rect;
    }

    /// Remove the active clip rectangle (equivalent to setClip(null)).
    pub fn clearClip(self: *Renderer) void {
        self.clip = null;
    }

    // ── DPI helpers ───────────────────────────────────────────────────────────

    inline fn toPhysI(self: *const Renderer, v: i32) i32 {
        if (self.dpi_scale == 1.0) return v;
        return @intFromFloat(@round(@as(f32, @floatFromInt(v)) * self.dpi_scale));
    }
    inline fn toPhysU(self: *const Renderer, v: u32) u32 {
        if (self.dpi_scale == 1.0) return v;
        return @intFromFloat(@round(@as(f32, @floatFromInt(v)) * self.dpi_scale));
    }

    // ── Clip helpers ──────────────────────────────────────────────────────────

    /// Returns the effective logical rect after intersecting `rect` with the
    /// active clip.  Returns null when the result is empty (nothing to draw).
    inline fn clipLogical(self: *const Renderer, rect: Rect) ?Rect {
        const c = self.clip orelse return rect;
        return c.intersection(rect);
    }

    /// Returns a GdiRect (physical pixels) for the active clip rect, or null
    /// if no clip is active.  Used to restrict GDI TextOut calls.
    inline fn physClipGdi(self: *const Renderer) ?GdiRect {
        const c = self.clip orelse return null;
        return GdiRect{
            .left   = self.toPhysI(c.x),
            .top    = self.toPhysI(c.y),
            .right  = self.toPhysI(c.right()),
            .bottom = self.toPhysI(c.bottom()),
        };
    }

    pub fn deinit(self: *Renderer) void {
        for (&self.gdi_fonts) |*hf| {
            if (hf.*) |f| _ = DeleteObject(@ptrCast(f));
            hf.* = null;
        }
    }

    pub fn clear(self: *Renderer, color: Color) void {
        @memset(self.pixels[0 .. self.width * self.height], toPixel(color));
    }

    pub fn fillRect(self: *Renderer, rect: Rect, color: Color) void {
        // Apply logical clip before converting to physical pixels
        const clipped = self.clipLogical(rect) orelse return;
        // Convert logical → physical before drawing into the physical pixel buffer
        const x0: u32 = @intCast(@max(0, self.toPhysI(clipped.x)));
        const y0: u32 = @intCast(@max(0, self.toPhysI(clipped.y)));
        const x1: u32 = @intCast(@min(@as(i32, @intCast(self.width)),  self.toPhysI(clipped.right())));
        const y1: u32 = @intCast(@min(@as(i32, @intCast(self.height)), self.toPhysI(clipped.bottom())));
        if (x0 >= x1 or y0 >= y1) return;
        if (color.a == 255) {
            const v = toPixel(color);
            var y: u32 = y0;
            while (y < y1) : (y += 1) {
                @memset(self.pixels[y * self.width + x0 .. y * self.width + x1], v);
            }
        } else if (color.a > 0) {
            // Alpha-blend path — used for modal scrims and semi-transparent fills.
            const af: u32  = color.a;
            const oma: u32 = 255 - af;
            const pr: u32  = @as(u32, color.r) * af;
            const pg: u32  = @as(u32, color.g) * af;
            const pb: u32  = @as(u32, color.b) * af;
            var y: u32 = y0;
            while (y < y1) : (y += 1) {
                for (self.pixels[y * self.width + x0 .. y * self.width + x1]) |*px| {
                    const bg = px.*;
                    const r = (pr + ((bg >> 16) & 0xFF) * oma) / 255;
                    const g = (pg + ((bg >>  8) & 0xFF) * oma) / 255;
                    const b = (pb + ( bg         & 0xFF) * oma) / 255;
                    px.* = (r << 16) | (g << 8) | b;
                }
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
        if (self.gdi_dc != null) {
            // Quick rejection: if a clip is active and the text origin is clearly
            // below or to the right of the clip, skip this command.  We cannot
            // know the exact text width here without measuring, so we only reject
            // based on the y coordinate (using LINE_H as an approximation for
            // height) and keep commands that might be partially visible.
            if (self.clip) |c| {
                const font_h: i32 = @intCast(FONT_PX[@min(scale, NUM_FONT_SCALES - 1)] * 2); // generous upper bound
                if (y + font_h < c.y or y >= c.bottom()) return;
                if (x >= c.right()) return;
            }
            if (self.text_cmd_count >= MAX_TEXT_CMDS) return;
            var wbuf: [1024]u16 = undefined;
            const wlen = std.unicode.utf8ToUtf16Le(&wbuf, text) catch return;
            if (self.text_wbuf_pos + wlen > TEXT_WBUF_CAP) return;
            @memcpy(self.text_wbuf[self.text_wbuf_pos..][0..wlen], wbuf[0..wlen]);
            self.text_cmds[self.text_cmd_count] = .{
                .wbuf_start = @intCast(self.text_wbuf_pos),
                .wbuf_len   = @intCast(wlen),
                // Store physical coords so GDI places text at the correct pixel
                .x = self.toPhysI(x), .y = self.toPhysI(y),
                .color = color, .scale = scale,
                // Capture clip as physical GdiRect for flushText
                .clip = self.physClipGdi(),
            };
            self.text_cmd_count += 1;
            self.text_wbuf_pos  += wlen;
            return;
        }
        // Fallback: bitmap font (no GDI / non-Windows)
        if (scale <= 1) {
            self.drawBitmapText(text, x, y, color);
        } else {
            self.drawBitmapTextScaled(text, x, y, color, scale);
        }
    }

    /// Discard all queued text for this frame without rendering.
    /// Use before drawing a modal overlay so page text doesn't bleed through.
    pub fn clearTextQueue(self: *Renderer) void {
        self.text_cmd_count = 0;
        self.text_wbuf_pos  = 0;
    }

    /// Render all queued text commands to the screen DC with ClearType AA.
    /// Called by the window/app layer after BitBlt, before ReleaseDC.
    pub fn flushText(self: *Renderer, screen_dc_raw: *anyopaque) void {
        if (self.text_cmd_count == 0) return;
        const dc: HDC = @ptrCast(screen_dc_raw);
        _ = SetBkMode(dc, TRANSPARENT_BK);
        _ = SetTextAlign(dc, TA_LEFT | TA_TOP);
        for (self.text_cmds[0..self.text_cmd_count]) |cmd| {
            const idx = @min(cmd.scale, NUM_FONT_SCALES - 1);
            if (self.gdi_fonts[idx]) |hf| {
                _ = SelectObject(dc, @ptrCast(hf));
                const cr: DWORD = @as(DWORD, cmd.color.r) | (@as(DWORD, cmd.color.g) << 8) | (@as(DWORD, cmd.color.b) << 16);
                _ = SetTextColor(dc, cr);
                if (cmd.clip) |cl| {
                    // Apply clip: intersect the DC clipping region with our rect,
                    // draw the text, then reset the clip.
                    _ = IntersectClipRect(dc, cl.left, cl.top, cl.right, cl.bottom);
                    _ = TextOutW(dc, cmd.x, cmd.y, self.text_wbuf[cmd.wbuf_start..].ptr, @intCast(cmd.wbuf_len));
                    _ = SelectClipRgn(dc, null);
                } else {
                    _ = TextOutW(dc, cmd.x, cmd.y, self.text_wbuf[cmd.wbuf_start..].ptr, @intCast(cmd.wbuf_len));
                }
            }
        }
        self.text_cmd_count = 0;
        self.text_wbuf_pos  = 0;
    }

    /// Measure text width in pixels using GDI or bitmap fallback.
    /// Returns the text width in LOGICAL (device-independent) pixels.
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
                // Font was created at physical size → GDI returns physical width.
                // Divide back to logical so widgets can use it for layout.
                const phys: u32 = @intCast(@max(0, sz.cx));
                if (self.dpi_scale <= 1.0) return phys;
                return @intFromFloat(@ceil(@as(f32, @floatFromInt(phys)) / self.dpi_scale));
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
        // Apply logical clip before rasterizing
        const clipped = self.clipLogical(rect) orelse return;
        // Scale logical → physical before rasterizing
        const phys = Rect.init(
            self.toPhysI(clipped.x), self.toPhysI(clipped.y),
            self.toPhysU(clipped.width), self.toPhysU(clipped.height),
        );
        // Compute the physical clip bounds for the corner-arc test.
        // We need to know where the corners of the ORIGINAL rect are so the
        // arc math is correct, even if we're rendering a clipped sub-rect.
        const orig_phys = Rect.init(
            self.toPhysI(rect.x), self.toPhysI(rect.y),
            self.toPhysU(rect.width), self.toPhysU(rect.height),
        );
        self.fillRoundRectPhys(orig_phys, self.toPhysU(radius), phys, color);
    }

    /// Rasterize a rounded rect.
    /// `rect` defines the full shape (for corner arc math).
    /// `clip_phys` defines the physical pixel region to actually write into
    /// (already intersected with the frame buffer and any logical clip).
    fn fillRoundRectPhys(self: *Renderer, rect: Rect, radius: u32, clip_phys: Rect, color: Color) void {
        const r: i32 = @intCast(@min(radius, @min(rect.width, rect.height) / 2));
        const bx0: i32 = @max(@max(0, clip_phys.x), rect.x);
        const by0: i32 = @max(@max(0, clip_phys.y), rect.y);
        const bx1: i32 = @min(@min(@as(i32, @intCast(self.width)),  rect.right()),  clip_phys.right());
        const by1: i32 = @min(@min(@as(i32, @intCast(self.height)), rect.bottom()), clip_phys.bottom());
        if (bx0 >= bx1 or by0 >= by1) return;

        const v = toPixel(color);
        const solid = color.a == 255;

        var py: i32 = by0;
        while (py < by1) : (py += 1) {
            const in_top = py < rect.y + r;
            const in_bot = py >= rect.bottom() - r;

            if (!in_top and !in_bot) {
                // Interior row — full span, no corner test needed
                if (solid) {
                    const row: u32 = @as(u32, @intCast(py)) * self.width;
                    @memset(self.pixels[row + @as(u32, @intCast(bx0)) .. row + @as(u32, @intCast(bx1))], v);
                } else {
                    var px: i32 = bx0;
                    while (px < bx1) : (px += 1)
                        self.blendPixel(@intCast(px), @intCast(py), color);
                }
            } else {
                // Corner row — per-pixel test at left and right edges only
                const cy_ctr: i32 = if (in_top) rect.y + r else rect.bottom() - r;
                const dy = py - cy_ctr;
                // Left corner region
                var px: i32 = bx0;
                while (px < @min(bx1, rect.x + r)) : (px += 1) {
                    const cx_ctr: i32 = rect.x + r;
                    const dx = px - cx_ctr;
                    if (dx * dx + dy * dy > r * r) continue;
                    self.blendPixel(@intCast(px), @intCast(py), color);
                }
                // Middle span (between corners), no test needed
                const mid_start = @max(bx0, rect.x + r);
                const mid_end   = @min(bx1, rect.right() - r);
                if (mid_start < mid_end) {
                    if (solid) {
                        const row: u32 = @as(u32, @intCast(py)) * self.width;
                        @memset(self.pixels[row + @as(u32, @intCast(mid_start)) .. row + @as(u32, @intCast(mid_end))], v);
                    } else {
                        var px2: i32 = mid_start;
                        while (px2 < mid_end) : (px2 += 1)
                            self.blendPixel(@intCast(px2), @intCast(py), color);
                    }
                }
                // Right corner region
                px = @max(bx0, rect.right() - r);
                while (px < bx1) : (px += 1) {
                    const cx_ctr: i32 = rect.right() - r;
                    const dx = px - cx_ctr;
                    if (dx * dx + dy * dy > r * r) continue;
                    self.blendPixel(@intCast(px), @intCast(py), color);
                }
            }
        }
    }

    // ── Image blit ────────────────────────────────────────────────────────────

    /// Blit a raw pixel buffer to the frame. `pixels` contains `src_w * src_h`
    /// values in 0xAARRGGBB format (alpha in high byte). Clips to frame bounds
    /// and the active clip rect.
    pub fn drawImageRaw(self: *Renderer, pixels: [*]const u32, src_w: u32, src_h: u32, dst: Rect) void {
        // Apply logical clip first
        const dst_clipped = self.clipLogical(dst) orelse return;
        const dx0: i32 = @max(0, dst_clipped.x);
        const dy0: i32 = @max(0, dst_clipped.y);
        const dx1: i32 = @min(@as(i32, @intCast(self.width)),  dst_clipped.right());
        const dy1: i32 = @min(@as(i32, @intCast(self.height)), dst_clipped.bottom());
        if (dx0 >= dx1 or dy0 >= dy1) return;
        const ox: u32 = @intCast(dx0 - dst.x);
        const oy: u32 = @intCast(dy0 - dst.y);
        var sy: u32 = oy;
        var dy: u32 = @intCast(dy0);
        while (dy < @as(u32, @intCast(dy1))) : ({ dy += 1; sy += 1; }) {
            if (sy >= src_h) break;
            var sx: u32 = ox;
            var dx: u32 = @intCast(dx0);
            while (dx < @as(u32, @intCast(dx1))) : ({ dx += 1; sx += 1; }) {
                if (sx >= src_w) break;
                const px = pixels[sy * src_w + sx];
                const a: u8 = @truncate(px >> 24);
                if (a == 0) continue;
                if (a == 255) {
                    self.pixels[dy * self.width + dx] = px & 0x00FFFFFF;
                } else {
                    const bg  = self.pixels[dy * self.width + dx];
                    const af: u32 = a;
                    const oma: u32 = 255 - af;
                    const rr = (((px >> 16) & 0xFF) * af + ((bg >> 16) & 0xFF) * oma) / 255;
                    const gg = (((px >>  8) & 0xFF) * af + ((bg >>  8) & 0xFF) * oma) / 255;
                    const bb = ( (px        & 0xFF) * af + ( bg        & 0xFF) * oma) / 255;
                    self.pixels[dy * self.width + dx] = (rr << 16) | (gg << 8) | bb;
                }
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
        // Precompute clip bounds for the bitmap path (logical == physical when no GDI)
        const clip_x0: i32 = if (self.clip) |c| c.x else 0;
        const clip_y0: i32 = if (self.clip) |c| c.y else 0;
        const clip_x1: i32 = if (self.clip) |c| c.right() else @intCast(self.width);
        const clip_y1: i32 = if (self.clip) |c| c.bottom() else @intCast(self.height);
        for (text, 0..) |ch, ci| {
            const gx: i32 = x + @as(i32, @intCast(ci)) * @as(i32, bfont.GLYPH_W);
            const g = bfont.glyph(ch);
            for (g, 0..) |row_bits, ry| {
                var bit: u3 = 7;
                while (true) {
                    if (row_bits & (@as(u8, 1) << bit) != 0) {
                        const fpx = gx + @as(i32, 7 - bit);
                        const fpy = y + @as(i32, @intCast(ry));
                        if (fpx >= clip_x0 and fpx < clip_x1 and
                            fpy >= clip_y0 and fpy < clip_y1 and
                            fpx >= 0 and fpx < @as(i32, @intCast(self.width)) and
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
        const clip_x0: i32 = if (self.clip) |c| c.x else 0;
        const clip_y0: i32 = if (self.clip) |c| c.y else 0;
        const clip_x1: i32 = if (self.clip) |c| c.right() else @intCast(self.width);
        const clip_y1: i32 = if (self.clip) |c| c.bottom() else @intCast(self.height);
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
                                if (fpx >= clip_x0 and fpx < clip_x1 and
                                    fpy >= clip_y0 and fpy < clip_y1 and
                                    fpx >= 0 and fpx < @as(i32, @intCast(self.width)) and
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
