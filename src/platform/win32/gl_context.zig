const std = @import("std");
const builtin = @import("builtin");

comptime {
    if (builtin.os.tag != .windows) @compileError("gl_context.zig is Windows-only");
}

// ── Win32 / WGL types ────────────────────────────────────────────────────────
const HWND    = *opaque {};
const HDC     = *opaque {};
const HGLRC   = *opaque {};
const HANDLE  = *anyopaque;
const BOOL    = i32;
const DWORD   = u32;
const WORD    = u16;
const UINT    = u32;
const INT     = i32;
const FLOAT   = f32;

const TRUE : BOOL = 1;
const FALSE: BOOL = 0;

const CC = std.builtin.CallingConvention.winapi;

const PIXELFORMATDESCRIPTOR = extern struct {
    nSize:           WORD  = @sizeOf(PIXELFORMATDESCRIPTOR),
    nVersion:        WORD  = 1,
    dwFlags:         DWORD = 0,
    iPixelType:      u8    = 0,
    cColorBits:      u8    = 0,
    cRedBits: u8=0, cRedShift: u8=0,
    cGreenBits: u8=0, cGreenShift: u8=0,
    cBlueBits: u8=0, cBlueShift: u8=0,
    cAlphaBits: u8=0, cAlphaShift: u8=0,
    cAccumBits: u8=0,
    cAccumRedBits: u8=0, cAccumGreenBits: u8=0, cAccumBlueBits: u8=0, cAccumAlphaBits: u8=0,
    cDepthBits:      u8    = 0,
    cStencilBits:    u8    = 0,
    cAuxBuffers:     u8    = 0,
    iLayerType:      u8    = 0,
    bReserved:       u8    = 0,
    dwLayerMask:     DWORD = 0,
    dwVisibleMask:   DWORD = 0,
    dwDamageMask:    DWORD = 0,
};

const PFD_DRAW_TO_WINDOW: DWORD = 0x00000004;
const PFD_SUPPORT_OPENGL: DWORD = 0x00000020;
const PFD_DOUBLEBUFFER:   DWORD = 0x00000001;
const PFD_TYPE_RGBA:      u8    = 0;

// WGL_ARB_create_context constants
const WGL_CONTEXT_MAJOR_VERSION_ARB: INT = 0x2091;
const WGL_CONTEXT_MINOR_VERSION_ARB: INT = 0x2092;
const WGL_CONTEXT_PROFILE_MASK_ARB:  INT = 0x9126;
const WGL_CONTEXT_CORE_PROFILE_BIT_ARB: INT = 0x00000001;

extern "user32"  fn GetDC(hwnd: HWND) callconv(CC) ?HDC;
extern "user32"  fn ReleaseDC(hwnd: HWND, hdc: HDC) callconv(CC) INT;
extern "gdi32"   fn ChoosePixelFormat(hdc: HDC, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(CC) INT;
extern "gdi32"   fn SetPixelFormat(hdc: HDC, format: INT, ppfd: *const PIXELFORMATDESCRIPTOR) callconv(CC) BOOL;
extern "gdi32"   fn SwapBuffers(hdc: HDC) callconv(CC) BOOL;
extern "opengl32" fn wglCreateContext(hdc: HDC) callconv(CC) ?HGLRC;
extern "opengl32" fn wglDeleteContext(hglrc: HGLRC) callconv(CC) BOOL;
extern "opengl32" fn wglMakeCurrent(hdc: ?HDC, hglrc: ?HGLRC) callconv(CC) BOOL;
extern "opengl32" fn wglGetProcAddress(proc: [*:0]const u8) callconv(CC) ?*anyopaque;

// ── GlContext ────────────────────────────────────────────────────────────────

pub const GlContext = struct {
    hwnd: HWND,
    dc:   HDC,
    rc:   HGLRC,

    pub fn create(hwnd: HWND) !GlContext {
        const dc = GetDC(hwnd) orelse return error.GetDCFailed;

        const pfd = PIXELFORMATDESCRIPTOR{
            .nSize      = @sizeOf(PIXELFORMATDESCRIPTOR),
            .nVersion   = 1,
            .dwFlags    = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
            .iPixelType = PFD_TYPE_RGBA,
            .cColorBits = 32,
            .cDepthBits = 24,
            .cStencilBits = 8,
        };
        const fmt = ChoosePixelFormat(dc, &pfd);
        if (fmt == 0) return error.ChoosePixelFormatFailed;
        if (SetPixelFormat(dc, fmt, &pfd) == FALSE) return error.SetPixelFormatFailed;

        // Bootstrap context (needed to load ARB extension for core profile)
        const bootstrap = wglCreateContext(dc) orelse return error.WglCreateContextFailed;
        if (wglMakeCurrent(dc, bootstrap) == FALSE) return error.WglMakeCurrentFailed;

        // Load wglCreateContextAttribsARB
        const createAttribs = wglGetProcAddress("wglCreateContextAttribsARB");

        var rc: HGLRC = bootstrap;
        if (createAttribs) |fn_ptr| {
            const wglCreateContextAttribsARB: *const fn (HDC, ?HGLRC, [*]const INT) callconv(CC) ?HGLRC =
                @ptrCast(@alignCast(fn_ptr));
            const attribs = [_]INT{
                WGL_CONTEXT_MAJOR_VERSION_ARB, 3,
                WGL_CONTEXT_MINOR_VERSION_ARB, 3,
                WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
                0,
            };
            if (wglCreateContextAttribsARB(dc, null, &attribs)) |core_rc| {
                _ = wglMakeCurrent(dc, core_rc);
                _ = wglDeleteContext(bootstrap);
                rc = core_rc;
            }
        }

        return .{ .hwnd = hwnd, .dc = dc, .rc = rc };
    }

    pub fn deinit(self: *GlContext) void {
        _ = wglMakeCurrent(null, null);
        _ = wglDeleteContext(self.rc);
        _ = ReleaseDC(self.hwnd, self.dc);
    }

    pub fn swapBuffers(self: *const GlContext) void {
        _ = SwapBuffers(self.dc);
    }

    pub fn getProcAddress(name: [*:0]const u8) ?*anyopaque {
        return wglGetProcAddress(name);
    }
};
