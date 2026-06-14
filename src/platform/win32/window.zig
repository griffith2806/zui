const std = @import("std");
const builtin = @import("builtin");
const event_mod = @import("../../events/event.zig");

comptime {
    if (builtin.os.tag != .windows) @compileError("win32 platform backend is Windows-only");
}

const Event = event_mod.Event;

// ── Win32 types ─────────────────────────────────────────────────────────────

const HWND      = *opaque {};
const HDC       = *opaque {};
const HINSTANCE = *opaque {};
const HBITMAP   = *opaque {};
const HBRUSH    = *opaque {};
const HCURSOR   = *opaque {};
const HICON     = *opaque {};
const HMENU     = *opaque {};
const HANDLE    = *anyopaque;

const BOOL     = i32;
const DWORD    = u32;
const WORD     = u16;
const UINT     = u32;
const INT      = i32;
const LONG     = i32;
const WPARAM   = usize;
const LPARAM   = isize;
const LRESULT  = isize;

const TRUE : BOOL = 1;
const FALSE: BOOL = 0;

const WNDPROC = *const fn (HWND, UINT, WPARAM, LPARAM) callconv(std.builtin.CallingConvention.winapi) LRESULT;

const POINT = extern struct { x: LONG, y: LONG };
const RECT  = extern struct { left: LONG, top: LONG, right: LONG, bottom: LONG };

const MSG = extern struct {
    hwnd:    ?HWND,
    message: UINT,
    wParam:  WPARAM,
    lParam:  LPARAM,
    time:    DWORD,
    pt:      POINT,
    lPrivate: DWORD,
};

const WNDCLASSEXW = extern struct {
    cbSize:        UINT,
    style:         UINT,
    lpfnWndProc:   WNDPROC,
    cbClsExtra:    INT,
    cbWndExtra:    INT,
    hInstance:     HINSTANCE,
    hIcon:         ?HICON,
    hCursor:       ?HCURSOR,
    hbrBackground: ?HBRUSH,
    lpszMenuName:  ?[*:0]const u16,
    lpszClassName: [*:0]const u16,
    hIconSm:       ?HICON,
};

const PAINTSTRUCT = extern struct {
    hdc:         HDC,
    fErase:      BOOL,
    rcPaint:     RECT,
    fRestore:    BOOL,
    fIncUpdate:  BOOL,
    rgbReserved: [32]u8,
};

const BITMAPINFOHEADER = extern struct {
    biSize:          DWORD,
    biWidth:         LONG,
    biHeight:        LONG,
    biPlanes:        WORD,
    biBitCount:      WORD,
    biCompression:   DWORD,
    biSizeImage:     DWORD,
    biXPelsPerMeter: LONG,
    biYPelsPerMeter: LONG,
    biClrUsed:       DWORD,
    biClrImportant:  DWORD,
};

const RGBQUAD = extern struct { rgbBlue: u8, rgbGreen: u8, rgbRed: u8, rgbReserved: u8 };

const BITMAPINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER,
    bmiColors: [1]RGBQUAD,
};

// ── Win32 constants ──────────────────────────────────────────────────────────

const CS_HREDRAW: UINT = 0x0002;
const CS_VREDRAW: UINT = 0x0001;
const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
const CW_USEDEFAULT: INT = @bitCast(@as(u32, 0x80000000));
const SW_SHOW: INT = 5;
const PM_REMOVE: UINT = 0x0001;
const GWLP_USERDATA: INT = -21;
const BI_RGB: DWORD = 0;
const DIB_RGB_COLORS: UINT = 0;
const SRCCOPY: DWORD = 0x00CC0020;
const WM_DESTROY: UINT     = 0x0002;
const WM_SIZE: UINT        = 0x0005;
const WM_CLOSE: UINT       = 0x0010;
const WM_PAINT: UINT       = 0x000F;
const WM_KEYDOWN: UINT     = 0x0100;
const WM_KEYUP: UINT       = 0x0101;
const WM_CHAR: UINT        = 0x0102;
const WM_MOUSEMOVE: UINT   = 0x0200;
const WM_LBUTTONDOWN: UINT = 0x0201;
const WM_LBUTTONUP: UINT   = 0x0202;
const WM_RBUTTONDOWN: UINT = 0x0204;
const WM_RBUTTONUP: UINT   = 0x0205;
const WM_MOUSEWHEEL: UINT  = 0x020A;

// Virtual keys for modifier detection
const VK_SHIFT:   INT = 0x10;
const VK_CONTROL: INT = 0x11;
const VK_MENU:    INT = 0x12;  // Alt

// ── DWM types and constants ───────────────────────────────────────────────────

const HRESULT = LONG;

const DWMWA_USE_IMMERSIVE_DARK_MODE:  DWORD = 20;
const DWMWA_WINDOW_CORNER_PREFERENCE: DWORD = 33;
const DWMWA_SYSTEMBACKDROP_TYPE:      DWORD = 38;
const DWMWCP_ROUND:       DWORD = 2;
const DWMSBT_MAINWINDOW:  DWORD = 2;

extern "dwmapi" fn DwmSetWindowAttribute(hwnd: HWND, dwAttr: DWORD, pv: *const anyopaque, cbAttr: DWORD) callconv(std.builtin.CallingConvention.winapi) HRESULT;

// ── Win32 function declarations ──────────────────────────────────────────────

extern "kernel32" fn GetModuleHandleW(name: ?[*:0]const u16) callconv(std.builtin.CallingConvention.winapi) ?HINSTANCE;

extern "user32" fn RegisterClassExW(wc: *const WNDCLASSEXW) callconv(std.builtin.CallingConvention.winapi) WORD;
extern "user32" fn CreateWindowExW(
    dwExStyle: DWORD, lpClassName: [*:0]const u16, lpWindowName: [*:0]const u16,
    dwStyle: DWORD, X: INT, Y: INT, nWidth: INT, nHeight: INT,
    hWndParent: ?HWND, hMenu: ?HMENU, hInstance: ?HINSTANCE, lpParam: ?*anyopaque,
) callconv(std.builtin.CallingConvention.winapi) ?HWND;
extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: INT) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "user32" fn UpdateWindow(hWnd: HWND) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "user32" fn DefWindowProcW(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(std.builtin.CallingConvention.winapi) LRESULT;
extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: ?HWND, wMsgFilterMin: UINT, wMsgFilterMax: UINT, wRemoveMsg: UINT) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(std.builtin.CallingConvention.winapi) LRESULT;
extern "user32" fn PostQuitMessage(nExitCode: INT) callconv(std.builtin.CallingConvention.winapi) void;
extern "user32" fn SetWindowLongPtrW(hWnd: HWND, nIndex: INT, dwNewLong: isize) callconv(std.builtin.CallingConvention.winapi) isize;
extern "user32" fn GetWindowLongPtrW(hWnd: HWND, nIndex: INT) callconv(std.builtin.CallingConvention.winapi) isize;
extern "user32" fn GetDC(hWnd: ?HWND) callconv(std.builtin.CallingConvention.winapi) ?HDC;
extern "user32" fn ReleaseDC(hWnd: ?HWND, hDC: HDC) callconv(std.builtin.CallingConvention.winapi) INT;
extern "user32" fn BeginPaint(hWnd: HWND, lpPaint: *PAINTSTRUCT) callconv(std.builtin.CallingConvention.winapi) ?HDC;
extern "user32" fn EndPaint(hWnd: HWND, lpPaint: *const PAINTSTRUCT) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "user32" fn AdjustWindowRect(lpRect: *RECT, dwStyle: DWORD, bMenu: BOOL) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "user32" fn LoadCursorW(hInstance: ?HINSTANCE, lpCursorName: [*:0]const u16) callconv(std.builtin.CallingConvention.winapi) ?HCURSOR;
const IDC_ARROW: [*:0]const u16 = @ptrFromInt(32512);

extern "user32" fn SetProcessDpiAwarenessContext(value: isize) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "user32" fn GetDpiForSystem() callconv(std.builtin.CallingConvention.winapi) UINT;
const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: isize = -4;

extern "gdi32" fn CreateCompatibleDC(hdc: ?HDC) callconv(std.builtin.CallingConvention.winapi) ?HDC;
extern "gdi32" fn CreateCompatibleBitmap(hdc: HDC, cx: INT, cy: INT) callconv(std.builtin.CallingConvention.winapi) ?HBITMAP;
extern "gdi32" fn DeleteDC(hdc: HDC) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "gdi32" fn CreateDIBSection(
    hdc: ?HDC, lpbmi: *const BITMAPINFO, usage: UINT,
    ppvBits: *?*anyopaque, hSection: ?HANDLE, offset: DWORD,
) callconv(std.builtin.CallingConvention.winapi) ?HBITMAP;
extern "gdi32" fn SelectObject(hdc: HDC, h: *anyopaque) callconv(std.builtin.CallingConvention.winapi) ?*anyopaque;
extern "gdi32" fn DeleteObject(ho: *anyopaque) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "user32" fn GetKeyState(nVirtKey: INT) callconv(std.builtin.CallingConvention.winapi) i16;

extern "gdi32" fn BitBlt(
    hdc: HDC, x: INT, y: INT, cx: INT, cy: INT,
    hdcSrc: HDC, x1: INT, y1: INT, rop: DWORD,
) callconv(std.builtin.CallingConvention.winapi) BOOL;

// ── Window ───────────────────────────────────────────────────────────────────

const CLASS_NAME = std.unicode.utf8ToUtf16LeStringLiteral("zui_wnd");
const MAX_EVENTS = 128;

pub const Window = struct {
    hwnd:    HWND,
    dc_mem:  HDC,
    bitmap:  HBITMAP,
    pixels:  [*]u32,
    // Composite off-screen DC: DIB is blitted here first, then text is rendered
    // on top with ClearType (screen-compatible DC), then one atomic blit to screen.
    dc_comp: HDC,
    bm_comp: HBITMAP,
    width:  u32,      // physical pixel width of the DIB / pixel buffer
    height: u32,      // physical pixel height
    dpi_scale: f32,   // e.g. 2.0 on a 200% DPI display
    should_close: bool = false,
    size_changed: bool = false,

    ev_buf:  [MAX_EVENTS]Event = undefined,
    ev_head: u32 = 0,
    ev_tail: u32 = 0,

    pub fn create(alloc: std.mem.Allocator, title: []const u8, width: u32, height: u32) !*Window {
        // Enable per-monitor DPI awareness so we render at native physical resolution.
        // Must be called before any window is created.
        _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

        const sys_dpi  = GetDpiForSystem();
        const dpi_scale: f32 = @as(f32, @floatFromInt(sys_dpi)) / 96.0;
        const phys_w: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(width))  * dpi_scale));
        const phys_h: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(height)) * dpi_scale));

        const hinstance = GetModuleHandleW(null) orelse return error.NoModuleHandle;

        const wc = WNDCLASSEXW{
            .cbSize        = @sizeOf(WNDCLASSEXW),
            .style         = CS_HREDRAW | CS_VREDRAW,
            .lpfnWndProc   = wndProc,
            .cbClsExtra    = 0,
            .cbWndExtra    = 0,
            .hInstance     = hinstance,
            .hIcon         = null,
            .hCursor       = LoadCursorW(null, IDC_ARROW),
            .hbrBackground = null,
            .lpszMenuName  = null,
            .lpszClassName = CLASS_NAME,
            .hIconSm       = null,
        };
        _ = RegisterClassExW(&wc);

        var title_buf: [256]u16 = undefined;
        const title_len = try std.unicode.utf8ToUtf16Le(title_buf[0 .. title_buf.len - 1], title);
        title_buf[title_len] = 0;

        // Create window sized to the PHYSICAL client area so the DIB maps 1:1 to screen.
        var wr = RECT{ .left = 0, .top = 0, .right = @intCast(phys_w), .bottom = @intCast(phys_h) };
        _ = AdjustWindowRect(&wr, WS_OVERLAPPEDWINDOW, FALSE);

        const hwnd = CreateWindowExW(
            0, CLASS_NAME, title_buf[0..title_len :0],
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT, CW_USEDEFAULT,
            wr.right - wr.left, wr.bottom - wr.top,
            null, null, hinstance, null,
        ) orelse return error.CreateWindowFailed;

        const dc_src = GetDC(hwnd) orelse return error.GetDCFailed;
        const dc_mem  = CreateCompatibleDC(dc_src) orelse return error.CreateDCFailed;
        const dc_comp = CreateCompatibleDC(dc_src) orelse return error.CreateDCFailed;
        const bm_comp = CreateCompatibleBitmap(dc_src, @intCast(phys_w), @intCast(phys_h))
            orelse return error.CreateDIBFailed;
        _ = SelectObject(dc_comp, bm_comp);
        _ = ReleaseDC(hwnd, dc_src);

        const bmi = BITMAPINFO{
            .bmiHeader = .{
                .biSize          = @sizeOf(BITMAPINFOHEADER),
                .biWidth         = @intCast(phys_w),
                .biHeight        = -@as(LONG, @intCast(phys_h)), // top-down
                .biPlanes        = 1,
                .biBitCount      = 32,
                .biCompression   = BI_RGB,
                .biSizeImage     = 0,
                .biXPelsPerMeter = 0,
                .biYPelsPerMeter = 0,
                .biClrUsed       = 0,
                .biClrImportant  = 0,
            },
            .bmiColors = .{.{ .rgbBlue = 0, .rgbGreen = 0, .rgbRed = 0, .rgbReserved = 0 }},
        };

        var raw_bits: ?*anyopaque = null;
        const bitmap = CreateDIBSection(dc_mem, &bmi, DIB_RGB_COLORS, &raw_bits, null, 0)
            orelse return error.CreateDIBFailed;
        _ = SelectObject(dc_mem, bitmap);

        const win = try alloc.create(Window);
        win.* = .{
            .hwnd      = hwnd,
            .dc_mem    = dc_mem,
            .bitmap    = bitmap,
            .pixels    = @ptrCast(@alignCast(raw_bits.?)),
            .dc_comp   = dc_comp,
            .bm_comp   = bm_comp,
            .width     = phys_w,
            .height    = phys_h,
            .dpi_scale = dpi_scale,
        };
        _ = SetWindowLongPtrW(hwnd, GWLP_USERDATA, @bitCast(@intFromPtr(win)));
        _ = ShowWindow(hwnd, SW_SHOW);
        _ = UpdateWindow(hwnd);

        // Windows 11 Fluent Design: dark title bar, Mica backdrop, rounded corners.
        // Do NOT call DwmExtendFrameIntoClientArea — that creates a visible frosted
        // glass strip. Instead keep the system title bar dark and let our painted
        // client area sit flush below it, matching the MS Store / WPF UI style.
        const dark: DWORD = 1;
        _ = DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, @as(*const anyopaque, @ptrCast(&dark)), @sizeOf(DWORD));
        const backdrop: DWORD = DWMSBT_MAINWINDOW;
        _ = DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, @as(*const anyopaque, @ptrCast(&backdrop)), @sizeOf(DWORD));
        const corners: DWORD = DWMWCP_ROUND;
        _ = DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, @as(*const anyopaque, @ptrCast(&corners)), @sizeOf(DWORD));

        return win;
    }

    pub fn resizeDIB(self: *Window, new_w: u32, new_h: u32) void {
        const bmi = BITMAPINFO{
            .bmiHeader = .{
                .biSize          = @sizeOf(BITMAPINFOHEADER),
                .biWidth         = @intCast(new_w),
                .biHeight        = -@as(LONG, @intCast(new_h)),
                .biPlanes        = 1,
                .biBitCount      = 32,
                .biCompression   = BI_RGB,
                .biSizeImage     = 0,
                .biXPelsPerMeter = 0,
                .biYPelsPerMeter = 0,
                .biClrUsed       = 0,
                .biClrImportant  = 0,
            },
            .bmiColors = .{.{ .rgbBlue = 0, .rgbGreen = 0, .rgbRed = 0, .rgbReserved = 0 }},
        };
        var raw_bits: ?*anyopaque = null;
        const new_bmp = CreateDIBSection(self.dc_mem, &bmi, DIB_RGB_COLORS, &raw_bits, null, 0) orelse return;
        _ = SelectObject(self.dc_mem, new_bmp);
        _ = DeleteObject(self.bitmap);
        self.bitmap = new_bmp;
        self.pixels = @ptrCast(@alignCast(raw_bits.?));

        // Resize composite bitmap to match
        const dc_screen = GetDC(self.hwnd) orelse return;
        const new_bm_comp = CreateCompatibleBitmap(dc_screen, @intCast(new_w), @intCast(new_h)) orelse {
            _ = ReleaseDC(self.hwnd, dc_screen);
            return;
        };
        _ = ReleaseDC(self.hwnd, dc_screen);
        _ = SelectObject(self.dc_comp, new_bm_comp);
        _ = DeleteObject(self.bm_comp);
        self.bm_comp = new_bm_comp;

        self.width  = new_w;
        self.height = new_h;
        self.size_changed = true;
    }

    pub fn deinit(self: *Window, alloc: std.mem.Allocator) void {
        _ = DeleteObject(self.bitmap);
        _ = DeleteDC(self.dc_mem);
        _ = DeleteObject(self.bm_comp);
        _ = DeleteDC(self.dc_comp);
        _ = DestroyWindow(self.hwnd);
        alloc.destroy(self);
    }

    pub fn pollEvent(self: *Window) ?Event {
        if (self.ev_head != self.ev_tail) return self.popEvent();
        var msg: MSG = undefined;
        while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE) != FALSE) {
            _ = TranslateMessage(&msg);
            _ = DispatchMessageW(&msg);
            if (self.ev_head != self.ev_tail) return self.popEvent();
        }
        return null;
    }

    /// Copy DIB → composite DC and return the composite DC for text rendering.
    /// Text is drawn on the composite (screen-compatible) DC to get ClearType AA.
    /// After text is drawn, call releasePresent() to blit everything to screen.
    pub fn present(self: *Window) ?*anyopaque {
        _ = BitBlt(self.dc_comp, 0, 0, @intCast(self.width), @intCast(self.height), self.dc_mem, 0, 0, SRCCOPY);
        return @ptrCast(self.dc_comp);
    }

    /// Blit the completed composite frame (shapes + text) to the screen in one shot.
    pub fn releasePresent(self: *Window, _: *anyopaque) void {
        const dc = GetDC(self.hwnd) orelse return;
        _ = BitBlt(dc, 0, 0, @intCast(self.width), @intCast(self.height), self.dc_comp, 0, 0, SRCCOPY);
        _ = ReleaseDC(self.hwnd, dc);
    }

    fn popEvent(self: *Window) Event {
        const ev = self.ev_buf[self.ev_head & (MAX_EVENTS - 1)];
        self.ev_head +%= 1;
        return ev;
    }

    fn pushEvent(self: *Window, ev: Event) void {
        const next = (self.ev_tail +% 1) & (MAX_EVENTS - 1);
        if (next == self.ev_head & (MAX_EVENTS - 1)) return; // drop if full
        self.ev_buf[self.ev_tail & (MAX_EVENTS - 1)] = ev;
        self.ev_tail +%= 1;
    }
};

fn wndProc(hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM) callconv(std.builtin.CallingConvention.winapi) LRESULT {
    const raw = GetWindowLongPtrW(hwnd, GWLP_USERDATA);
    const win: ?*Window = if (raw != 0) @ptrFromInt(@as(usize, @bitCast(raw))) else null;

    switch (msg) {
        WM_CLOSE => {
            if (win) |w| { w.should_close = true; w.pushEvent(.close); }
            return 0;
        },
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        WM_SIZE => {
            if (win) |w| {
                const ulp: usize = @bitCast(lp);
                const nw: u32 = @truncate(ulp & 0xFFFF);  // physical
                const nh: u32 = @truncate((ulp >> 16) & 0xFFFF);
                if (nw > 0 and nh > 0 and (nw != w.width or nh != w.height)) {
                    w.resizeDIB(nw, nh);
                }
                // Emit logical (device-independent) dimensions
                const lw: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(nw)) / w.dpi_scale));
                const lh: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(nh)) / w.dpi_scale));
                w.pushEvent(.{ .resize = .{ .width = lw, .height = lh } });
            }
        },
        WM_PAINT => {
            if (win) |w| {
                var ps: PAINTSTRUCT = undefined;
                const dc = BeginPaint(hwnd, &ps) orelse return 0;
                _ = BitBlt(dc, 0, 0, @intCast(w.width), @intCast(w.height), w.dc_comp, 0, 0, SRCCOPY);
                _ = EndPaint(hwnd, &ps);
            }
            return 0;
        },
        WM_MOUSEMOVE => {
            if (win) |w| {
                const x: i32 = @as(i16, @truncate(lp));
                const y: i32 = @as(i16, @truncate(lp >> 16));
                w.pushEvent(.{ .mouse_move = .{
                    .x = physToLog(x, w.dpi_scale), .y = physToLog(y, w.dpi_scale),
                    .dx = 0, .dy = 0,
                } });
            }
        },
        WM_LBUTTONDOWN => mouseBtn(win, lp, .left, true),
        WM_LBUTTONUP   => mouseBtn(win, lp, .left, false),
        WM_RBUTTONDOWN => mouseBtn(win, lp, .right, true),
        WM_RBUTTONUP   => mouseBtn(win, lp, .right, false),
        WM_KEYDOWN => {
            if (win) |w| w.pushEvent(.{ .key_press = .{
                .key       = vkToKey(@intCast(wp)),
                .repeat    = (lp & (1 << 30)) != 0,
                .modifiers = currentModifiers(),
            }});
        },
        WM_KEYUP => {
            if (win) |w| w.pushEvent(.{ .key_release = .{
                .key       = vkToKey(@intCast(wp)),
                .modifiers = currentModifiers(),
            }});
        },
        WM_CHAR => {
            if (win) |w| {
                const cp: u21 = @truncate(wp);
                if (cp >= 0x20 and cp != 0x7F) w.pushEvent(.{ .char_input = cp });
            }
        },
        else => {},
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

fn mouseBtn(win: ?*Window, lp: LPARAM, btn: event_mod.MouseButton, press: bool) void {
    if (win) |w| {
        const px: i32 = @as(i16, @truncate(lp));
        const py: i32 = @as(i16, @truncate(lp >> 16));
        const x = physToLog(px, w.dpi_scale);
        const y = physToLog(py, w.dpi_scale);
        const ev = if (press)
            Event{ .mouse_press = .{ .x = x, .y = y, .button = btn } }
        else
            Event{ .mouse_release = .{ .x = x, .y = y, .button = btn } };
        w.pushEvent(ev);
    }
}

inline fn physToLog(phys: i32, scale: f32) i32 {
    if (scale <= 1.0) return phys;
    return @intFromFloat(@round(@as(f32, @floatFromInt(phys)) / scale));
}

fn currentModifiers() event_mod.Modifiers {
    return .{
        .shift = (@as(u16, @bitCast(GetKeyState(VK_SHIFT)))   & 0x8000) != 0,
        .ctrl  = (@as(u16, @bitCast(GetKeyState(VK_CONTROL))) & 0x8000) != 0,
        .alt   = (@as(u16, @bitCast(GetKeyState(VK_MENU)))    & 0x8000) != 0,
    };
}

fn vkToKey(vk: u32) event_mod.KeyCode {
    return switch (vk) {
        0x41 => .a, 0x42 => .b, 0x43 => .c, 0x44 => .d, 0x45 => .e,
        0x46 => .f, 0x47 => .g, 0x48 => .h, 0x49 => .i, 0x4A => .j,
        0x4B => .k, 0x4C => .l, 0x4D => .m, 0x4E => .n, 0x4F => .o,
        0x50 => .p, 0x51 => .q, 0x52 => .r, 0x53 => .s, 0x54 => .t,
        0x55 => .u, 0x56 => .v, 0x57 => .w, 0x58 => .x, 0x59 => .y, 0x5A => .z,
        0x30 => .@"0", 0x31 => .@"1", 0x32 => .@"2", 0x33 => .@"3", 0x34 => .@"4",
        0x35 => .@"5", 0x36 => .@"6", 0x37 => .@"7", 0x38 => .@"8", 0x39 => .@"9",
        0x70 => .f1,  0x71 => .f2,  0x72 => .f3,  0x73 => .f4,
        0x74 => .f5,  0x75 => .f6,  0x76 => .f7,  0x77 => .f8,
        0x78 => .f9,  0x79 => .f10, 0x7A => .f11, 0x7B => .f12,
        0x26 => .up, 0x28 => .down, 0x25 => .left, 0x27 => .right,
        0x0D => .enter, 0x1B => .escape, 0x08 => .backspace,
        0x09 => .tab,   0x20 => .space,  0x2E => .delete,
        0x10 => .left_shift, 0x11 => .left_ctrl, 0x12 => .left_alt,
        0x5B => .left_super, 0x5C => .right_super,
        else => .unknown,
    };
}
