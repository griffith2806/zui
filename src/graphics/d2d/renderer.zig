// Direct2D + DirectWrite GPU-accelerated renderer backend.
//
// Uses ID2D1HwndRenderTarget for GPU-accelerated drawing directly to the HWND,
// and IDWriteFactory + IDWriteTextFormat for proper Unicode text shaping with
// Segoe UI Variable.
//
// Build with: zig build -Dbackend=d2d
// Links against d2d1.dll and dwrite.dll (both ship with Windows 8+).

const std     = @import("std");
const builtin = @import("builtin");
const Color   = @import("../../style/color.zig").Color;
const Rect    = @import("../../layout/geometry.zig").Rect;
const Image   = @import("../image.zig").Image;

comptime {
    if (builtin.os.tag != .windows) @compileError("d2d renderer is Windows-only");
}

// ── Win32 primitive types ─────────────────────────────────────────────────────

const HRESULT = i32;
const ULONG   = u32;
const UINT    = u32;
const UINT32  = u32;
const FLOAT   = f32;
const BOOL    = i32;
const HWND    = *opaque {};

const winapi = std.builtin.CallingConvention.winapi;

const S_OK: HRESULT = 0;

// ── GUID ─────────────────────────────────────────────────────────────────────

const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

// {06152247-6F50-465A-9245-118BFD3B6007}  IID_ID2D1Factory
const IID_ID2D1Factory = GUID{
    .Data1 = 0x06152247, .Data2 = 0x6F50, .Data3 = 0x465A,
    .Data4 = .{ 0x92, 0x45, 0x11, 0x8B, 0xFD, 0x3B, 0x60, 0x07 },
};

// {2CD90694-12E2-11DC-9FED-001143A055F9}  IID_ID2D1HwndRenderTarget
const IID_ID2D1HwndRenderTarget = GUID{
    .Data1 = 0x2CD90694, .Data2 = 0x12E2, .Data3 = 0x11DC,
    .Data4 = .{ 0x9F, 0xED, 0x00, 0x11, 0x43, 0xA0, 0x55, 0xF9 },
};

// {B859BB69-3142-11DB-92AF-0024E966F68A}  IID_IDWriteFactory
const IID_IDWriteFactory = GUID{
    .Data1 = 0xB859BB69, .Data2 = 0x3142, .Data3 = 0x11DB,
    .Data4 = .{ 0x92, 0xAF, 0x00, 0x24, 0xE9, 0x66, 0xF6, 0x8A },
};
// {30572F99-DAC6-41DB-A16E-0486307E606A}  IID_IDWriteFactory1
// On Windows 11 24H2, DWriteCreateFactory returns E_NOINTERFACE for the legacy
// IID_IDWriteFactory but succeeds for IID_IDWriteFactory1 (a superset interface).
// IDWriteFactory1 derives from IDWriteFactory, so the returned object exposes every
// IDWriteFactory method at the same vtbl slots — we request this and use it as an
// IDWriteFactory unchanged.
const IID_IDWriteFactory1 = GUID{
    .Data1 = 0x30572F99, .Data2 = 0xDAC6, .Data3 = 0x41DB,
    .Data4 = .{ 0xA1, 0x6E, 0x04, 0x86, 0x30, 0x7E, 0x60, 0x6A },
};

// ── D2D / DWrite constants ────────────────────────────────────────────────────

const D2D1_FACTORY_TYPE_SINGLE_THREADED: u32 = 0;
const DWRITE_FACTORY_TYPE_SHARED: u32 = 0;

const D2D1_ANTIALIAS_MODE_PER_PRIMITIVE: u32 = 0;
const D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE: u32 = 1;
const D2D1_ALPHA_MODE_PREMULTIPLIED: u32 = 1;
const D2D1_ALPHA_MODE_IGNORE: u32 = 3;
const D2D1_BITMAP_INTERPOLATION_MODE_LINEAR: u32 = 1;

// DXGI_FORMAT_B8G8R8A8_UNORM = 87
const DXGI_FORMAT_B8G8R8A8_UNORM: u32 = 87;

// DWRITE_FONT_WEIGHT_NORMAL = 400, SEMIBOLD = 600
const DWRITE_FONT_WEIGHT_NORMAL: u32 = 400;
const DWRITE_FONT_WEIGHT_SEMIBOLD: u32 = 600;
const DWRITE_FONT_STYLE_NORMAL: u32 = 0;
const DWRITE_FONT_STRETCH_NORMAL: u32 = 5;

// D2D1_DRAW_TEXT_OPTIONS_NONE = 0
const D2D1_DRAW_TEXT_OPTIONS_NONE: u32 = 0;
// DWRITE_MEASURING_MODE_NATURAL = 0
const DWRITE_MEASURING_MODE_NATURAL: u32 = 0;
// D2D1_COMPATIBLE_RENDER_TARGET_OPTIONS_NONE = 0

// ── D2D structs ───────────────────────────────────────────────────────────────

const D2D1_COLOR_F = extern struct {
    r: FLOAT,
    g: FLOAT,
    b: FLOAT,
    a: FLOAT,
};

const D2D1_POINT_2F = extern struct {
    x: FLOAT,
    y: FLOAT,
};

const D2D1_RECT_F = extern struct {
    left:   FLOAT,
    top:    FLOAT,
    right:  FLOAT,
    bottom: FLOAT,
};

const D2D1_ROUNDED_RECT = extern struct {
    rect:    D2D1_RECT_F,
    radiusX: FLOAT,
    radiusY: FLOAT,
};

const D2D1_SIZE_U = extern struct {
    width:  u32,
    height: u32,
};

const D2D1_SIZE_F = extern struct {
    width:  FLOAT,
    height: FLOAT,
};

const D2D1_PIXEL_FORMAT = extern struct {
    format:    u32,   // DXGI_FORMAT
    alphaMode: u32,   // D2D1_ALPHA_MODE
};

const D2D1_RENDER_TARGET_PROPERTIES = extern struct {
    type_:       u32,   // D2D1_RENDER_TARGET_TYPE (0 = default)
    pixelFormat: D2D1_PIXEL_FORMAT,
    dpiX:        FLOAT,
    dpiY:        FLOAT,
    usage:       u32,   // D2D1_RENDER_TARGET_USAGE (0 = none)
    minLevel:    u32,   // D2D1_FEATURE_LEVEL (0 = default)
};

const D2D1_HWND_RENDER_TARGET_PROPERTIES = extern struct {
    hwnd:            HWND,
    pixelSize:       D2D1_SIZE_U,
    presentOptions:  u32,   // D2D1_PRESENT_OPTIONS (0 = default)
};

const D2D1_BITMAP_PROPERTIES = extern struct {
    pixelFormat: D2D1_PIXEL_FORMAT,
    dpiX:        FLOAT,
    dpiY:        FLOAT,
};

const DWRITE_TEXT_METRICS = extern struct {
    left:                  FLOAT,
    top:                   FLOAT,
    width:                 FLOAT,
    widthIncludingTrailingWhitespace: FLOAT,
    height:                FLOAT,
    layoutWidth:           FLOAT,
    layoutHeight:          FLOAT,
    maxBidiReorderingDepth: u32,
    lineCount:             u32,
};

// ── COM vtable structs ────────────────────────────────────────────────────────
//
// Pattern from wic.zig / file_dialog.zig: face = extern struct { vtbl: *const VtblType }
// Method slots must be in strict COM vtable order.

// ID2D1Factory vtable (partial — only what we need)
const ID2D1FactoryVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    // ID2D1Factory
    ReloadSystemMetrics:   *const fn (*anyopaque) callconv(winapi) HRESULT,
    GetDesktopDpi:         *const fn (*anyopaque, *FLOAT, *FLOAT) callconv(winapi) void,
    CreateRectangleGeometry: *const fn (*anyopaque, *const D2D1_RECT_F, *?*anyopaque) callconv(winapi) HRESULT,
    CreateRoundedRectangleGeometry: *const fn (*anyopaque, *const D2D1_ROUNDED_RECT, *?*anyopaque) callconv(winapi) HRESULT,
    CreateEllipseGeometry: *const fn (*anyopaque, *const anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateGeometryGroup: *const fn (*anyopaque, u32, *?*anyopaque, u32, *?*anyopaque) callconv(winapi) HRESULT,
    CreateTransformedGeometry: *const fn (*anyopaque, *anyopaque, *const anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreatePathGeometry: *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateStrokeStyle: *const fn (*anyopaque, *const anyopaque, ?*const FLOAT, u32, *?*anyopaque) callconv(winapi) HRESULT,
    CreateDrawingStateBlock: *const fn (*anyopaque, ?*const anyopaque, ?*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateWicBitmapRenderTarget: *const fn (*anyopaque, *anyopaque, *const D2D1_RENDER_TARGET_PROPERTIES, *?*anyopaque) callconv(winapi) HRESULT,
    CreateHwndRenderTarget: *const fn (
        *anyopaque,                                   // self
        *const D2D1_RENDER_TARGET_PROPERTIES,          // renderTargetProperties
        *const D2D1_HWND_RENDER_TARGET_PROPERTIES,    // hwndRenderTargetProperties
        *?*anyopaque,                                  // hwndRenderTarget
    ) callconv(winapi) HRESULT,
};

// ID2D1RenderTarget vtable — ID2D1HwndRenderTarget inherits from this
// We define the full ID2D1HwndRenderTarget vtable including all parent methods.
const ID2D1HwndRenderTargetVtbl = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    // ID2D1Resource (3)
    GetFactory:     *const fn (*anyopaque, *?*anyopaque) callconv(winapi) void,
    // ID2D1RenderTarget (4-57)
    CreateBitmap:                   *const fn (*anyopaque, D2D1_SIZE_U, ?*const anyopaque, u32, *const D2D1_BITMAP_PROPERTIES, *?*anyopaque) callconv(winapi) HRESULT,
    CreateBitmapFromWicBitmap:      *const fn (*anyopaque, *anyopaque, ?*const D2D1_BITMAP_PROPERTIES, *?*anyopaque) callconv(winapi) HRESULT,
    CreateSharedBitmap:             *const fn (*anyopaque, *const GUID, *anyopaque, ?*const D2D1_BITMAP_PROPERTIES, *?*anyopaque) callconv(winapi) HRESULT,
    CreateBitmapBrush:              *const fn (*anyopaque, ?*anyopaque, ?*const anyopaque, ?*const anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateSolidColorBrush:          *const fn (*anyopaque, *const D2D1_COLOR_F, ?*const anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateGradientStopCollection:   *const fn (*anyopaque, *const anyopaque, u32, u32, u32, *?*anyopaque) callconv(winapi) HRESULT,
    CreateLinearGradientBrush:      *const fn (*anyopaque, *const anyopaque, ?*const anyopaque, *anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateRadialGradientBrush:      *const fn (*anyopaque, *const anyopaque, ?*const anyopaque, *anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateCompatibleRenderTarget:   *const fn (*anyopaque, ?*const D2D1_SIZE_F, ?*const D2D1_SIZE_U, ?*const D2D1_PIXEL_FORMAT, u32, *?*anyopaque) callconv(winapi) HRESULT,
    CreateLayer:                    *const fn (*anyopaque, ?*const D2D1_SIZE_F, *?*anyopaque) callconv(winapi) HRESULT,
    CreateMesh:                     *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    DrawLine:                       *const fn (*anyopaque, D2D1_POINT_2F, D2D1_POINT_2F, *anyopaque, FLOAT, ?*anyopaque) callconv(winapi) void,
    DrawRectangle:                  *const fn (*anyopaque, *const D2D1_RECT_F, *anyopaque, FLOAT, ?*anyopaque) callconv(winapi) void,
    FillRectangle:                  *const fn (*anyopaque, *const D2D1_RECT_F, *anyopaque) callconv(winapi) void,
    DrawRoundedRectangle:           *const fn (*anyopaque, *const D2D1_ROUNDED_RECT, *anyopaque, FLOAT, ?*anyopaque) callconv(winapi) void,
    FillRoundedRectangle:           *const fn (*anyopaque, *const D2D1_ROUNDED_RECT, *anyopaque) callconv(winapi) void,
    DrawEllipse:                    *const fn (*anyopaque, *const anyopaque, *anyopaque, FLOAT, ?*anyopaque) callconv(winapi) void,
    FillEllipse:                    *const fn (*anyopaque, *const anyopaque, *anyopaque) callconv(winapi) void,
    DrawGeometry:                   *const fn (*anyopaque, *anyopaque, *anyopaque, FLOAT, ?*anyopaque) callconv(winapi) void,
    FillGeometry:                   *const fn (*anyopaque, *anyopaque, *anyopaque, ?*anyopaque) callconv(winapi) void,
    FillMesh:                       *const fn (*anyopaque, *anyopaque, *anyopaque) callconv(winapi) void,
    FillOpacityMask:                *const fn (*anyopaque, *anyopaque, *anyopaque, u32, ?*const D2D1_RECT_F, ?*const D2D1_RECT_F) callconv(winapi) void,
    DrawBitmap:                     *const fn (*anyopaque, *anyopaque, ?*const D2D1_RECT_F, FLOAT, u32, ?*const D2D1_RECT_F) callconv(winapi) void,
    DrawText:                       *const fn (*anyopaque, [*]const u16, u32, *anyopaque, *const D2D1_RECT_F, *anyopaque, u32, u32) callconv(winapi) void,
    DrawTextLayout:                 *const fn (*anyopaque, D2D1_POINT_2F, *anyopaque, *anyopaque, u32) callconv(winapi) void,
    DrawGlyphRun:                   *const fn (*anyopaque, D2D1_POINT_2F, *const anyopaque, *anyopaque, u32) callconv(winapi) void,
    SetTransform:                   *const fn (*anyopaque, *const anyopaque) callconv(winapi) void,
    GetTransform:                   *const fn (*anyopaque, *anyopaque) callconv(winapi) void,
    SetAntialiasMode:               *const fn (*anyopaque, u32) callconv(winapi) void,
    GetAntialiasMode:               *const fn (*anyopaque) callconv(winapi) u32,
    SetTextAntialiasMode:           *const fn (*anyopaque, u32) callconv(winapi) void,
    GetTextAntialiasMode:           *const fn (*anyopaque) callconv(winapi) u32,
    SetTextRenderingParams:         *const fn (*anyopaque, ?*anyopaque) callconv(winapi) void,
    GetTextRenderingParams:         *const fn (*anyopaque, *?*anyopaque) callconv(winapi) void,
    SetTags:                        *const fn (*anyopaque, u64, u64) callconv(winapi) void,
    GetTags:                        *const fn (*anyopaque, ?*u64, ?*u64) callconv(winapi) void,
    PushLayer:                      *const fn (*anyopaque, *const anyopaque, ?*anyopaque) callconv(winapi) void,
    PopLayer:                       *const fn (*anyopaque) callconv(winapi) void,
    Flush:                          *const fn (*anyopaque, ?*u64, ?*u64) callconv(winapi) HRESULT,
    SaveDrawingState:               *const fn (*anyopaque, *anyopaque) callconv(winapi) void,
    RestoreDrawingState:            *const fn (*anyopaque, *anyopaque) callconv(winapi) void,
    PushAxisAlignedClip:            *const fn (*anyopaque, *const D2D1_RECT_F, u32) callconv(winapi) void,
    PopAxisAlignedClip:             *const fn (*anyopaque) callconv(winapi) void,
    Clear:                          *const fn (*anyopaque, ?*const D2D1_COLOR_F) callconv(winapi) void,
    BeginDraw:                      *const fn (*anyopaque) callconv(winapi) void,
    EndDraw:                        *const fn (*anyopaque, ?*u64, ?*u64) callconv(winapi) HRESULT,
    GetPixelFormat:                 *const fn (*anyopaque) callconv(winapi) D2D1_PIXEL_FORMAT,
    SetDpi:                         *const fn (*anyopaque, FLOAT, FLOAT) callconv(winapi) void,
    GetDpi:                         *const fn (*anyopaque, *FLOAT, *FLOAT) callconv(winapi) void,
    GetSize:                        *const fn (*anyopaque) callconv(winapi) D2D1_SIZE_F,
    GetPixelSize:                   *const fn (*anyopaque) callconv(winapi) D2D1_SIZE_U,
    GetMaximumBitmapSize:           *const fn (*anyopaque) callconv(winapi) u32,
    IsSupported:                    *const fn (*anyopaque, *const anyopaque) callconv(winapi) BOOL,
    // ID2D1HwndRenderTarget (58-59)
    CheckWindowState:               *const fn (*anyopaque) callconv(winapi) u32,
    Resize:                         *const fn (*anyopaque, *const D2D1_SIZE_U) callconv(winapi) HRESULT,
    GetHwnd:                        *const fn (*anyopaque) callconv(winapi) HWND,
};

// ID2D1SolidColorBrush vtable
const ID2D1SolidColorBrushVtbl = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    // ID2D1Resource (3)
    GetFactory:     *const fn (*anyopaque, *?*anyopaque) callconv(winapi) void,
    // ID2D1Brush (4-8)
    SetOpacity:     *const fn (*anyopaque, FLOAT) callconv(winapi) void,
    SetTransform:   *const fn (*anyopaque, *const anyopaque) callconv(winapi) void,
    GetOpacity:     *const fn (*anyopaque) callconv(winapi) FLOAT,
    GetTransform:   *const fn (*anyopaque, *anyopaque) callconv(winapi) void,
    // ID2D1SolidColorBrush (9-10)
    SetColor:       *const fn (*anyopaque, *const D2D1_COLOR_F) callconv(winapi) void,
    GetColor:       *const fn (*anyopaque) callconv(winapi) D2D1_COLOR_F,
};

// ID2D1Bitmap vtable (partial)
const ID2D1BitmapVtbl = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    // ID2D1Resource (3)
    GetFactory:     *const fn (*anyopaque, *?*anyopaque) callconv(winapi) void,
    // ID2D1Bitmap (4-7)
    GetSize:        *const fn (*anyopaque) callconv(winapi) D2D1_SIZE_F,
    GetPixelSize:   *const fn (*anyopaque) callconv(winapi) D2D1_SIZE_U,
    GetPixelFormat: *const fn (*anyopaque) callconv(winapi) D2D1_PIXEL_FORMAT,
    GetDpi:         *const fn (*anyopaque, *FLOAT, *FLOAT) callconv(winapi) void,
    CopyFromBitmap:     *const fn (*anyopaque, ?*const D2D1_POINT_2F, *anyopaque, ?*const D2D1_RECT_F) callconv(winapi) HRESULT,
    CopyFromRenderTarget: *const fn (*anyopaque, ?*const D2D1_POINT_2F, *anyopaque, ?*const D2D1_RECT_F) callconv(winapi) HRESULT,
    CopyFromMemory:     *const fn (*anyopaque, ?*const D2D1_RECT_F, *const anyopaque, u32) callconv(winapi) HRESULT,
};

// IDWriteFactory vtable (partial)
const IDWriteFactoryVtbl = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    // IDWriteFactory (3+)
    GetSystemFontCollection: *const fn (*anyopaque, *?*anyopaque, BOOL) callconv(winapi) HRESULT,
    CreateCustomFontCollection: *const fn (*anyopaque, *anyopaque, *const anyopaque, u32, *?*anyopaque) callconv(winapi) HRESULT,
    RegisterFontCollectionLoader: *const fn (*anyopaque, *anyopaque) callconv(winapi) HRESULT,
    UnregisterFontCollectionLoader: *const fn (*anyopaque, *anyopaque) callconv(winapi) HRESULT,
    CreateFontFileReference: *const fn (*anyopaque, [*:0]const u16, ?*const anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateCustomFontFileReference: *const fn (*anyopaque, *const anyopaque, u32, *anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateFontFace: *const fn (*anyopaque, u32, u32, *?*anyopaque, u32, BOOL, *?*anyopaque) callconv(winapi) HRESULT,
    CreateRenderingParams: *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateMonitorRenderingParams: *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateCustomRenderingParams: *const fn (*anyopaque, FLOAT, FLOAT, FLOAT, u32, u32, *?*anyopaque) callconv(winapi) HRESULT,
    RegisterFontFileLoader: *const fn (*anyopaque, *anyopaque) callconv(winapi) HRESULT,
    UnregisterFontFileLoader: *const fn (*anyopaque, *anyopaque) callconv(winapi) HRESULT,
    CreateTextFormat: *const fn (
        *anyopaque,            // self
        [*:0]const u16,        // fontFamilyName (UTF-16)
        ?*anyopaque,           // fontCollection (null = system)
        u32,                   // fontWeight
        u32,                   // fontStyle
        u32,                   // fontStretch
        FLOAT,                 // fontSize (DIPs)
        [*:0]const u16,        // localeName
        *?*anyopaque,          // textFormat
    ) callconv(winapi) HRESULT,
    CreateTypography: *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    GetGdiInterop: *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    CreateTextLayout: *const fn (
        *anyopaque,       // self
        [*]const u16,     // string
        u32,              // stringLength
        *anyopaque,       // textFormat (IDWriteTextFormat*)
        FLOAT,            // maxWidth
        FLOAT,            // maxHeight
        *?*anyopaque,     // textLayout
    ) callconv(winapi) HRESULT,
};

// IDWriteTextFormat vtable (partial)
const IDWriteTextFormatVtbl = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    // IDWriteTextFormat slots we don't need but must count
    SetTextAlignment:      *const fn (*anyopaque, u32) callconv(winapi) HRESULT,
    SetParagraphAlignment: *const fn (*anyopaque, u32) callconv(winapi) HRESULT,
    SetWordWrapping:       *const fn (*anyopaque, u32) callconv(winapi) HRESULT,
    // ... rest omitted, we only use AddRef/Release on text formats
};

// DWRITE_TEXT_RANGE — passed by value in IDWriteTextLayout range-aware methods.
const DWRITE_TEXT_RANGE = extern struct {
    startPosition: u32,
    length:        u32,
};

// IDWriteTextLayout vtable.
// We only call: IUnknown (Release), GetMetrics.
// All other slots are stubbed with *const fn(*anyopaque,...) to give correct vtable offsets.
// DWRITE_TEXT_RANGE parameters (which pass by value) use the concrete struct above.
const IDWriteTextLayoutVtbl = extern struct {
    // IUnknown (0-2)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    // IDWriteTextFormat inherited slots (3-25)
    SetTextAlignment:      *const fn (*anyopaque, u32) callconv(winapi) HRESULT,
    SetParagraphAlignment: *const fn (*anyopaque, u32) callconv(winapi) HRESULT,
    SetWordWrapping:       *const fn (*anyopaque, u32) callconv(winapi) HRESULT,
    SetReadingDirection:   *const fn (*anyopaque, u32) callconv(winapi) HRESULT,
    SetFlowDirection:      *const fn (*anyopaque, u32) callconv(winapi) HRESULT,
    SetIncrementalTabStop: *const fn (*anyopaque, FLOAT) callconv(winapi) HRESULT,
    SetTrimming:           *const fn (*anyopaque, *const anyopaque, ?*anyopaque) callconv(winapi) HRESULT,
    SetLineSpacing:        *const fn (*anyopaque, u32, FLOAT, FLOAT) callconv(winapi) HRESULT,
    GetTextAlignment:      *const fn (*anyopaque) callconv(winapi) u32,
    GetParagraphAlignment: *const fn (*anyopaque) callconv(winapi) u32,
    GetWordWrapping:       *const fn (*anyopaque) callconv(winapi) u32,
    GetReadingDirection:   *const fn (*anyopaque) callconv(winapi) u32,
    GetFlowDirection:      *const fn (*anyopaque) callconv(winapi) u32,
    GetIncrementalTabStop: *const fn (*anyopaque) callconv(winapi) FLOAT,
    GetTrimming:           *const fn (*anyopaque, *anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    GetLineSpacing:        *const fn (*anyopaque, *u32, *FLOAT, *FLOAT) callconv(winapi) HRESULT,
    GetFontCollection:     *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    GetFontFamilyNameLength: *const fn (*anyopaque) callconv(winapi) u32,
    GetFontFamilyName:     *const fn (*anyopaque, [*]u16, u32) callconv(winapi) HRESULT,
    GetFontWeight:         *const fn (*anyopaque) callconv(winapi) u32,
    GetFontStyle:          *const fn (*anyopaque) callconv(winapi) u32,
    GetFontStretch:        *const fn (*anyopaque) callconv(winapi) u32,
    GetFontSize:           *const fn (*anyopaque) callconv(winapi) FLOAT,
    GetLocaleNameLength:   *const fn (*anyopaque) callconv(winapi) u32,
    GetLocaleName:         *const fn (*anyopaque, [*]u16, u32) callconv(winapi) HRESULT,
    // IDWriteTextLayout own slots (26+)
    // DWRITE_TEXT_RANGE is passed by value as two u32s (startPosition, length).
    SetMaxWidth:           *const fn (*anyopaque, FLOAT) callconv(winapi) HRESULT,
    SetMaxHeight:          *const fn (*anyopaque, FLOAT) callconv(winapi) HRESULT,
    SetFontCollection:     *const fn (*anyopaque, *anyopaque, DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    SetFontFamilyName:     *const fn (*anyopaque, [*:0]const u16, DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    SetFontWeight:         *const fn (*anyopaque, u32, DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    SetFontStyle:          *const fn (*anyopaque, u32, DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    SetFontStretch:        *const fn (*anyopaque, u32, DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    SetFontSize:           *const fn (*anyopaque, FLOAT, DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    SetUnderline:          *const fn (*anyopaque, BOOL, DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    SetStrikethrough:      *const fn (*anyopaque, BOOL, DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    SetDrawingEffect:      *const fn (*anyopaque, *anyopaque, DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    SetInlineObject:       *const fn (*anyopaque, *anyopaque, DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    SetTypography:         *const fn (*anyopaque, *anyopaque, DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    SetLocaleName:         *const fn (*anyopaque, [*:0]const u16, DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetMaxWidth:           *const fn (*anyopaque) callconv(winapi) FLOAT,
    GetMaxHeight:          *const fn (*anyopaque) callconv(winapi) FLOAT,
    GetFontCollection2:    *const fn (*anyopaque, u32, *?*anyopaque, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetFontFamilyNameLength2: *const fn (*anyopaque, u32, *u32, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetFontFamilyName2:    *const fn (*anyopaque, u32, [*]u16, u32, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetFontWeight2:        *const fn (*anyopaque, u32, *u32, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetFontStyle2:         *const fn (*anyopaque, u32, *u32, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetFontStretch2:       *const fn (*anyopaque, u32, *u32, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetFontSize2:          *const fn (*anyopaque, u32, *FLOAT, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetUnderline:          *const fn (*anyopaque, u32, *BOOL, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetStrikethrough:      *const fn (*anyopaque, u32, *BOOL, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetDrawingEffect:      *const fn (*anyopaque, u32, *?*anyopaque, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetInlineObject:       *const fn (*anyopaque, u32, *?*anyopaque, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetTypography:         *const fn (*anyopaque, u32, *?*anyopaque, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetLocaleNameLength2:  *const fn (*anyopaque, u32, *u32, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    GetLocaleName2:        *const fn (*anyopaque, u32, [*]u16, u32, ?*DWRITE_TEXT_RANGE) callconv(winapi) HRESULT,
    Draw:                  *const fn (*anyopaque, ?*anyopaque, *anyopaque, FLOAT, FLOAT) callconv(winapi) HRESULT,
    GetLineMetrics:        *const fn (*anyopaque, ?*anyopaque, u32, *u32) callconv(winapi) HRESULT,
    GetMetrics:            *const fn (*anyopaque, *DWRITE_TEXT_METRICS) callconv(winapi) HRESULT,
    GetOverhangMetrics:    *const fn (*anyopaque, *anyopaque) callconv(winapi) HRESULT,
    GetClusterMetrics:     *const fn (*anyopaque, ?*anyopaque, u32, *u32) callconv(winapi) HRESULT,
    DetermineMinWidth:     *const fn (*anyopaque, *FLOAT) callconv(winapi) HRESULT,
    HitTestPoint:          *const fn (*anyopaque, FLOAT, FLOAT, *BOOL, *BOOL, *anyopaque) callconv(winapi) HRESULT,
    HitTestTextPosition:   *const fn (*anyopaque, u32, BOOL, *FLOAT, *FLOAT, *anyopaque) callconv(winapi) HRESULT,
    HitTestTextRange:      *const fn (*anyopaque, u32, u32, FLOAT, FLOAT, ?*anyopaque, u32, *u32) callconv(winapi) HRESULT,
};

// ── COM "face" types ──────────────────────────────────────────────────────────

const ID2D1FactoryFace          = extern struct { vtbl: *const ID2D1FactoryVtbl };
const ID2D1HwndRenderTargetFace = extern struct { vtbl: *const ID2D1HwndRenderTargetVtbl };
const ID2D1SolidColorBrushFace  = extern struct { vtbl: *const ID2D1SolidColorBrushVtbl };
const ID2D1BitmapFace           = extern struct { vtbl: *const ID2D1BitmapVtbl };
const IDWriteFactoryFace        = extern struct { vtbl: *const IDWriteFactoryVtbl };
const IDWriteTextFormatFace     = extern struct { vtbl: *const IDWriteTextFormatVtbl };
const IDWriteTextLayoutFace     = extern struct { vtbl: *const IDWriteTextLayoutVtbl };

// ── DLL entry points ──────────────────────────────────────────────────────────

extern "d2d1" fn D2D1CreateFactory(
    factoryType:    u32,
    riid:           *const GUID,
    pFactoryOptions: ?*anyopaque,
    ppIFactory:     **anyopaque,
) callconv(winapi) HRESULT;

extern "dwrite" fn DWriteCreateFactory(
    factoryType: u32,
    iid:         *const GUID,
    factory:     **anyopaque,
) callconv(winapi) HRESULT;

// ── D2D 1.1 device-context + DXGI swapchain path ──────────────────────────────
// The legacy ID2D1HwndRenderTarget (above) can't host ID2D1Effect (needed for the
// GPU NV12→RGB YCbCr effect), so we render through an ID2D1DeviceContext whose
// target is a DXGI swapchain backbuffer. D3D11CreateDeviceAndSwapChain builds the
// device + swapchain in one call (no DXGI factory walk); the device is exposed so
// the H.264 decoder can DXVA-decode on it and hand its NV12 texture straight in.

extern "user32" fn GetDpiForWindow(hwnd: *anyopaque) callconv(winapi) u32;

extern "d3d11" fn D3D11CreateDeviceAndSwapChain(
    pAdapter: ?*anyopaque,
    DriverType: u32,
    Software: ?*anyopaque,
    Flags: u32,
    pFeatureLevels: ?*const u32,
    FeatureLevels: u32,
    SDKVersion: u32,
    pSwapChainDesc: *const DXGI_SWAP_CHAIN_DESC,
    ppSwapChain: *?*anyopaque,
    ppDevice: *?*anyopaque,
    pFeatureLevel: ?*u32,
    ppImmediateContext: *?*anyopaque,
) callconv(winapi) HRESULT;

extern "d2d1" fn D2D1CreateDevice(
    dxgiDevice: *anyopaque,
    creationProperties: ?*const anyopaque,
    d2dDevice: *?*anyopaque,
) callconv(winapi) HRESULT;


const D3D_DRIVER_TYPE_HARDWARE: u32 = 1;
const D3D11_SDK_VERSION: u32 = 7;
const D3D11_CREATE_DEVICE_BGRA_SUPPORT: u32 = 0x20;
const D3D11_CREATE_DEVICE_VIDEO_SUPPORT: u32 = 0x800; // DXVA decode (shared-device decoder, Phase 3)
// {9B7E4E00-342C-4106-A19F-4F2704F689F0} IID_ID3D11Multithread
const IID_ID3D11Multithread = GUID{ .Data1 = 0x9B7E4E00, .Data2 = 0x342C, .Data3 = 0x4106, .Data4 = .{ 0xA1, 0x9F, 0x4F, 0x27, 0x04, 0xF6, 0x89, 0xF0 } };
const ID3D11MultithreadVtbl = extern struct {
    _pad_0_4: [5]*const anyopaque, // IUnknown(3) + Enter(3) + Leave(4)
    SetMultithreadProtected: *const fn (*anyopaque, BOOL) callconv(winapi) BOOL, // 5
};
const ID3D11MultithreadFace = extern struct { vtbl: *const ID3D11MultithreadVtbl };
const DXGI_USAGE_RENDER_TARGET_OUTPUT: u32 = 0x20;
const DXGI_SWAP_EFFECT_DISCARD: u32 = 0;
const DXGI_FORMAT_UNKNOWN: u32 = 0;
const D2D1_BITMAP_OPTIONS_TARGET: u32 = 1;
const D2D1_BITMAP_OPTIONS_CANNOT_DRAW: u32 = 2;
const D2D1_DEVICE_CONTEXT_OPTIONS_NONE: u32 = 0;

// {54ec77fa-1377-44e6-8c32-88fd5f44c84c} IID_IDXGIDevice
const IID_IDXGIDevice = GUID{ .Data1 = 0x54ec77fa, .Data2 = 0x1377, .Data3 = 0x44e6, .Data4 = .{ 0x8c, 0x32, 0x88, 0xfd, 0x5f, 0x44, 0xc8, 0x4c } };
// {cafcb56c-6ac3-4889-bf47-9e23bbd260ec} IID_IDXGISurface
const IID_IDXGISurface = GUID{ .Data1 = 0xcafcb56c, .Data2 = 0x6ac3, .Data3 = 0x4889, .Data4 = .{ 0xbf, 0x47, 0x9e, 0x23, 0xbb, 0xd2, 0x60, 0xec } };

const DXGI_RATIONAL = extern struct { Numerator: u32, Denominator: u32 };
const DXGI_MODE_DESC = extern struct {
    Width: u32,
    Height: u32,
    RefreshRate: DXGI_RATIONAL,
    Format: u32,
    ScanlineOrdering: u32,
    Scaling: u32,
};
const DXGI_SAMPLE_DESC = extern struct { Count: u32, Quality: u32 };
const DXGI_SWAP_CHAIN_DESC = extern struct {
    BufferDesc: DXGI_MODE_DESC,
    SampleDesc: DXGI_SAMPLE_DESC,
    BufferUsage: u32,
    BufferCount: u32,
    OutputWindow: HWND,
    Windowed: BOOL,
    SwapEffect: u32,
    Flags: u32,
};
const D2D1_BITMAP_PROPERTIES1 = extern struct {
    pixelFormat: D2D1_PIXEL_FORMAT,
    dpiX: FLOAT,
    dpiY: FLOAT,
    bitmapOptions: u32,
    colorContext: ?*anyopaque,
};

// Generic IUnknown view for QueryInterface/Release on opaque COM pointers.
const IUnknownVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
};
const IUnknownFace = extern struct { vtbl: *const IUnknownVtbl };

// ID2D1Device : ID2D1Resource — we only need CreateDeviceContext (slot 4).
const ID2D1DeviceVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    GetFactory:     *const fn (*anyopaque, *?*anyopaque) callconv(winapi) void,
    CreateDeviceContext: *const fn (*anyopaque, u32, *?*anyopaque) callconv(winapi) HRESULT,
};
const ID2D1DeviceFace = extern struct { vtbl: *const ID2D1DeviceVtbl };

// IDXGISwapChain : IDXGIDeviceSubObject : IDXGIObject.
const IDXGISwapChainVtbl = extern struct {
    // IUnknown 0-2
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    // IDXGIObject 3-6
    SetPrivateData:          *const fn (*anyopaque, *const GUID, u32, *const anyopaque) callconv(winapi) HRESULT,
    SetPrivateDataInterface: *const fn (*anyopaque, *const GUID, ?*const anyopaque) callconv(winapi) HRESULT,
    GetPrivateData:          *const fn (*anyopaque, *const GUID, *u32, *anyopaque) callconv(winapi) HRESULT,
    GetParent:               *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    // IDXGIDeviceSubObject 7
    GetDevice: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    // IDXGISwapChain 8-14
    Present:            *const fn (*anyopaque, u32, u32) callconv(winapi) HRESULT,
    GetBuffer:          *const fn (*anyopaque, u32, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    SetFullscreenState: *const fn (*anyopaque, BOOL, ?*anyopaque) callconv(winapi) HRESULT,
    GetFullscreenState: *const fn (*anyopaque, ?*BOOL, *?*anyopaque) callconv(winapi) HRESULT,
    GetDesc:            *const fn (*anyopaque, *DXGI_SWAP_CHAIN_DESC) callconv(winapi) HRESULT,
    ResizeBuffers:      *const fn (*anyopaque, u32, u32, u32, u32, u32) callconv(winapi) HRESULT,
    // ResizeTarget … unused
};
const IDXGISwapChainFace = extern struct { vtbl: *const IDXGISwapChainVtbl };

// ID2D1DeviceContext : ID2D1RenderTarget. Slots 0-57 are identical to
// ID2D1RenderTarget, so the existing draw methods call through the
// ID2D1HwndRenderTargetFace view; here we only bind the four 1.1 methods we use,
// padding the gaps with the EXACT slot counts so their offsets are correct.
const ID2D1DeviceContextVtbl = extern struct {
    // IUnknown(3) + ID2D1Resource(1) + ID2D1RenderTarget(53) = slots 0..56, then the
    // ID2D1DeviceContext methods start at 57. CreateBitmap(57), CreateBitmapFromWicBitmap(58),
    // CreateColorContext*3 (59..61) → CreateBitmapFromDxgiSurface at 62.
    _pad_0_61: [62]*const anyopaque, // slots 0..61
    CreateBitmapFromDxgiSurface: *const fn (*anyopaque, *anyopaque, ?*const D2D1_BITMAP_PROPERTIES1, *?*anyopaque) callconv(winapi) HRESULT, // 62
    CreateEffect:                *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT, // 63
    _pad_64_73: [10]*const anyopaque, // 64..73
    SetTarget: *const fn (*anyopaque, ?*anyopaque) callconv(winapi) void, // 74
    _pad_75_82: [8]*const anyopaque, // 75..82
    DrawImage: *const fn (*anyopaque, *anyopaque, ?*const D2D1_POINT_2F, ?*const D2D1_RECT_F, u32, u32) callconv(winapi) void, // 83
};
const ID2D1DeviceContextFace = extern struct { vtbl: *const ID2D1DeviceContextVtbl };

fn relCom(p: *anyopaque) void {
    const u: *IUnknownFace = @ptrCast(@alignCast(p));
    _ = u.vtbl.Release(@ptrCast(u));
}

/// Bind the swapchain's backbuffer as the device context's render target.
/// Returns the ID2D1Bitmap1 target (caller owns a ref). Used by init and resize.
fn makeSwapchainTarget(swapchain: *IDXGISwapChainFace, dc: *ID2D1DeviceContextFace) !*anyopaque {
    var surf_raw: ?*anyopaque = null;
    if (swapchain.vtbl.GetBuffer(@ptrCast(swapchain), 0, &IID_IDXGISurface, &surf_raw) != S_OK or surf_raw == null)
        return error.SwapchainGetBufferFailed;
    const surf = surf_raw.?;
    defer relCom(surf);
    const props = D2D1_BITMAP_PROPERTIES1{
        .pixelFormat = .{ .format = DXGI_FORMAT_B8G8R8A8_UNORM, .alphaMode = D2D1_ALPHA_MODE_IGNORE },
        .dpiX = 96.0,
        .dpiY = 96.0,
        .bitmapOptions = D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
        .colorContext = null,
    };
    var bmp_raw: ?*anyopaque = null;
    if (dc.vtbl.CreateBitmapFromDxgiSurface(@ptrCast(dc), surf, &props, &bmp_raw) != S_OK or bmp_raw == null)
        return error.CreateBitmapFromDxgiFailed;
    dc.vtbl.SetTarget(@ptrCast(dc), bmp_raw.?);
    return bmp_raw.?;
}

// ── Font size table ───────────────────────────────────────────────────────────
// Matches software renderer exactly: indexed by scale (1..6).
// Values are in points/DIPs (D2D uses DIPs = 1/96 inch by default).
// We store as f32 (pt sizes) — D2D will scale by DPI internally since we
// set DPI on the render target.

const FONT_PX = [7]f32{ 0, 14, 22, 32, 44, 60, 80 };
const NUM_FONT_SCALES: usize = FONT_PX.len;

/// Approximate line-height for layout purposes (scale=1 body text).
pub const LINE_H: u32 = 18;

// Segoe UI Variable family name as UTF-16 literal
const SEGOE_UI_VAR = std.unicode.utf8ToUtf16LeStringLiteral("Segoe UI Variable");
// Icon font: "Segoe MDL2 Assets" (ships on Win10 1709+/11) for UI glyphs.
const SEGOE_ICONS = std.unicode.utf8ToUtf16LeStringLiteral("Segoe MDL2 Assets");
const LOCALE_EN_US = std.unicode.utf8ToUtf16LeStringLiteral("en-us");
const LOCALE_EMPTY = std.unicode.utf8ToUtf16LeStringLiteral("");

// ── D3D11 VideoProcessor (GPU NV12→BGRA + scale) bindings ─────────────────────
// drawNv12 converts a decoded NV12 ID3D11Texture2D to BGRA on the GPU via
// ID3D11VideoContext.VideoProcessorBlt, then the BGRA result draws through the
// existing CreateBitmapFromDxgiSurface/DrawBitmap path. Only the handful of
// methods we call are bound; vtbl gaps are padded with exact slot counts.

const DXGI_FORMAT_NV12: u32 = 103;
const D3D11_BIND_RENDER_TARGET: u32 = 0x20;
const D3D11_BIND_SHADER_RESOURCE: u32 = 0x8;
const D3D11_USAGE_DEFAULT: u32 = 0;
const D3D11_VPIV_DIMENSION_TEXTURE2D: u32 = 1;
const D3D11_VPOV_DIMENSION_TEXTURE2D: u32 = 1;
const D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE: u32 = 0;
// D3D11_VIDEO_USAGE_PLAYBACK_NORMAL = 0
// Colorspace bitfields packed into a u32 (D3D11_VIDEO_PROCESSOR_COLOR_SPACE):
//   bit0 Usage, bit1 RGB_Range, bits2-3 YCbCr_Matrix(=1 BT.709 / 0 BT.601),
//   bit4 YCbCr_XvYCC, bits5-6 Nominal_Range. We use BT.601 limited (Matrix=0).

const D3D11_SUBRESOURCE_DATA = extern struct {
    pSysMem: *const anyopaque,
    SysMemPitch: u32,
    SysMemSlicePitch: u32,
};

const D3D11_TEXTURE2D_DESC = extern struct {
    Width: u32,
    Height: u32,
    MipLevels: u32,
    ArraySize: u32,
    Format: u32,
    SampleDesc: DXGI_SAMPLE_DESC,
    Usage: u32,
    BindFlags: u32,
    CPUAccessFlags: u32,
    MiscFlags: u32,
};

const D3D11_VIDEO_PROCESSOR_CONTENT_DESC = extern struct {
    InputFrameFormat: u32,
    InputFrameRate: DXGI_RATIONAL,
    InputWidth: u32,
    InputHeight: u32,
    OutputFrameRate: DXGI_RATIONAL,
    OutputWidth: u32,
    OutputHeight: u32,
    Usage: u32,
};

const D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC = extern struct {
    ViewDimension: u32,
    MipSlice: u32, // union { Texture2D{MipSlice}, ... } — Texture2D is one u32
};

const D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC = extern struct {
    FourCC: u32,
    ViewDimension: u32,
    // union: Texture2D { MipSlice: u32, ArraySlice: u32 }
    MipSlice: u32,
    ArraySlice: u32,
};

const D3D11_VIDEO_PROCESSOR_STREAM = extern struct {
    Enable: BOOL,
    OutputIndex: u32,
    InputFrameOrField: u32,
    PastFrames: u32,
    FutureFrames: u32,
    ppPastSurfaces: ?*anyopaque,
    pInputSurface: ?*anyopaque, // ID3D11VideoProcessorInputView*
    ppFutureSurfaces: ?*anyopaque,
    ppPastSurfacesRight: ?*anyopaque,
    pInputSurfaceRight: ?*anyopaque,
    ppFutureSurfacesRight: ?*anyopaque,
};

const D3D11_VIDEO_PROCESSOR_COLOR_SPACE = extern struct {
    bits: u32, // packed bitfield (see note above)
};

// {1788DE07-..} not needed; QI uses the canonical IIDs below.
// {B1C7706B-..}? use the published IIDs:
const IID_ID3D11VideoDevice = GUID{ .Data1 = 0x10EC4D5B, .Data2 = 0x975A, .Data3 = 0x4689, .Data4 = .{ 0xB9, 0xE4, 0xD0, 0xAA, 0xC3, 0x0F, 0xE3, 0x33 } };
const IID_ID3D11VideoContext = GUID{ .Data1 = 0x61F21C45, .Data2 = 0x3C0E, .Data3 = 0x4a74, .Data4 = .{ 0x9C, 0xEA, 0x67, 0x10, 0x0D, 0x9A, 0xD5, 0xE4 } };

// ID3D11Device — we only need CreateTexture2D (slot 5).
const ID3D11DeviceVtbl = extern struct {
    _pad_0_4: [5]*const anyopaque, // IUnknown(3) + CreateBuffer(3) + ... up to 4
    CreateTexture2D: *const fn (*anyopaque, *const D3D11_TEXTURE2D_DESC, ?*const anyopaque, *?*anyopaque) callconv(winapi) HRESULT, // 5
};
const ID3D11DeviceFace = extern struct { vtbl: *const ID3D11DeviceVtbl };

// ID3D11VideoDevice : IUnknown. CreateVideoProcessor(4), CreateVideoProcessorInputView(8),
// CreateVideoProcessorOutputView(9), CreateVideoProcessorEnumerator(10).
const ID3D11VideoDeviceVtbl = extern struct {
    _pad_0_2: [3]*const anyopaque, // IUnknown
    _slot3: *const anyopaque, // CreateVideoDecoder
    CreateVideoProcessor: *const fn (*anyopaque, *anyopaque, u32, *?*anyopaque) callconv(winapi) HRESULT, // 4
    _slot5_7: [3]*const anyopaque, // CreateAuthenticatedChannel, CreateCryptoSession, CreateVideoDecoderOutputView
    CreateVideoProcessorInputView: *const fn (*anyopaque, *anyopaque, *anyopaque, *const D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC, *?*anyopaque) callconv(winapi) HRESULT, // 8
    CreateVideoProcessorOutputView: *const fn (*anyopaque, *anyopaque, *anyopaque, *const D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC, *?*anyopaque) callconv(winapi) HRESULT, // 9
    CreateVideoProcessorEnumerator: *const fn (*anyopaque, *const D3D11_VIDEO_PROCESSOR_CONTENT_DESC, *?*anyopaque) callconv(winapi) HRESULT, // 10
};
const ID3D11VideoDeviceFace = extern struct { vtbl: *const ID3D11VideoDeviceVtbl };

// ID3D11VideoContext : ID3D11DeviceChild. VideoProcessorSetOutputColorSpace(15),
// VideoProcessorSetStreamColorSpace(28), VideoProcessorBlt(53).
const ID3D11VideoContextVtbl = extern struct {
    _pad_0_14: [15]*const anyopaque, // IUnknown(3)+DeviceChild(4)+VideoContext 7..14
    VideoProcessorSetOutputColorSpace: *const fn (*anyopaque, *anyopaque, *const D3D11_VIDEO_PROCESSOR_COLOR_SPACE) callconv(winapi) void, // 15
    _pad_16_27: [12]*const anyopaque, // 16..27
    VideoProcessorSetStreamColorSpace: *const fn (*anyopaque, *anyopaque, u32, *const D3D11_VIDEO_PROCESSOR_COLOR_SPACE) callconv(winapi) void, // 28
    _pad_29_52: [24]*const anyopaque, // 29..52
    VideoProcessorBlt: *const fn (*anyopaque, *anyopaque, *anyopaque, u32, u32, *const D3D11_VIDEO_PROCESSOR_STREAM) callconv(winapi) HRESULT, // 53
};
const ID3D11VideoContextFace = extern struct { vtbl: *const ID3D11VideoContextVtbl };

// Lazily-created VideoProcessor pipeline, cached on the renderer once sizes are known.
const VideoNv12 = struct {
    video_device: *ID3D11VideoDeviceFace,
    video_ctx: *ID3D11VideoContextFace,
    enumerator: *anyopaque,
    processor: *anyopaque,
    out_tex: *anyopaque, // ID3D11Texture2D (BGRA)
    out_view: *anyopaque, // ID3D11VideoProcessorOutputView
    out_bitmap: *anyopaque, // ID2D1Bitmap1 wrapping out_tex (for DrawBitmap)
    src_w: u32,
    src_h: u32,
    out_w: u32,
    out_h: u32,
};

/// Build the GPU NV12→BGRA pipeline for a given source size. The output texture is
/// at source resolution (D2D scales it on draw). Returns error on any failure so the
/// caller can fall back to the CPU path.
fn buildVp(d3d_device: *anyopaque, d3d_ctx: *anyopaque, dc_ctx: *ID2D1DeviceContextFace, src_w: u32, src_h: u32) !VideoNv12 {
    var vdev_raw: ?*anyopaque = null;
    {
        const u: *IUnknownFace = @ptrCast(@alignCast(d3d_device));
        if (u.vtbl.QueryInterface(@ptrCast(u), &IID_ID3D11VideoDevice, &vdev_raw) != S_OK or vdev_raw == null) return error.VideoDeviceQi;
    }
    const video_device: *ID3D11VideoDeviceFace = @ptrCast(@alignCast(vdev_raw.?));
    errdefer relCom(@ptrCast(video_device));

    var vctx_raw: ?*anyopaque = null;
    {
        const u: *IUnknownFace = @ptrCast(@alignCast(d3d_ctx));
        if (u.vtbl.QueryInterface(@ptrCast(u), &IID_ID3D11VideoContext, &vctx_raw) != S_OK or vctx_raw == null) return error.VideoContextQi;
    }
    const video_ctx: *ID3D11VideoContextFace = @ptrCast(@alignCast(vctx_raw.?));
    errdefer relCom(@ptrCast(video_ctx));

    const cdesc = D3D11_VIDEO_PROCESSOR_CONTENT_DESC{
        .InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE,
        .InputFrameRate = .{ .Numerator = 60, .Denominator = 1 },
        .InputWidth = src_w,
        .InputHeight = src_h,
        .OutputFrameRate = .{ .Numerator = 60, .Denominator = 1 },
        .OutputWidth = src_w,
        .OutputHeight = src_h,
        .Usage = 0, // D3D11_VIDEO_USAGE_PLAYBACK_NORMAL
    };
    var enum_raw: ?*anyopaque = null;
    if (video_device.vtbl.CreateVideoProcessorEnumerator(@ptrCast(video_device), &cdesc, &enum_raw) != S_OK or enum_raw == null) return error.VpEnum;
    const enumerator = enum_raw.?;
    errdefer relCom(enumerator);

    var proc_raw: ?*anyopaque = null;
    if (video_device.vtbl.CreateVideoProcessor(@ptrCast(video_device), enumerator, 0, &proc_raw) != S_OK or proc_raw == null) return error.VpProc;
    const processor = proc_raw.?;
    errdefer relCom(processor);

    const tdesc = D3D11_TEXTURE2D_DESC{
        .Width = src_w,
        .Height = src_h,
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = DXGI_FORMAT_B8G8R8A8_UNORM,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .Usage = D3D11_USAGE_DEFAULT,
        .BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE,
        .CPUAccessFlags = 0,
        .MiscFlags = 0,
    };
    var tex_raw: ?*anyopaque = null;
    {
        const dev: *ID3D11DeviceFace = @ptrCast(@alignCast(d3d_device));
        if (dev.vtbl.CreateTexture2D(@ptrCast(dev), &tdesc, null, &tex_raw) != S_OK or tex_raw == null) return error.VpTex;
    }
    const out_tex = tex_raw.?;
    errdefer relCom(out_tex);

    const ovd = D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC{ .ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D, .MipSlice = 0 };
    var ov_raw: ?*anyopaque = null;
    if (video_device.vtbl.CreateVideoProcessorOutputView(@ptrCast(video_device), out_tex, enumerator, &ovd, &ov_raw) != S_OK or ov_raw == null) return error.VpOutView;
    const out_view = ov_raw.?;
    errdefer relCom(out_view);

    // Wrap the BGRA output texture as a D2D bitmap so DrawBitmap can scale it.
    var surf_raw: ?*anyopaque = null;
    {
        const u: *IUnknownFace = @ptrCast(@alignCast(out_tex));
        if (u.vtbl.QueryInterface(@ptrCast(u), &IID_IDXGISurface, &surf_raw) != S_OK or surf_raw == null) return error.VpSurf;
    }
    const surf = surf_raw.?;
    defer relCom(surf);
    const bprops = D2D1_BITMAP_PROPERTIES1{
        .pixelFormat = .{ .format = DXGI_FORMAT_B8G8R8A8_UNORM, .alphaMode = D2D1_ALPHA_MODE_IGNORE },
        .dpiX = 96.0,
        .dpiY = 96.0,
        .bitmapOptions = 0, // normal drawable bitmap
        .colorContext = null,
    };
    var bmp_raw: ?*anyopaque = null;
    if (dc_ctx.vtbl.CreateBitmapFromDxgiSurface(@ptrCast(dc_ctx), surf, &bprops, &bmp_raw) != S_OK or bmp_raw == null) return error.VpBitmap;
    const out_bitmap = bmp_raw.?;
    errdefer relCom(out_bitmap);

    return VideoNv12{
        .video_device = video_device,
        .video_ctx = video_ctx,
        .enumerator = enumerator,
        .processor = processor,
        .out_tex = out_tex,
        .out_view = out_view,
        .out_bitmap = out_bitmap,
        .src_w = src_w,
        .src_h = src_h,
        .out_w = src_w,
        .out_h = src_h,
    };
}

// ── Renderer ──────────────────────────────────────────────────────────────────

pub const Renderer = struct {
    // `render_target` and `device_context` are the SAME ID2D1DeviceContext COM
    // object viewed through two vtbls: the RenderTarget view (slots 0-57) drives
    // every existing draw method unchanged, the DeviceContext view exposes the 1.1
    // methods (SetTarget / effects). Released once (via render_target).
    render_target:  *ID2D1HwndRenderTargetFace,
    device_context: *ID2D1DeviceContextFace,
    d2d_device:     *ID2D1DeviceFace,
    swapchain:      *IDXGISwapChainFace,
    d3d_device:     *anyopaque,        // ID3D11Device — shared with the decoder (Phase 3)
    d3d_ctx:        *anyopaque,        // ID3D11DeviceContext (immediate) — VideoProcessorBlt
    target_bitmap:  ?*anyopaque,        // swapchain backbuffer bound as the D2D target
    vp:             ?VideoNv12 = null,  // lazily-created GPU NV12→BGRA pipeline
    brush:          *ID2D1SolidColorBrushFace,
    dwrite:         ?*IDWriteFactoryFace, // null if DirectWrite is unavailable (text disabled)
    text_formats:   [NUM_FONT_SCALES]?*IDWriteTextFormatFace,
    icon_formats:   [NUM_FONT_SCALES]?*IDWriteTextFormatFace, // Segoe MDL2 Assets
    dpi_scale:      f32,
    width:          u32,
    height:         u32,
    begin_draw_called: bool,
    clip_pushed:    bool,

    /// The D3D11 device backing this renderer's swapchain. The H.264 decoder can
    /// DXVA-decode on it so its NV12 texture is usable as a D2D effect input with
    /// no cross-device copy. Returns an `*ID3D11Device` as an opaque pointer.
    pub fn d3dDevice(self: *Renderer) *anyopaque {
        return self.d3d_device;
    }

    /// Initialize the D2D renderer for the given HWND.
    /// `hwnd` must be a valid HWND; `width` and `height` are in physical pixels.
    pub fn init(hwnd: *anyopaque, width: u32, height: u32) !Renderer {
        // ── 1. D3D11 device + DXGI swapchain in one call ──────────────────────
        const scd = DXGI_SWAP_CHAIN_DESC{
            .BufferDesc = .{
                .Width = width,
                .Height = height,
                .RefreshRate = .{ .Numerator = 0, .Denominator = 1 },
                .Format = DXGI_FORMAT_B8G8R8A8_UNORM,
                .ScanlineOrdering = 0,
                .Scaling = 0,
            },
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = 1,
            .OutputWindow = @ptrCast(hwnd),
            .Windowed = 1,
            .SwapEffect = DXGI_SWAP_EFFECT_DISCARD,
            .Flags = 0,
        };
        var swapchain_raw: ?*anyopaque = null;
        var device_raw: ?*anyopaque = null;
        var ctx_raw: ?*anyopaque = null;
        const hr_dev = D3D11CreateDeviceAndSwapChain(
            null, D3D_DRIVER_TYPE_HARDWARE, null,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT, null, 0, D3D11_SDK_VERSION,
            &scd, &swapchain_raw, &device_raw, null, &ctx_raw,
        );
        if (hr_dev != S_OK or device_raw == null or swapchain_raw == null)
            return error.D3D11CreateFailed;
        const d3d_device = device_raw.?;
        errdefer relCom(d3d_device);
        const d3d_ctx = ctx_raw orelse return error.D3D11CreateFailed; // kept for the VideoProcessor (NV12 path)
        errdefer relCom(d3d_ctx);
        // The decoder will DXVA-decode on this device from the receive thread while
        // the renderer presents on the main thread — serialize device access.
        {
            var mt_raw: ?*anyopaque = null;
            const u: *IUnknownFace = @ptrCast(@alignCast(d3d_ctx));
            if (u.vtbl.QueryInterface(@ptrCast(u), &IID_ID3D11Multithread, &mt_raw) == S_OK) {
                if (mt_raw) |m| {
                    const mt: *ID3D11MultithreadFace = @ptrCast(@alignCast(m));
                    _ = mt.vtbl.SetMultithreadProtected(@ptrCast(mt), 1);
                    relCom(m);
                }
            }
        }
        const swapchain: *IDXGISwapChainFace = @ptrCast(@alignCast(swapchain_raw.?));
        errdefer relCom(@ptrCast(swapchain));

        // ── 2. D3D device → IDXGIDevice → D2D device → device context ─────────
        var dxgi_dev_raw: ?*anyopaque = null;
        {
            const u: *IUnknownFace = @ptrCast(@alignCast(d3d_device));
            if (u.vtbl.QueryInterface(@ptrCast(u), &IID_IDXGIDevice, &dxgi_dev_raw) != S_OK or dxgi_dev_raw == null)
                return error.DxgiDeviceQiFailed;
        }
        const dxgi_dev = dxgi_dev_raw.?;
        defer relCom(dxgi_dev); // only needed to create the D2D device

        var d2d_dev_raw: ?*anyopaque = null;
        if (D2D1CreateDevice(dxgi_dev, null, &d2d_dev_raw) != S_OK or d2d_dev_raw == null)
            return error.D2DCreateDeviceFailed;
        const d2d_device: *ID2D1DeviceFace = @ptrCast(@alignCast(d2d_dev_raw.?));
        errdefer relCom(@ptrCast(d2d_device));

        var dc_raw: ?*anyopaque = null;
        if (d2d_device.vtbl.CreateDeviceContext(@ptrCast(d2d_device), D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &dc_raw) != S_OK or dc_raw == null)
            return error.D2DDeviceContextFailed;
        const dc = dc_raw.?;
        errdefer relCom(dc);
        // Same COM object, two vtbl views (see the struct doc comment).
        const dc_render: *ID2D1HwndRenderTargetFace = @ptrCast(@alignCast(dc));
        const dc_ctx: *ID2D1DeviceContextFace = @ptrCast(@alignCast(dc));

        // ── 3. Match the window DPI so logical coords scale to physical pixels ─
        const dpi: f32 = blk: {
            const d = GetDpiForWindow(hwnd);
            break :blk if (d > 0) @floatFromInt(d) else 96.0;
        };
        dc_render.vtbl.SetDpi(@ptrCast(dc_render), dpi, dpi);

        // ── 4. Bind the swapchain backbuffer as the render target ─────────────
        const target = try makeSwapchainTarget(swapchain, dc_ctx);
        errdefer relCom(target);

        dc_render.vtbl.SetAntialiasMode(@ptrCast(dc_render), D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
        dc_render.vtbl.SetTextAntialiasMode(@ptrCast(dc_render), D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE);

        // ── 5. Reusable solid-color brush ─────────────────────────────────────
        const brush_color = D2D1_COLOR_F{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
        var brush_raw: ?*anyopaque = null;
        if (dc_render.vtbl.CreateSolidColorBrush(@ptrCast(dc_render), &brush_color, null, &brush_raw) != S_OK or brush_raw == null)
            return error.D2DBrushCreateFailed;
        const brush: *ID2D1SolidColorBrushFace = @ptrCast(@alignCast(brush_raw.?));
        errdefer relCom(@ptrCast(brush));

        // ── 6. DirectWrite factory + text formats ─────────────────────────────
        // Request IID_IDWriteFactory1 (not the legacy IID_IDWriteFactory) — see the
        // IID note above for the Windows 11 24H2 E_NOINTERFACE quirk. Text still
        // degrades gracefully (dwrite stays null, drawText skipped) if it ever fails,
        // so shapes/images/GPU video keep rendering.
        var dwrite: ?*IDWriteFactoryFace = null;
        var text_formats: [NUM_FONT_SCALES]?*IDWriteTextFormatFace = .{null} ** NUM_FONT_SCALES;
        var icon_formats: [NUM_FONT_SCALES]?*IDWriteTextFormatFace = .{null} ** NUM_FONT_SCALES;
        var dwrite_raw: *anyopaque = undefined;
        if (DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, &IID_IDWriteFactory1, &dwrite_raw) == S_OK) {
            const dw: *IDWriteFactoryFace = @ptrCast(@alignCast(dwrite_raw));
            dwrite = dw;
            for (FONT_PX, 0..) |px, i| {
                if (px == 0) continue;
                const weight: u32 = if (px >= 32) DWRITE_FONT_WEIGHT_SEMIBOLD else DWRITE_FONT_WEIGHT_NORMAL;
                var fmt_raw: ?*anyopaque = null;
                if (dw.vtbl.CreateTextFormat(@ptrCast(dw), SEGOE_UI_VAR, null, weight, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, px, LOCALE_EN_US, &fmt_raw) == S_OK and fmt_raw != null)
                    text_formats[i] = @ptrCast(@alignCast(fmt_raw.?));
                var icon_raw: ?*anyopaque = null;
                if (dw.vtbl.CreateTextFormat(@ptrCast(dw), SEGOE_ICONS, null, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, px, LOCALE_EN_US, &icon_raw) == S_OK and icon_raw != null)
                    icon_formats[i] = @ptrCast(@alignCast(icon_raw.?));
            }
        }

        return Renderer{
            .render_target = dc_render,
            .device_context = dc_ctx,
            .d2d_device = d2d_device,
            .swapchain = swapchain,
            .d3d_device = d3d_device,
            .d3d_ctx = d3d_ctx,
            .target_bitmap = target,
            .brush = brush,
            .dwrite = dwrite,
            .text_formats = text_formats,
            .icon_formats = icon_formats,
            .dpi_scale = dpi / 96.0,
            .width = width,
            .height = height,
            .begin_draw_called = false,
            .clip_pushed = false,
        };
    }

    pub fn deinit(self: *Renderer) void {
        // Pop any outstanding clip
        if (self.clip_pushed) {
            self.render_target.vtbl.PopAxisAlignedClip(@ptrCast(self.render_target));
            self.clip_pushed = false;
        }
        // End draw if started (ignore HRESULT on deinit)
        if (self.begin_draw_called) {
            _ = self.render_target.vtbl.EndDraw(@ptrCast(self.render_target), null, null);
            self.begin_draw_called = false;
        }
        // Release text + icon formats
        for (&self.text_formats) |*fmt| {
            if (fmt.*) |f| { _ = f.vtbl.Release(@ptrCast(f)); fmt.* = null; }
        }
        for (&self.icon_formats) |*fmt| {
            if (fmt.*) |f| { _ = f.vtbl.Release(@ptrCast(f)); fmt.* = null; }
        }
        if (self.dwrite) |dw| _ = dw.vtbl.Release(@ptrCast(dw));
        _ = self.brush.vtbl.Release(@ptrCast(self.brush));
        // Unbind + release the swapchain target, then the device context (which is
        // the same COM object as render_target — release once), device, swapchain,
        // and finally the D3D11 device.
        self.destroyVp();
        self.device_context.vtbl.SetTarget(@ptrCast(self.device_context), null);
        if (self.target_bitmap) |b| { relCom(b); self.target_bitmap = null; }
        _ = self.render_target.vtbl.Release(@ptrCast(self.render_target));
        relCom(@ptrCast(self.d2d_device));
        relCom(@ptrCast(self.swapchain));
        relCom(self.d3d_ctx);
        relCom(self.d3d_device);
    }

    // ── DPI helpers ───────────────────────────────────────────────────────────

    /// Convert a logical i32 coordinate to DIP float for D2D.
    /// D2D manages DPI internally via the render target DPI setting,
    /// so we pass logical coordinates directly as DIPs.
    inline fn toDip(v: i32) FLOAT {
        return @floatFromInt(v);
    }

    inline fn toDipU(v: u32) FLOAT {
        return @floatFromInt(v);
    }

    // ── Color helper ──────────────────────────────────────────────────────────

    inline fn toColorF(c: Color) D2D1_COLOR_F {
        return .{
            .r = @as(f32, @floatFromInt(c.r)) / 255.0,
            .g = @as(f32, @floatFromInt(c.g)) / 255.0,
            .b = @as(f32, @floatFromInt(c.b)) / 255.0,
            .a = @as(f32, @floatFromInt(c.a)) / 255.0,
        };
    }

    /// Set the brush color without allocating a new brush.
    inline fn setBrushColor(self: *Renderer, color: Color) void {
        const cf = toColorF(color);
        self.brush.vtbl.SetColor(@ptrCast(self.brush), &cf);
    }

    // ── Frame rendering ───────────────────────────────────────────────────────

    /// Begin a new frame and clear to `color`.
    /// In D2D the frame begins with BeginDraw(); all draws happen inside.
    /// flushText() calls EndDraw() to present.
    pub fn clear(self: *Renderer, color: Color) void {
        if (!self.begin_draw_called) {
            self.render_target.vtbl.BeginDraw(@ptrCast(self.render_target));
            self.begin_draw_called = true;
        }
        const cf = toColorF(color);
        self.render_target.vtbl.Clear(@ptrCast(self.render_target), &cf);
    }

    pub fn fillRect(self: *Renderer, rect: Rect, color: Color) void {
        if (!self.begin_draw_called) return;
        const d2d_rect = D2D1_RECT_F{
            .left   = toDip(rect.x),
            .top    = toDip(rect.y),
            .right  = toDip(rect.right()),
            .bottom = toDip(rect.bottom()),
        };
        self.setBrushColor(color);
        self.render_target.vtbl.FillRectangle(
            @ptrCast(self.render_target),
            &d2d_rect,
            @ptrCast(self.brush),
        );
    }

    pub fn fillRoundRect(self: *Renderer, rect: Rect, radius: u32, color: Color) void {
        if (!self.begin_draw_called) return;
        const r: FLOAT = toDipU(radius);
        const rr = D2D1_ROUNDED_RECT{
            .rect = .{
                .left   = toDip(rect.x),
                .top    = toDip(rect.y),
                .right  = toDip(rect.right()),
                .bottom = toDip(rect.bottom()),
            },
            .radiusX = r,
            .radiusY = r,
        };
        self.setBrushColor(color);
        self.render_target.vtbl.FillRoundedRectangle(
            @ptrCast(self.render_target),
            &rr,
            @ptrCast(self.brush),
        );
    }

    // ── Text rendering ─────────────────────────────────────────────────────────

    /// Draw body text (scale=1 / 14 DIP Segoe UI Variable).
    pub fn drawText(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color) void {
        self.drawTextScaled(text, x, y, color, 1);
    }

    /// Draw text at an integer scale (1=14pt, 2=22pt, 3=32pt …).
    /// Uses ID2D1RenderTarget::DrawText directly — no IDWriteTextLayout allocation,
    /// eliminating ~50 COM alloc/release pairs per frame at 60 fps.
    pub fn drawTextScaled(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color, scale: u32) void {
        const idx = @min(scale, NUM_FONT_SCALES - 1);
        self.drawGlyphs(text, x, y, color, self.text_formats[idx]);
    }

    /// Draw an icon glyph (Segoe MDL2 Assets) at an integer scale.
    pub fn drawIcon(self: *Renderer, icon: []const u8, x: i32, y: i32, color: Color, scale: u32) void {
        const idx = @min(scale, NUM_FONT_SCALES - 1);
        self.drawGlyphs(icon, x, y, color, self.icon_formats[idx]);
    }

    fn drawGlyphs(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color, fmt_opt: ?*IDWriteTextFormatFace) void {
        if (!self.begin_draw_called) return;
        const fmt = fmt_opt orelse return;

        var wbuf: [2048]u16 = undefined;
        const wlen = std.unicode.utf8ToUtf16Le(&wbuf, text) catch return;
        if (wlen == 0) return;

        // Large layout rect — DrawText clips to it, but we don't want wrapping.
        const layout_rect = D2D1_RECT_F{
            .left   = toDip(x),
            .top    = toDip(y),
            .right  = toDip(x) + 10000.0,
            .bottom = toDip(y) + 10000.0,
        };
        self.setBrushColor(color);
        self.render_target.vtbl.DrawText(
            @ptrCast(self.render_target),
            wbuf[0..wlen].ptr,
            @intCast(wlen),
            @ptrCast(fmt),
            &layout_rect,
            @ptrCast(self.brush),
            D2D1_DRAW_TEXT_OPTIONS_NONE,
            DWRITE_MEASURING_MODE_NATURAL,
        );
    }

    /// Measure text width in logical pixels using DirectWrite.
    pub fn textWidth(self: *const Renderer, text: []const u8) u32 {
        return self.textWidthScaled(text, 1);
    }

    pub fn textWidthScaled(self: *const Renderer, text: []const u8, scale: u32) u32 {
        const idx = @min(scale, NUM_FONT_SCALES - 1);
        return self.glyphsWidth(text, self.text_formats[idx]);
    }

    /// Measure icon-glyph width (Segoe MDL2 Assets).
    pub fn iconWidthScaled(self: *const Renderer, icon: []const u8, scale: u32) u32 {
        const idx = @min(scale, NUM_FONT_SCALES - 1);
        return self.glyphsWidth(icon, self.icon_formats[idx]);
    }

    fn glyphsWidth(self: *const Renderer, text: []const u8, fmt_opt: ?*IDWriteTextFormatFace) u32 {
        const fmt = fmt_opt orelse return @intCast(text.len * 8);
        // A format is only non-null when dwrite was created, so this unwrap is safe.
        const dwrite = self.dwrite orelse return @intCast(text.len * 8);

        var wbuf: [2048]u16 = undefined;
        const wlen = std.unicode.utf8ToUtf16Le(&wbuf, text) catch return 0;
        if (wlen == 0) return 0;

        var layout_raw: ?*anyopaque = null;
        const hr = dwrite.vtbl.CreateTextLayout(
            @ptrCast(dwrite),
            wbuf[0..wlen].ptr,
            @intCast(wlen),
            @ptrCast(fmt),
            10000.0,
            10000.0,
            &layout_raw,
        );
        if (hr != S_OK or layout_raw == null) return @intCast(text.len * 8);
        const layout: *IDWriteTextLayoutFace = @ptrCast(@alignCast(layout_raw.?));
        defer _ = layout.vtbl.Release(@ptrCast(layout));

        var metrics: DWRITE_TEXT_METRICS = undefined;
        const hr_m = layout.vtbl.GetMetrics(@ptrCast(layout), &metrics);
        if (hr_m != S_OK) return @intCast(text.len * 8);

        // metrics.width is in DIPs. Since D2D coordinate system == logical pixels
        // (we pass logical coords directly), this is already in logical pixels.
        return @intFromFloat(@ceil(metrics.width));
    }

    /// Called by app.zig after drawing to present the frame.
    /// For D2D: calls EndDraw() to flush GPU commands and present.
    /// The `screen_dc` parameter is unused (D2D owns presentation).
    pub fn flushText(self: *Renderer, screen_dc: *anyopaque) void {
        _ = screen_dc;
        if (!self.begin_draw_called) return;
        _ = self.render_target.vtbl.EndDraw(
            @ptrCast(self.render_target),
            null,
            null,
        );
        self.begin_draw_called = false;
        // Present the rendered backbuffer to the window (vsync-synced).
        _ = self.swapchain.vtbl.Present(@ptrCast(self.swapchain), 1, 0);
    }

    /// No-op for D2D (text is drawn inline, no queue).
    pub fn clearTextQueue(self: *Renderer) void {
        _ = self;
    }

    // ── Clip ─────────────────────────────────────────────────────────────────

    pub fn setClip(self: *Renderer, rect: ?Rect) void {
        if (!self.begin_draw_called) return;
        // Pop any existing clip first
        if (self.clip_pushed) {
            self.render_target.vtbl.PopAxisAlignedClip(@ptrCast(self.render_target));
            self.clip_pushed = false;
        }
        const r = rect orelse return;
        const d2d_rect = D2D1_RECT_F{
            .left   = toDip(r.x),
            .top    = toDip(r.y),
            .right  = toDip(r.right()),
            .bottom = toDip(r.bottom()),
        };
        self.render_target.vtbl.PushAxisAlignedClip(
            @ptrCast(self.render_target),
            &d2d_rect,
            D2D1_ANTIALIAS_MODE_PER_PRIMITIVE,
        );
        self.clip_pushed = true;
    }

    pub fn clearClip(self: *Renderer) void {
        if (!self.begin_draw_called) return;
        if (self.clip_pushed) {
            self.render_target.vtbl.PopAxisAlignedClip(@ptrCast(self.render_target));
            self.clip_pushed = false;
        }
    }

    // ── Image drawing ─────────────────────────────────────────────────────────

    pub fn drawImage(self: *Renderer, img: *const Image, dst: Rect) void {
        self.drawImageRaw(img.pixels.ptr, img.width, img.height, dst);
    }

    /// Draw a raw pixel buffer (0xAARRGGBB format) to the render target.
    /// Converts ARGB → BGRA for D2D's native DXGI_FORMAT_B8G8R8A8_UNORM.
    pub fn drawImageRaw(self: *Renderer, pixels: [*]const u32, src_w: u32, src_h: u32, dst: Rect) void {
        if (!self.begin_draw_called) return;
        if (src_w == 0 or src_h == 0) return;

        // Convert 0xAARRGGBB → 0xAABBGGRR (BGRA) for D2D
        // Use a fixed-size stack buffer; for large images fall back to allocating.
        const pixel_count = src_w * src_h;

        // Stack buffer for images up to 512×512 (1 MB). Larger images use the
        // page allocator for a temporary conversion buffer and free it immediately.
        const STACK_MAX: usize = 512 * 512;
        var stack_buf: [STACK_MAX]u32 = undefined;
        const heap_buf: ?[]u32 = if (pixel_count > STACK_MAX)
            std.heap.page_allocator.alloc(u32, pixel_count) catch return
        else
            null;
        defer if (heap_buf) |h| std.heap.page_allocator.free(h);

        const bgra_slice: []u32 = if (heap_buf) |h| h else stack_buf[0..pixel_count];
        for (bgra_slice, 0..pixel_count) |*dst_px, i| {
            const src = pixels[i];
            const a: u32 = (src >> 24) & 0xFF;
            const r: u32 = (src >> 16) & 0xFF;
            const g: u32 = (src >>  8) & 0xFF;
            const b: u32 =  src        & 0xFF;
            dst_px.* = b | (g << 8) | (r << 16) | (a << 24);
        }

        const bitmap_props = D2D1_BITMAP_PROPERTIES{
            .pixelFormat = .{
                .format    = DXGI_FORMAT_B8G8R8A8_UNORM,
                .alphaMode = D2D1_ALPHA_MODE_PREMULTIPLIED,
            },
            .dpiX = 96.0,
            .dpiY = 96.0,
        };

        var bmp_raw: ?*anyopaque = null;
        const hr_bmp = self.render_target.vtbl.CreateBitmap(
            @ptrCast(self.render_target),
            D2D1_SIZE_U{ .width = src_w, .height = src_h },
            @ptrCast(bgra_slice.ptr),
            src_w * 4, // pitch in bytes
            &bitmap_props,
            &bmp_raw,
        );
        if (hr_bmp != S_OK or bmp_raw == null) return;
        const bmp: *ID2D1BitmapFace = @ptrCast(@alignCast(bmp_raw.?));
        defer _ = bmp.vtbl.Release(@ptrCast(bmp));

        const dst_rect = D2D1_RECT_F{
            .left   = toDip(dst.x),
            .top    = toDip(dst.y),
            .right  = toDip(dst.right()),
            .bottom = toDip(dst.bottom()),
        };
        self.render_target.vtbl.DrawBitmap(
            @ptrCast(self.render_target),
            @ptrCast(bmp),
            &dst_rect,
            1.0,
            D2D1_BITMAP_INTERPOLATION_MODE_LINEAR,
            null,
        );
    }

    // ── GPU NV12 video draw ────────────────────────────────────────────────────

    /// Draw a decoded NV12 ID3D11Texture2D (which MUST be on this renderer's D3D11
    /// device — see d3dDevice()) into `dst`, GPU-converting NV12→BGRA via the
    /// VideoProcessor and scaling with D2D. Returns false if the GPU path is
    /// unavailable, so the caller can fall back to the CPU drawImageRaw path.
    pub fn drawNv12(self: *Renderer, nv12_tex: *anyopaque, src_w: u32, src_h: u32, dst: Rect) bool {
        if (!self.begin_draw_called or src_w == 0 or src_h == 0) return false;
        const vp = self.ensureVp(src_w, src_h) orelse return false;

        const ivd = D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC{
            .FourCC = 0,
            .ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D,
            .MipSlice = 0,
            .ArraySlice = 0,
        };
        var iv_raw: ?*anyopaque = null;
        if (vp.video_device.vtbl.CreateVideoProcessorInputView(@ptrCast(vp.video_device), nv12_tex, vp.enumerator, &ivd, &iv_raw) != S_OK or iv_raw == null)
            return false;
        const input_view = iv_raw.?;
        defer relCom(input_view);

        // NV12 input is BT.601 limited (16-235); RGB output full range.
        const cs_in = D3D11_VIDEO_PROCESSOR_COLOR_SPACE{ .bits = 0x10 };
        const cs_out = D3D11_VIDEO_PROCESSOR_COLOR_SPACE{ .bits = 0x00 };
        vp.video_ctx.vtbl.VideoProcessorSetStreamColorSpace(@ptrCast(vp.video_ctx), vp.processor, 0, &cs_in);
        vp.video_ctx.vtbl.VideoProcessorSetOutputColorSpace(@ptrCast(vp.video_ctx), vp.processor, &cs_out);

        var stream = std.mem.zeroes(D3D11_VIDEO_PROCESSOR_STREAM);
        stream.Enable = 1;
        stream.pInputSurface = input_view;
        if (vp.video_ctx.vtbl.VideoProcessorBlt(@ptrCast(vp.video_ctx), vp.processor, vp.out_view, 0, 1, &stream) != S_OK)
            return false;

        const dst_rect = D2D1_RECT_F{
            .left = toDip(dst.x),
            .top = toDip(dst.y),
            .right = toDip(dst.right()),
            .bottom = toDip(dst.bottom()),
        };
        self.render_target.vtbl.DrawBitmap(@ptrCast(self.render_target), @ptrCast(vp.out_bitmap), &dst_rect, 1.0, D2D1_BITMAP_INTERPOLATION_MODE_LINEAR, null);
        return true;
    }

    /// Smoke test: build an NV12 texture on this device, run it through the
    /// VideoProcessor, and draw. Returns true if the whole GPU pipeline succeeded
    /// (verifies the hand-bound VideoProcessor vtbl slots are correct). Must be
    /// called inside a frame (after clear()).
    pub fn nv12SelfTest(self: *Renderer) bool {
        const W: u32 = 64;
        const H: u32 = 64;
        var buf: [W * H + W * H / 2]u8 = undefined;
        @memset(buf[0 .. W * H], 150); // Y
        @memset(buf[W * H ..], 128); // UV (neutral)
        const sub = D3D11_SUBRESOURCE_DATA{ .pSysMem = &buf, .SysMemPitch = W, .SysMemSlicePitch = W * H };
        const tdesc = D3D11_TEXTURE2D_DESC{
            .Width = W,
            .Height = H,
            .MipLevels = 1,
            .ArraySize = 1,
            .Format = DXGI_FORMAT_NV12,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Usage = D3D11_USAGE_DEFAULT,
            .BindFlags = 0, // VideoProcessor input — no SRV/RTV bind needed
            .CPUAccessFlags = 0,
            .MiscFlags = 0,
        };
        var tex_raw: ?*anyopaque = null;
        const dev: *ID3D11DeviceFace = @ptrCast(@alignCast(self.d3d_device));
        if (dev.vtbl.CreateTexture2D(@ptrCast(dev), &tdesc, @ptrCast(&sub), &tex_raw) != S_OK or tex_raw == null) return false;
        defer relCom(tex_raw.?);
        return self.drawNv12(tex_raw.?, W, H, Rect.init(0, 0, W, H));
    }

    fn ensureVp(self: *Renderer, src_w: u32, src_h: u32) ?*VideoNv12 {
        if (self.vp) |*v| {
            if (v.src_w == src_w and v.src_h == src_h) return v;
            self.destroyVp();
        }
        self.vp = buildVp(self.d3d_device, self.d3d_ctx, self.device_context, src_w, src_h) catch return null;
        return &(self.vp.?);
    }

    fn destroyVp(self: *Renderer) void {
        if (self.vp) |v| {
            relCom(v.out_bitmap);
            relCom(v.out_view);
            relCom(v.out_tex);
            relCom(v.processor);
            relCom(v.enumerator);
            relCom(@ptrCast(v.video_ctx));
            relCom(@ptrCast(v.video_device));
            self.vp = null;
        }
    }

    // ── Resize ────────────────────────────────────────────────────────────────

    pub fn resize(self: *Renderer, width: u32, height: u32) void {
        if (width == 0 or height == 0) return;
        // End any outstanding draw before resizing.
        if (self.begin_draw_called) {
            if (self.clip_pushed) {
                self.render_target.vtbl.PopAxisAlignedClip(@ptrCast(self.render_target));
                self.clip_pushed = false;
            }
            _ = self.render_target.vtbl.EndDraw(@ptrCast(self.render_target), null, null);
            self.begin_draw_called = false;
        }
        // The target bitmap holds a reference to the old backbuffer, so it MUST be
        // unbound + released before ResizeBuffers can free/recreate the buffers.
        self.device_context.vtbl.SetTarget(@ptrCast(self.device_context), null);
        if (self.target_bitmap) |b| { relCom(b); self.target_bitmap = null; }
        _ = self.swapchain.vtbl.ResizeBuffers(@ptrCast(self.swapchain), 0, width, height, DXGI_FORMAT_UNKNOWN, 0);
        self.target_bitmap = makeSwapchainTarget(self.swapchain, self.device_context) catch null;
        self.width  = width;
        self.height = height;
    }
};
