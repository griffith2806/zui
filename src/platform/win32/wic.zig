// Windows Imaging Component (WIC) bindings.
// Loads WindowsCodecs.dll at runtime via CoCreateInstance so there is no
// import-library dependency.  CoInitializeEx comes from ole32.dll which is
// always linked on Windows.
//
// Supports decoding any format WIC understands (PNG, JPEG, BMP, TIFF, …).
// The caller receives a pixel buffer in pre-multiplied BGRA layout
// (4 bytes per pixel, BGRA order), which loadFile() in image.zig converts
// to the 0xAARRGGBB u32 format used by the software renderer.

const std     = @import("std");
const builtin = @import("builtin");

comptime {
    if (builtin.os.tag != .windows) @compileError("wic.zig is Windows-only");
}

// ── Win32 primitive types ─────────────────────────────────────────────────────

const HRESULT = i32;
const ULONG   = u32;
const DWORD   = u32;
const UINT    = u32;
const BOOL    = i32;

const winapi = std.builtin.CallingConvention.winapi;

const S_OK:                          HRESULT = 0;
const S_FALSE:                       HRESULT = 1;
const COINIT_APARTMENTTHREADED:      DWORD   = 0x2;
const CLSCTX_INPROC_SERVER:          DWORD   = 0x1;
const GENERIC_READ:                  DWORD   = 0x80000000;
const WICDecodeMetadataCacheOnDemand: DWORD  = 0;
const WICBitmapDitherTypeNone:       DWORD   = 0;
const WICBitmapPaletteTypeCustom:    DWORD   = 0;

// S_FALSE == already initialized; RPC_E_CHANGED_MODE == different threading model
const RPC_E_CHANGED_MODE: HRESULT = @bitCast(@as(u32, 0x80010106));

// ── GUID ─────────────────────────────────────────────────────────────────────

const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

// {cacaf262-9370-4615-a13b-9f5539da4c0a}
const CLSID_WICImagingFactory = GUID{
    .Data1 = 0xcacaf262, .Data2 = 0x9370, .Data3 = 0x4615,
    .Data4 = .{ 0xa1, 0x3b, 0x9f, 0x55, 0x39, 0xda, 0x4c, 0x0a },
};

// {ec5ec8a9-c395-4314-9c77-54d7a935ff70}
const IID_IWICImagingFactory = GUID{
    .Data1 = 0xec5ec8a9, .Data2 = 0xc395, .Data3 = 0x4314,
    .Data4 = .{ 0x9c, 0x77, 0x54, 0xd7, 0xa9, 0x35, 0xff, 0x70 },
};

// {6fddc324-4e03-4bfe-b185-3d77768dc90f}  GUID_WICPixelFormat32bppPBGRA
const GUID_WICPixelFormat32bppPBGRA = GUID{
    .Data1 = 0x6fddc324, .Data2 = 0x4e03, .Data3 = 0x4bfe,
    .Data4 = .{ 0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x0f },
};

// ── COM vtable structs ────────────────────────────────────────────────────────

// IWICBitmapSource — base interface for frame decode and format converter
const IWICBitmapSourceVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    GetSize:        *const fn (*anyopaque, *UINT, *UINT) callconv(winapi) HRESULT,
    GetPixelFormat: *const fn (*anyopaque, *GUID) callconv(winapi) HRESULT,
    GetResolution:  *const fn (*anyopaque, *f64, *f64) callconv(winapi) HRESULT,
    CopyPalette:    *const fn (*anyopaque, ?*anyopaque) callconv(winapi) HRESULT,
    CopyPixels:     *const fn (*anyopaque, ?*anyopaque, UINT, UINT, [*]u8) callconv(winapi) HRESULT,
};

// IWICBitmapDecoder
const IWICBitmapDecoderVtbl = extern struct {
    QueryInterface:              *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:                      *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:                     *const fn (*anyopaque) callconv(winapi) ULONG,
    QueryCapability:             *const fn (*anyopaque, ?*anyopaque, *DWORD) callconv(winapi) HRESULT,
    Initialize:                  *const fn (*anyopaque, ?*anyopaque, DWORD) callconv(winapi) HRESULT,
    GetContainerFormat:          *const fn (*anyopaque, *GUID) callconv(winapi) HRESULT,
    GetDecoderInfo:              *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CopyPalette:                 *const fn (*anyopaque, ?*anyopaque) callconv(winapi) HRESULT,
    GetMetadataQueryReader:      *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    GetPreview:                  *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    GetColorContexts:            *const fn (*anyopaque, UINT, ?*?*anyopaque, *UINT) callconv(winapi) HRESULT,
    GetThumbnail:                *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    GetFrameCount:               *const fn (*anyopaque, *UINT) callconv(winapi) HRESULT,
    GetFrame:                    *const fn (*anyopaque, UINT, *?*anyopaque) callconv(winapi) HRESULT,
};

// IWICFormatConverter — extends IWICBitmapSource
const IWICFormatConverterVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    // IWICBitmapSource
    GetSize:        *const fn (*anyopaque, *UINT, *UINT) callconv(winapi) HRESULT,
    GetPixelFormat: *const fn (*anyopaque, *GUID) callconv(winapi) HRESULT,
    GetResolution:  *const fn (*anyopaque, *f64, *f64) callconv(winapi) HRESULT,
    CopyPalette:    *const fn (*anyopaque, ?*anyopaque) callconv(winapi) HRESULT,
    CopyPixels:     *const fn (*anyopaque, ?*anyopaque, UINT, UINT, [*]u8) callconv(winapi) HRESULT,
    // IWICFormatConverter
    Initialize:     *const fn (
        *anyopaque,        // self
        ?*anyopaque,       // pISource (IWICBitmapSource*)
        *const GUID,       // dstFormat
        DWORD,             // dither
        ?*anyopaque,       // pIPalette (null = none)
        f64,               // alphaThresholdPercent
        DWORD,             // paletteTranslate
    ) callconv(winapi) HRESULT,
    CanConvert:     *const fn (*anyopaque, *const GUID, *const GUID, *BOOL) callconv(winapi) HRESULT,
};

// IWICImagingFactory
const IWICImagingFactoryVtbl = extern struct {
    // IUnknown
    QueryInterface:               *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:                       *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:                      *const fn (*anyopaque) callconv(winapi) ULONG,
    // IWICImagingFactory
    CreateDecoderFromFilename:    *const fn (
        *anyopaque,       // self
        [*:0]const u16,   // wzFilename (UTF-16LE NUL-terminated)
        ?*const GUID,     // pguidVendor (null = any)
        DWORD,            // dwDesiredAccess
        DWORD,            // metadataOptions
        *?*anyopaque,     // ppIDecoder
    ) callconv(winapi) HRESULT,
    CreateDecoderFromStream:      *const fn (*anyopaque, ?*anyopaque, ?*const GUID, DWORD, *?*anyopaque) callconv(winapi) HRESULT,
    CreateDecoderFromFileHandle:  *const fn (*anyopaque, usize, ?*const GUID, DWORD, *?*anyopaque) callconv(winapi) HRESULT,
    CreateComponentInfo:          *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    CreateDecoder:                *const fn (*anyopaque, *const GUID, ?*const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    CreateEncoder:                *const fn (*anyopaque, *const GUID, ?*const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    CreatePalette:                *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateFormatConverter:        *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateBitmapScaler:           *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateBitmapClipper:          *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateBitmapFlipRotator:      *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateStream:                 *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateColorContext:           *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateColorTransformer:       *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateBitmap:                 *const fn (*anyopaque, UINT, UINT, *const GUID, DWORD, *?*anyopaque) callconv(winapi) HRESULT,
    CreateBitmapFromSource:       *const fn (*anyopaque, ?*anyopaque, DWORD, *?*anyopaque) callconv(winapi) HRESULT,
    CreateBitmapFromSourceRect:   *const fn (*anyopaque, ?*anyopaque, UINT, UINT, UINT, UINT, *?*anyopaque) callconv(winapi) HRESULT,
    CreateBitmapFromMemory:       *const fn (*anyopaque, UINT, UINT, *const GUID, UINT, UINT, [*]u8, *?*anyopaque) callconv(winapi) HRESULT,
    CreateBitmapFromHBITMAP:      *const fn (*anyopaque, ?*anyopaque, ?*anyopaque, DWORD, *?*anyopaque) callconv(winapi) HRESULT,
    CreateBitmapFromHICON:        *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateComponentEnumerator:    *const fn (*anyopaque, DWORD, DWORD, *?*anyopaque) callconv(winapi) HRESULT,
    CreateFastMetadataEncoderFromDecoder: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateFastMetadataEncoderFromFrameDecode: *const fn (*anyopaque, ?*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateQueryWriter:            *const fn (*anyopaque, *const GUID, ?*const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    CreateQueryWriterFromReader:  *const fn (*anyopaque, ?*anyopaque, ?*const GUID, *?*anyopaque) callconv(winapi) HRESULT,
};

// COM "face" types — each is just a pointer to its vtable.
const IWICImagingFactoryFace  = extern struct { vtbl: *const IWICImagingFactoryVtbl };
const IWICBitmapDecoderFace   = extern struct { vtbl: *const IWICBitmapDecoderVtbl };
const IWICBitmapSourceFace    = extern struct { vtbl: *const IWICBitmapSourceVtbl };
const IWICFormatConverterFace = extern struct { vtbl: *const IWICFormatConverterVtbl };

// ── ole32 imports ─────────────────────────────────────────────────────────────

extern "ole32" fn CoInitializeEx(?*anyopaque, DWORD) callconv(winapi) HRESULT;
extern "ole32" fn CoCreateInstance(
    rclsid:       *const GUID,
    pUnkOuter:    ?*anyopaque,
    dwClsContext: DWORD,
    riid:         *const GUID,
    ppv:          *?*anyopaque,
) callconv(winapi) HRESULT;

// ── Error set ────────────────────────────────────────────────────────────────

pub const WicError = error{
    ComInitFailed,
    FactoryCreateFailed,
    DecoderCreateFailed,
    GetFrameFailed,
    FormatConverterCreateFailed,
    FormatConverterInitFailed,
    GetSizeFailed,
    CopyPixelsFailed,
    InvalidImageSize,
    PathTooLong,
    InvalidUtf8,
    OutOfMemory,
};

// ── Public function ───────────────────────────────────────────────────────────

/// Decode an image file (PNG, JPEG, BMP, TIFF, GIF, …) using WIC.
///
/// Returns a caller-owned slice of raw bytes in **pre-multiplied BGRA** order
/// (4 bytes per pixel: B, G, R, A).  The caller must `alloc.free()` the slice.
/// `width` and `height` are filled in on success.
pub fn loadFileAsBgra(
    alloc:  std.mem.Allocator,
    path:   []const u8,
    width:  *u32,
    height: *u32,
) WicError![]u8 {
    // ── Initialize COM (tolerates "already initialized") ────────────────────
    const hr_init = CoInitializeEx(null, COINIT_APARTMENTTHREADED);
    if (hr_init != S_OK and hr_init != S_FALSE and hr_init != RPC_E_CHANGED_MODE) {
        return error.ComInitFailed;
    }
    // We deliberately skip CoUninitialize — COM lifetime is the process's
    // responsibility, not a per-image-load concern.

    // ── 1. Create IWICImagingFactory ─────────────────────────────────────────
    var factory_ptr: ?*anyopaque = null;
    const hr_fac = CoCreateInstance(
        &CLSID_WICImagingFactory,
        null,
        CLSCTX_INPROC_SERVER,
        &IID_IWICImagingFactory,
        &factory_ptr,
    );
    if (hr_fac != S_OK or factory_ptr == null) return error.FactoryCreateFailed;
    const factory: *IWICImagingFactoryFace = @ptrCast(@alignCast(factory_ptr.?));
    defer _ = factory.vtbl.Release(@ptrCast(factory));

    // ── 2. UTF-8 → UTF-16LE NUL-terminated path ─────────────────────────────
    // Windows MAX_PATH is 260 but extended paths allow 32767; use the larger.
    var path_buf: [32768]u16 = undefined;
    const path_len = std.unicode.utf8ToUtf16Le(path_buf[0..32767], path) catch |e| switch (e) {
        error.InvalidUtf8 => return error.InvalidUtf8,
    };
    if (path_len >= path_buf.len) return error.PathTooLong;
    path_buf[path_len] = 0;
    const path_w: [*:0]const u16 = @ptrCast(&path_buf);

    // ── 3. Create decoder from file ──────────────────────────────────────────
    var decoder_ptr: ?*anyopaque = null;
    const hr_dec = factory.vtbl.CreateDecoderFromFilename(
        @ptrCast(factory),
        path_w,
        null,                          // any registered WIC vendor
        GENERIC_READ,
        WICDecodeMetadataCacheOnDemand,
        &decoder_ptr,
    );
    if (hr_dec != S_OK or decoder_ptr == null) return error.DecoderCreateFailed;
    const decoder: *IWICBitmapDecoderFace = @ptrCast(@alignCast(decoder_ptr.?));
    defer _ = decoder.vtbl.Release(@ptrCast(decoder));

    // ── 4. Get first frame ───────────────────────────────────────────────────
    var frame_ptr: ?*anyopaque = null;
    const hr_frm = decoder.vtbl.GetFrame(@ptrCast(decoder), 0, &frame_ptr);
    if (hr_frm != S_OK or frame_ptr == null) return error.GetFrameFailed;
    const frame: *IWICBitmapSourceFace = @ptrCast(@alignCast(frame_ptr.?));
    defer _ = frame.vtbl.Release(@ptrCast(frame));

    // ── 5. Create format converter ───────────────────────────────────────────
    var conv_ptr: ?*anyopaque = null;
    const hr_cv = factory.vtbl.CreateFormatConverter(@ptrCast(factory), &conv_ptr);
    if (hr_cv != S_OK or conv_ptr == null) return error.FormatConverterCreateFailed;
    const conv: *IWICFormatConverterFace = @ptrCast(@alignCast(conv_ptr.?));
    defer _ = conv.vtbl.Release(@ptrCast(conv));

    // ── 6. Initialize converter to 32bppPBGRA ────────────────────────────────
    const hr_ci = conv.vtbl.Initialize(
        @ptrCast(conv),
        frame_ptr,                         // source (IWICBitmapSource*)
        &GUID_WICPixelFormat32bppPBGRA,    // target pixel format
        WICBitmapDitherTypeNone,
        null,                              // no palette
        0.0,                               // alpha threshold
        WICBitmapPaletteTypeCustom,
    );
    if (hr_ci != S_OK) return error.FormatConverterInitFailed;

    // ── 7. Query pixel dimensions ────────────────────────────────────────────
    var w: UINT = 0;
    var h: UINT = 0;
    const hr_sz = conv.vtbl.GetSize(@ptrCast(conv), &w, &h);
    if (hr_sz != S_OK) return error.GetSizeFailed;
    if (w == 0 or h == 0) return error.InvalidImageSize;

    // ── 8. Copy pixels into caller-owned buffer ──────────────────────────────
    const stride: UINT = w * 4;
    const buf_size: UINT = stride * h;
    const buf = alloc.alloc(u8, @as(usize, buf_size)) catch return error.OutOfMemory;
    errdefer alloc.free(buf);

    const hr_cp = conv.vtbl.CopyPixels(
        @ptrCast(conv),
        null,        // null WICRect = copy entire image
        stride,
        buf_size,
        buf.ptr,
    );
    if (hr_cp != S_OK) return error.CopyPixelsFailed;

    width.*  = w;
    height.* = h;
    return buf;
}
