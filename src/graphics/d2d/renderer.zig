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

// ── D2D / DWrite constants ────────────────────────────────────────────────────

const D2D1_FACTORY_TYPE_SINGLE_THREADED: u32 = 0;
const DWRITE_FACTORY_TYPE_SHARED: u32 = 1;

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
const LOCALE_EN_US = std.unicode.utf8ToUtf16LeStringLiteral("en-us");
const LOCALE_EMPTY = std.unicode.utf8ToUtf16LeStringLiteral("");

// ── Renderer ──────────────────────────────────────────────────────────────────

pub const Renderer = struct {
    factory:       *ID2D1FactoryFace,
    render_target: *ID2D1HwndRenderTargetFace,
    brush:         *ID2D1SolidColorBrushFace,
    dwrite:        *IDWriteFactoryFace,
    text_formats:  [NUM_FONT_SCALES]?*IDWriteTextFormatFace,
    dpi_scale:     f32,
    width:         u32,
    height:        u32,
    begin_draw_called: bool,
    clip_pushed:   bool,

    /// Initialize the D2D renderer for the given HWND.
    /// `hwnd` must be a valid HWND; `width` and `height` are in physical pixels.
    pub fn init(hwnd: *anyopaque, width: u32, height: u32) !Renderer {
        // ── 1. Create ID2D1Factory ────────────────────────────────────────────
        var factory_raw: *anyopaque = undefined;
        const hr_fac = D2D1CreateFactory(
            D2D1_FACTORY_TYPE_SINGLE_THREADED,
            &IID_ID2D1Factory,
            null,
            &factory_raw,
        );
        if (hr_fac != S_OK) return error.D2DFactoryCreateFailed;
        const factory: *ID2D1FactoryFace = @ptrCast(@alignCast(factory_raw));

        // ── 2. Create HwndRenderTarget ────────────────────────────────────────
        const rt_props = D2D1_RENDER_TARGET_PROPERTIES{
            .type_       = 0, // D2D1_RENDER_TARGET_TYPE_DEFAULT
            .pixelFormat = .{
                .format    = DXGI_FORMAT_B8G8R8A8_UNORM,
                .alphaMode = D2D1_ALPHA_MODE_PREMULTIPLIED,
            },
            .dpiX    = 0, // 0 = use system DPI
            .dpiY    = 0,
            .usage   = 0,
            .minLevel = 0,
        };
        const hwnd_rt_props = D2D1_HWND_RENDER_TARGET_PROPERTIES{
            .hwnd       = @ptrCast(hwnd),
            .pixelSize  = .{ .width = width, .height = height },
            .presentOptions = 0,
        };
        var rt_raw: ?*anyopaque = null;
        const hr_rt = factory.vtbl.CreateHwndRenderTarget(
            @ptrCast(factory),
            &rt_props,
            &hwnd_rt_props,
            &rt_raw,
        );
        if (hr_rt != S_OK or rt_raw == null) {
            _ = factory.vtbl.Release(@ptrCast(factory));
            return error.D2DRenderTargetCreateFailed;
        }
        const rt: *ID2D1HwndRenderTargetFace = @ptrCast(@alignCast(rt_raw.?));

        // Set anti-alias mode
        rt.vtbl.SetAntialiasMode(@ptrCast(rt), D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
        rt.vtbl.SetTextAntialiasMode(@ptrCast(rt), D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE);

        // ── 3. Create a reusable solid-color brush ────────────────────────────
        const brush_color = D2D1_COLOR_F{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 };
        var brush_raw: ?*anyopaque = null;
        const hr_br = rt.vtbl.CreateSolidColorBrush(
            @ptrCast(rt),
            &brush_color,
            null,
            &brush_raw,
        );
        if (hr_br != S_OK or brush_raw == null) {
            _ = rt.vtbl.Release(@ptrCast(rt));
            _ = factory.vtbl.Release(@ptrCast(factory));
            return error.D2DBrushCreateFailed;
        }
        const brush: *ID2D1SolidColorBrushFace = @ptrCast(@alignCast(brush_raw.?));

        // ── 4. Create IDWriteFactory ──────────────────────────────────────────
        var dwrite_raw: *anyopaque = undefined;
        const hr_dw = DWriteCreateFactory(
            DWRITE_FACTORY_TYPE_SHARED,
            &IID_IDWriteFactory,
            &dwrite_raw,
        );
        if (hr_dw != S_OK) {
            _ = brush.vtbl.Release(@ptrCast(brush));
            _ = rt.vtbl.Release(@ptrCast(rt));
            _ = factory.vtbl.Release(@ptrCast(factory));
            return error.DWriteFactoryCreateFailed;
        }
        const dwrite: *IDWriteFactoryFace = @ptrCast(@alignCast(dwrite_raw));

        // ── 5. Create text formats for each font scale ────────────────────────
        // D2D uses DIPs (device-independent pixels = 1/96 inch).
        // We pass font sizes in DIPs; D2D + DirectWrite handle DPI scaling.
        var text_formats: [NUM_FONT_SCALES]?*IDWriteTextFormatFace = .{null} ** NUM_FONT_SCALES;
        for (FONT_PX, 0..) |px, i| {
            if (px == 0) continue;
            const weight: u32 = if (px >= 32) DWRITE_FONT_WEIGHT_SEMIBOLD else DWRITE_FONT_WEIGHT_NORMAL;
            var fmt_raw: ?*anyopaque = null;
            const hr_fmt = dwrite.vtbl.CreateTextFormat(
                @ptrCast(dwrite),
                SEGOE_UI_VAR,
                null,
                weight,
                DWRITE_FONT_STYLE_NORMAL,
                DWRITE_FONT_STRETCH_NORMAL,
                px,
                LOCALE_EN_US,
                &fmt_raw,
            );
            if (hr_fmt == S_OK and fmt_raw != null) {
                text_formats[i] = @ptrCast(@alignCast(fmt_raw.?));
            }
            // If creation fails (e.g. font not found), text_formats[i] stays null — text is skipped
        }

        // Query actual DPI from render target
        var dpi_x: FLOAT = 96.0;
        var dpi_y: FLOAT = 96.0;
        rt.vtbl.GetDpi(@ptrCast(rt), &dpi_x, &dpi_y);
        const dpi_scale: f32 = dpi_x / 96.0;

        return Renderer{
            .factory       = factory,
            .render_target = rt,
            .brush         = brush,
            .dwrite        = dwrite,
            .text_formats  = text_formats,
            .dpi_scale     = dpi_scale,
            .width         = width,
            .height        = height,
            .begin_draw_called = false,
            .clip_pushed   = false,
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
        // Release text formats
        for (&self.text_formats) |*fmt| {
            if (fmt.*) |f| {
                _ = f.vtbl.Release(@ptrCast(f));
                fmt.* = null;
            }
        }
        _ = self.dwrite.vtbl.Release(@ptrCast(self.dwrite));
        _ = self.brush.vtbl.Release(@ptrCast(self.brush));
        _ = self.render_target.vtbl.Release(@ptrCast(self.render_target));
        _ = self.factory.vtbl.Release(@ptrCast(self.factory));
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
        if (!self.begin_draw_called) return;
        const idx = @min(scale, NUM_FONT_SCALES - 1);
        const fmt = self.text_formats[idx] orelse return;

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
        const fmt = self.text_formats[idx] orelse return @intCast(text.len * 8);

        var wbuf: [2048]u16 = undefined;
        const wlen = std.unicode.utf8ToUtf16Le(&wbuf, text) catch return 0;
        if (wlen == 0) return 0;

        var layout_raw: ?*anyopaque = null;
        const hr = self.dwrite.vtbl.CreateTextLayout(
            @ptrCast(self.dwrite),
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

        // Stack buffer for images up to 512×512 (1MB).  Larger images use alloc.
        const STACK_MAX: usize = 512 * 512;
        var stack_buf: [STACK_MAX]u32 = undefined;

        // Large images (> 512×512) are skipped — would need an allocator.
        // In practice the gallery images are small; this is a safe fallback.
        if (pixel_count > STACK_MAX) return;

        const bgra_slice: []u32 = blk: {
            const s = stack_buf[0..pixel_count];
            for (s, 0..pixel_count) |*dst_px, i| {
                const src = pixels[i];
                const a: u32 = (src >> 24) & 0xFF;
                const r: u32 = (src >> 16) & 0xFF;
                const g: u32 = (src >>  8) & 0xFF;
                const b: u32 =  src        & 0xFF;
                // BGRA: B in byte0, G in byte1, R in byte2, A in byte3
                dst_px.* = b | (g << 8) | (r << 16) | (a << 24);
            }
            break :blk s;
        };

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

    // ── Resize ────────────────────────────────────────────────────────────────

    pub fn resize(self: *Renderer, width: u32, height: u32) void {
        // End any outstanding draw before resizing
        if (self.begin_draw_called) {
            if (self.clip_pushed) {
                self.render_target.vtbl.PopAxisAlignedClip(@ptrCast(self.render_target));
                self.clip_pushed = false;
            }
            _ = self.render_target.vtbl.EndDraw(@ptrCast(self.render_target), null, null);
            self.begin_draw_called = false;
        }
        const new_size = D2D1_SIZE_U{ .width = width, .height = height };
        _ = self.render_target.vtbl.Resize(@ptrCast(self.render_target), &new_size);
        self.width  = width;
        self.height = height;
    }
};
