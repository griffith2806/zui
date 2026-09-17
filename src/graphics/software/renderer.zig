const std = @import("std");
const Color = @import("../../style/color.zig").Color;
const Rect  = @import("../../layout/geometry.zig").Rect;
const paint = @import("../../style/paint.zig");
const Corners = paint.Corners;
const GradientStop = paint.GradientStop;
const bfont = @import("font.zig");
const Image = @import("../image.zig").Image;

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
// Icon font. "Segoe MDL2 Assets" ships on Windows 10 (1709+) and 11 and carries
// the standard symbol glyphs (cog = U+E713). Drawn through the same GDI/ClearType
// path as text, so icons inherit crisp DPI-aware rendering for free.
const SEGOE_ICONS = std.unicode.utf8ToUtf16LeStringLiteral("Segoe MDL2 Assets");

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

// ── Arbitrary-size font cache ────────────────────────────────────────────────
// The fixed ladder above covers scale-based text. `drawTextSized` accepts an
// arbitrary logical pixel size + family, so HFONTs are created lazily and kept
// in a small fixed-size ring cache keyed by (rounded_size_px, family).
const FONT_CACHE_SLOTS = 16;
const FAMILY_MAX = 64;

const SizedFont = struct {
    size_px:    i32 = 0,
    family_len: u8  = 0,
    family:     [FAMILY_MAX]u8 = [_]u8{0} ** FAMILY_MAX,
    hfont:      ?HFONT = null,
};

/// Map an arbitrary logical pixel size onto the nearest fixed ladder rung (1..6).
fn nearestScaleForPx(size_px: f32) u32 {
    const r = @round(size_px / 14.0);
    if (!(r > 1.0)) return 1;
    if (r > 6.0) return 6;
    return @intFromFloat(r);
}

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
    /// true → render with the icon font (Segoe MDL2 Assets) instead of the UI font.
    is_icon: bool = false,
    /// Resolved font for arbitrary-size text (drawTextSized). When set it wins
    /// over the scale/icon font lookup in flushText. null for the ladder path.
    hfont: ?HFONT = null,
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
    gdi_icon_fonts: [NUM_FONT_SCALES]?HFONT = .{null} ** NUM_FONT_SCALES,
    // Lazily-created arbitrary-size fonts (see getSizedFont).
    sized_fonts: [FONT_CACHE_SLOTS]SizedFont = [_]SizedFont{.{}} ** FONT_CACHE_SLOTS,
    sized_next:  usize = 0,
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
            // Icon font at the same physical size, normal weight.
            self.gdi_icon_fonts[i] = CreateFontW(
                -phys_px, 0, 0, 0, FW_NORMAL, 0, 0, 0,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                CLEARTYPE_QUALITY, FF_SWISS, SEGOE_ICONS,
            );
        }
    }

    /// Resolve (creating on first use) an HFONT for an arbitrary logical pixel
    /// size + font family. Empty `family` means the default UI font. Returns null
    /// when no GDI DC is available or the family name is unusable.
    fn getSizedFont(self: *const Renderer, size_px: f32, family: []const u8) ?HFONT {
        if (self.gdi_dc == null) return null;
        const rounded: i32 = @intFromFloat(@round(size_px));
        if (rounded <= 0) return null;
        const fam: []const u8 = if (family.len == 0) "Segoe UI Variable" else family;
        if (fam.len == 0 or fam.len > FAMILY_MAX - 1) return null;
        const self_mut = @constCast(self);
        for (&self_mut.sized_fonts) |*sf| {
            if (sf.hfont != null and sf.size_px == rounded and
                std.mem.eql(u8, sf.family[0..sf.family_len], fam)) return sf.hfont;
        }
        var fambuf: [FAMILY_MAX]u16 = undefined;
        const n = std.unicode.utf8ToUtf16Le(&fambuf, fam) catch return null;
        if (n >= fambuf.len) return null;
        fambuf[n] = 0;
        // Font height is created in physical pixels for crisp ClearType; the
        // measurement path divides back to logical.
        const phys_px: INT = @intFromFloat(@round(@as(f32, @floatFromInt(rounded)) * self.dpi_scale));
        const hf = CreateFontW(
            -phys_px, 0, 0, 0, FW_NORMAL, 0, 0, 0,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, FF_SWISS, fambuf[0..n :0].ptr,
        );
        const slot = &self_mut.sized_fonts[self_mut.sized_next];
        if (slot.hfont) |old| _ = DeleteObject(@ptrCast(old));
        slot.size_px = rounded;
        slot.family_len = @intCast(fam.len);
        @memcpy(slot.family[0..fam.len], fam);
        slot.hfont = hf;
        self_mut.sized_next = (self_mut.sized_next + 1) % FONT_CACHE_SLOTS;
        return hf;
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
        for (&self.sized_fonts) |*sf| {
            if (sf.hfont) |f| _ = DeleteObject(@ptrCast(f));
            sf.hfont = null;
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

    /// Draw text at an arbitrary logical pixel size using `family` (empty family
    /// = the default UI font). Uses a lazily-created GDI font when available,
    /// otherwise falls back to the bitmap font at the nearest ladder scale.
    pub fn drawTextSized(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color, size_px: f32, family: []const u8) void {
        if (self.getSizedFont(size_px, family)) |hf| {
            self.queueSizedGlyphs(text, x, y, color, size_px, hf);
            return;
        }
        const scale = nearestScaleForPx(size_px);
        if (scale <= 1) {
            self.drawBitmapText(text, x, y, color);
        } else {
            self.drawBitmapTextScaled(text, x, y, color, scale);
        }
    }

    /// Draw an icon glyph from the icon font. `icon` is a UTF-8 string holding the
    /// codepoint (e.g. zui.icons.settings). `scale` matches the text scale table, so
    /// an icon lines up with same-scale text. Falls back to nothing without GDI.
    pub fn drawIcon(self: *Renderer, icon: []const u8, x: i32, y: i32, color: Color, scale: u32) void {
        self.queueGlyphs(icon, x, y, color, scale, true);
    }

    fn drawTextScale(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color, scale: u32) void {
        self.queueGlyphs(text, x, y, color, scale, false);
    }

    fn queueGlyphs(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color, scale: u32, is_icon: bool) void {
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
                .is_icon = is_icon,
                // Capture clip as physical GdiRect for flushText
                .clip = self.physClipGdi(),
            };
            self.text_cmd_count += 1;
            self.text_wbuf_pos  += wlen;
            return;
        }
        // Fallback: bitmap font (no GDI / non-Windows). Icons have no bitmap
        // representation, so skip them rather than drawing garbage.
        if (is_icon) return;
        if (scale <= 1) {
            self.drawBitmapText(text, x, y, color);
        } else {
            self.drawBitmapTextScaled(text, x, y, color, scale);
        }
    }

    /// Queue arbitrary-size text with a pre-resolved font.
    fn queueSizedGlyphs(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color, size_px: f32, hf: ?HFONT) void {
        const font_px: i32 = @intFromFloat(@round(size_px));
        if (self.clip) |c| {
            const font_h: i32 = font_px * 2; // generous upper bound
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
            .x = self.toPhysI(x), .y = self.toPhysI(y),
            .color = color, .scale = 1,
            .is_icon = false,
            .hfont = hf,
            .clip = self.physClipGdi(),
        };
        self.text_cmd_count += 1;
        self.text_wbuf_pos  += wlen;
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
            const font: ?HFONT = cmd.hfont orelse
                (if (cmd.is_icon) self.gdi_icon_fonts[idx] else self.gdi_fonts[idx]);
            if (font) |hf| {
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

    /// Measure text at an arbitrary logical pixel size + family, in LOGICAL
    /// pixels. Mirrors textWidthScaled's physical→logical conversion.
    pub fn textWidthSized(self: *const Renderer, text: []const u8, size_px: f32, family: []const u8) u32 {
        if (self.getSizedFont(size_px, family)) |hf| {
            const dc = self.gdi_dc.?;
            _ = SelectObject(@constCast(dc), @ptrCast(@constCast(hf)));
            var wbuf: [1024]u16 = undefined;
            const wlen = std.unicode.utf8ToUtf16Le(&wbuf, text) catch return 0;
            var sz: GdiSize = undefined;
            _ = GetTextExtentPoint32W(@constCast(dc), wbuf[0..wlen].ptr, @intCast(wlen), &sz);
            const phys: u32 = @intCast(@max(0, sz.cx));
            if (self.dpi_scale <= 1.0) return phys;
            return @intFromFloat(@ceil(@as(f32, @floatFromInt(phys)) / self.dpi_scale));
        }
        const sc: usize = nearestScaleForPx(size_px);
        return @intCast(text.len * bfont.GLYPH_W * sc);
    }

    /// Measure an icon glyph's width in LOGICAL pixels using the icon font.
    pub fn iconWidthScaled(self: *const Renderer, icon: []const u8, scale: u32) u32 {
        const idx = @min(scale, NUM_FONT_SCALES - 1);
        if (self.gdi_dc) |dc| {
            if (self.gdi_icon_fonts[idx]) |hf| {
                _ = SelectObject(@constCast(dc), @ptrCast(@constCast(hf)));
                var wbuf: [16]u16 = undefined;
                const wlen = std.unicode.utf8ToUtf16Le(&wbuf, icon) catch return 0;
                var sz: GdiSize = undefined;
                _ = GetTextExtentPoint32W(@constCast(dc), wbuf[0..wlen].ptr, @intCast(wlen), &sz);
                const phys: u32 = @intCast(@max(0, sz.cx));
                if (self.dpi_scale <= 1.0) return phys;
                return @intFromFloat(@ceil(@as(f32, @floatFromInt(phys)) / self.dpi_scale));
            }
        }
        return @as(u32, @intCast(FONT_PX[idx])) * scale;
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

    // ── Per-corner rounded rect + gradients (M23b) ────────────────────────────

    /// Fill a rectangle with independent per-corner radii. `Corners.smoothing`
    /// is currently ignored by the software rasterizer (circular arcs only).
    pub fn fillCorners(self: *Renderer, rect: Rect, corners: Corners, color: Color) void {
        const clipped = self.clipLogical(rect) orelse return;
        const phys = Rect.init(
            self.toPhysI(clipped.x), self.toPhysI(clipped.y),
            self.toPhysU(clipped.width), self.toPhysU(clipped.height),
        );
        const orig_phys = Rect.init(
            self.toPhysI(rect.x), self.toPhysI(rect.y),
            self.toPhysU(rect.width), self.toPhysU(rect.height),
        );
        const s = self.dpi_scale;
        const cp = Corners{
            .tl = corners.tl * s, .tr = corners.tr * s,
            .br = corners.br * s, .bl = corners.bl * s,
            .smoothing = corners.smoothing,
        };
        self.fillCornersPhys(orig_phys, cp, phys, color);
    }

    fn fillCornersPhys(self: *Renderer, rect: Rect, corners: Corners, clip_phys: Rect, color: Color) void {
        const w: i32 = @intCast(rect.width);
        const h: i32 = @intCast(rect.height);
        const maxr: i32 = @divTrunc(@min(w, h), 2);
        const tl = clampI(@intFromFloat(@round(corners.tl)), 0, maxr);
        const tr = clampI(@intFromFloat(@round(corners.tr)), 0, maxr);
        const br = clampI(@intFromFloat(@round(corners.br)), 0, maxr);
        const bl = clampI(@intFromFloat(@round(corners.bl)), 0, maxr);

        const bx0: i32 = @max(@max(0, clip_phys.x), rect.x);
        const by0: i32 = @max(@max(0, clip_phys.y), rect.y);
        const bx1: i32 = @min(@min(@as(i32, @intCast(self.width)), rect.right()), clip_phys.right());
        const by1: i32 = @min(@min(@as(i32, @intCast(self.height)), rect.bottom()), clip_phys.bottom());
        if (bx0 >= bx1 or by0 >= by1) return;

        var py: i32 = by0;
        while (py < by1) : (py += 1) {
            var left_start: i32 = rect.x;
            var right_end: i32 = rect.right();

            if (tl > 0 and py < rect.y + tl) {
                left_start = rect.x + tl - discDx(tl, py - (rect.y + tl));
            } else if (bl > 0 and py >= rect.bottom() - bl) {
                left_start = rect.x + bl - discDx(bl, py - (rect.bottom() - bl));
            }
            if (tr > 0 and py < rect.y + tr) {
                right_end = rect.right() - tr + discDx(tr, py - (rect.y + tr)) + 1;
            } else if (br > 0 and py >= rect.bottom() - br) {
                right_end = rect.right() - br + discDx(br, py - (rect.bottom() - br)) + 1;
            }

            const x0 = @max(bx0, left_start);
            const x1 = @min(bx1, right_end);
            if (x0 < x1) self.fillRowPhys(x0, x1, py, color);
        }
    }

    fn fillRowPhys(self: *Renderer, x0: i32, x1: i32, y: i32, color: Color) void {
        if (x0 >= x1) return;
        const row: u32 = @as(u32, @intCast(y)) * self.width;
        if (color.a == 255) {
            @memset(self.pixels[row + @as(u32, @intCast(x0)) .. row + @as(u32, @intCast(x1))], toPixel(color));
        } else if (color.a > 0) {
            var px = x0;
            while (px < x1) : (px += 1) self.blendPixel(@intCast(px), @intCast(y), color);
        }
    }

    /// Fill a rounded rect (per-corner radii) with a linear gradient.
    /// `angle_deg` 0 = left→right, 90 = top→bottom. Stops are sampled in order.
    pub fn fillLinearGradient(
        self: *Renderer,
        rect: Rect,
        corners: Corners,
        stops: []const GradientStop,
        angle_deg: f32,
    ) void {
        if (stops.len == 0) return;
        const clipped = self.clipLogical(rect) orelse return;
        const bx0: i32 = @max(0, clipped.x);
        const by0: i32 = @max(0, clipped.y);
        const bx1: i32 = @min(@as(i32, @intCast(self.width)), clipped.right());
        const by1: i32 = @min(@as(i32, @intCast(self.height)), clipped.bottom());
        if (bx0 >= bx1 or by0 >= by1) return;

        // Project onto the pixel-index span (0 .. extent-1) so the last row /
        // column reaches the final stop exactly instead of stopping short.
        const w: f32 = @floatFromInt(rect.width -| 1);
        const h: f32 = @floatFromInt(rect.height -| 1);
        const a = angle_deg * std.math.pi / 180.0;
        const dir_x = std.math.cos(a);
        const dir_y = std.math.sin(a);
        const p0: f32 = 0;
        const p1: f32 = w * dir_x;
        const p2: f32 = h * dir_y;
        const p3: f32 = w * dir_x + h * dir_y;
        const pmin = @min(@min(p0, p1), @min(p2, p3));
        const pmax = @max(@max(p0, p1), @max(p2, p3));
        const span = pmax - pmin;

        const has_corners = corners.tl != 0 or corners.tr != 0 or corners.br != 0 or corners.bl != 0;

        var py: i32 = by0;
        while (py < by1) : (py += 1) {
            var px: i32 = bx0;
            while (px < bx1) : (px += 1) {
                if (has_corners and !insideCorners(rect, corners, px, py)) continue;
                const rx: f32 = @floatFromInt(px - rect.x);
                const ry: f32 = @floatFromInt(py - rect.y);
                const proj = rx * dir_x + ry * dir_y;
                const t = if (span != 0) (proj - pmin) / span else 0.0;
                self.blendPixel(@intCast(px), @intCast(py), paint.sampleStops(stops, t));
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

    /// Draw a typed Image struct to the frame. Thin wrapper around drawImageRaw.
    pub fn drawImage(self: *Renderer, img: *const Image, dst: Rect) void {
        self.drawImageRaw(img.pixels.ptr, img.width, img.height, dst);
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

// ── Rounded-corner / gradient helpers ─────────────────────────────────────────

fn clampI(v: i32, lo: i32, hi: i32) i32 {
    return @min(@max(v, lo), hi);
}

/// Horizontal half-extent of a circle of radius `r` at vertical offset `dy`.
fn discDx(r: i32, dy: i32) i32 {
    const disc = r * r - dy * dy;
    if (disc <= 0) return 0;
    return @intFromFloat(@sqrt(@as(f32, @floatFromInt(disc))));
}

fn cornerRadius(rect: Rect, v: f32) i32 {
    const w: i32 = @intCast(rect.width);
    const h: i32 = @intCast(rect.height);
    const maxr: i32 = @divTrunc(@min(w, h), 2);
    return clampI(@intFromFloat(@round(v)), 0, maxr);
}

/// True when `(px, py)` lies inside the per-corner rounded rect.
fn insideCorners(rect: Rect, corners: Corners, px: i32, py: i32) bool {
    const tl = cornerRadius(rect, corners.tl);
    const tr = cornerRadius(rect, corners.tr);
    const br = cornerRadius(rect, corners.br);
    const bl = cornerRadius(rect, corners.bl);

    if (tl > 0 and px < rect.x + tl and py < rect.y + tl) {
        const dx = px - (rect.x + tl);
        const dy = py - (rect.y + tl);
        if (dx * dx + dy * dy > tl * tl) return false;
    }
    if (tr > 0 and px >= rect.right() - tr and py < rect.y + tr) {
        const dx = px - (rect.right() - tr);
        const dy = py - (rect.y + tr);
        if (dx * dx + dy * dy > tr * tr) return false;
    }
    if (br > 0 and px >= rect.right() - br and py >= rect.bottom() - br) {
        const dx = px - (rect.right() - br);
        const dy = py - (rect.bottom() - br);
        if (dx * dx + dy * dy > br * br) return false;
    }
    if (bl > 0 and px < rect.x + bl and py >= rect.bottom() - bl) {
        const dx = px - (rect.x + bl);
        const dy = py - (rect.bottom() - bl);
        if (dx * dx + dy * dy > bl * bl) return false;
    }
    return true;
}

/// Sample a sorted gradient stop list at normalized position `t` (0..1).
fn sampleGradient(stops: []const GradientStop, t_in: f32) Color {
    return paint.sampleStops(stops, t_in);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn testPixel(buf: []const u32, w: u32, x: u32, y: u32) u32 {
    return buf[y * w + x];
}

test "fillCorners: only top-left radius clips that corner" {
    const W = 10;
    const H = 10;
    var buf: [W * H]u32 = undefined;
    var r = Renderer.init(&buf, W, H);
    r.clear(Color.black);
    r.fillCorners(Rect.init(0, 0, W, H), .{ .tl = 5 }, Color.white);

    try testing.expectEqual(@as(u32, 0x000000), testPixel(&buf, W, 0, 0)); // outside arc
    try testing.expectEqual(@as(u32, 0x000000), testPixel(&buf, W, 4, 0)); // outside arc
    try testing.expectEqual(@as(u32, 0xFFFFFF), testPixel(&buf, W, 5, 0)); // on arc
    try testing.expectEqual(@as(u32, 0xFFFFFF), testPixel(&buf, W, 9, 0)); // no top-right radius
    try testing.expectEqual(@as(u32, 0xFFFFFF), testPixel(&buf, W, 0, 9)); // no bottom-left radius
    try testing.expectEqual(@as(u32, 0xFFFFFF), testPixel(&buf, W, 9, 9));
}

test "fillCorners uniform matches fillRoundRect" {
    const W = 24;
    const H = 24;
    var a: [W * H]u32 = undefined;
    var b: [W * H]u32 = undefined;
    var ra = Renderer.init(&a, W, H);
    var rb = Renderer.init(&b, W, H);
    ra.clear(Color.black);
    rb.clear(Color.black);
    ra.fillCorners(Rect.init(0, 0, W, H), Corners.uniform(6), Color.white);
    rb.fillRoundRect(Rect.init(0, 0, W, H), 6, Color.white);
    try testing.expectEqualSlices(u32, &a, &b);
}

test "fillCorners: zero radius fills whole rect" {
    const W = 4;
    const H = 4;
    var buf: [W * H]u32 = undefined;
    var r = Renderer.init(&buf, W, H);
    r.clear(Color.black);
    r.fillCorners(Rect.init(0, 0, W, H), Corners.uniform(0), Color.white);
    for (buf) |p| try testing.expectEqual(@as(u32, 0xFFFFFF), p);
}

test "fillCorners: alpha blends over background" {
    const W = 4;
    const H = 4;
    var buf: [W * H]u32 = undefined;
    var r = Renderer.init(&buf, W, H);
    r.clear(Color.black);
    r.fillCorners(Rect.init(0, 0, W, H), Corners.uniform(0), Color.rgba(255, 255, 255, 128));
    // ~50% white over black -> mid grey
    const p = testPixel(&buf, W, 1, 1);
    const rr: u32 = (p >> 16) & 0xFF;
    try testing.expect(rr > 120 and rr < 136);
}

test "fillLinearGradient: horizontal black to white" {
    const W = 256;
    const H = 1;
    var buf: [W * H]u32 = undefined;
    var r = Renderer.init(&buf, W, H);
    r.clear(Color.black);
    const stops = [_]GradientStop{
        .{ .position = 0.0, .color = Color.black },
        .{ .position = 1.0, .color = Color.white },
    };
    r.fillLinearGradient(Rect.init(0, 0, W, H), Corners.uniform(0), &stops, 0);

    try testing.expectEqual(@as(u32, 0x000000), testPixel(&buf, W, 0, 0));
    try testing.expectEqual(@as(u32, 0xFFFFFF), testPixel(&buf, W, 255, 0)); // clamped end
    const mid = (testPixel(&buf, W, 128, 0) >> 16) & 0xFF;
    try testing.expect(mid >= 126 and mid <= 129);
    // Monotonic increase
    var x: u32 = 1;
    while (x < W) : (x += 1) {
        const prev = (testPixel(&buf, W, x - 1, 0) >> 16) & 0xFF;
        const cur = (testPixel(&buf, W, x, 0) >> 16) & 0xFF;
        try testing.expect(cur >= prev);
    }
}

test "fillLinearGradient: vertical direction" {
    const W = 1;
    const H = 256;
    var buf: [W * H]u32 = undefined;
    var r = Renderer.init(&buf, W, H);
    r.clear(Color.black);
    const stops = [_]GradientStop{
        .{ .position = 0.0, .color = Color.black },
        .{ .position = 1.0, .color = Color.white },
    };
    r.fillLinearGradient(Rect.init(0, 0, W, H), Corners.uniform(0), &stops, 90);
    try testing.expectEqual(@as(u32, 0x000000), testPixel(&buf, W, 0, 0));
    try testing.expectEqual(@as(u32, 0xFFFFFF), testPixel(&buf, W, 0, 255));
}

test "sampleGradient: clamps outside stops" {
    const stops = [_]GradientStop{
        .{ .position = 0.25, .color = Color.red },
        .{ .position = 0.75, .color = Color.blue },
    };
    try testing.expectEqual(Color.red, sampleGradient(&stops, 0.0));
    try testing.expectEqual(Color.blue, sampleGradient(&stops, 1.0));
    try testing.expectEqual(Color.red, sampleGradient(&stops, 0.25));
}

test "insideCorners: corner exclusion" {
    const rect = Rect.init(0, 0, 10, 10);
    const c = Corners{ .tl = 5 };
    try testing.expectEqual(false, insideCorners(rect, c, 0, 0));
    try testing.expectEqual(true, insideCorners(rect, c, 5, 0));
    try testing.expectEqual(true, insideCorners(rect, c, 0, 9));
}

test "drawTextSized / textWidthSized bitmap fallback" {
    const W = 64;
    const H = 64;
    var buf: [W * H]u32 = undefined;
    var r = Renderer.init(&buf, W, H);
    r.clear(Color.black);
    // No GDI in tests → bitmap fallback path, both with default and named family.
    r.drawTextSized("Hi", 2, 2, Color.white, 16, "");
    r.drawTextSized("Hi", 2, 20, Color.white, 40, "Inter");
    try testing.expect(r.textWidthSized("Hi", 16, "") > 0);
    try testing.expect(r.textWidthSized("Hi", 40, "Inter") > 0);
    try testing.expect(r.textWidthSized("", 16, "") == 0);
    // Nearest-rung mapping: 16px → scale 1, 40px → scale 3.
    try testing.expectEqual(@as(u32, 2 * 8 * 1), r.textWidthSized("Hi", 16, ""));
    try testing.expectEqual(@as(u32, 2 * 8 * 3), r.textWidthSized("Hi", 40, ""));
}
