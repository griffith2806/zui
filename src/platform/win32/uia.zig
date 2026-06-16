// Windows UI Automation provider.
// Implements IRawElementProviderSimple + Fragment + FragmentRoot via COM vtables.
// UIAutomationCore.dll is loaded dynamically so the app degrades gracefully
// on systems where it is missing (very old Windows).

const std    = @import("std");
const builtin = @import("builtin");
const node_mod = @import("../../accessibility/node.zig");

comptime {
    if (builtin.os.tag != .windows) @compileError("UIA backend is Windows-only");
}

pub const AccessNode = node_mod.AccessNode;
const Role = node_mod.Role;

// ── Win32 primitive types ─────────────────────────────────────────────────────

const HWND    = *anyopaque;
const BOOL    = i32;
const DWORD   = u32;
const ULONG   = u32;
const LONG    = i32;
const WPARAM  = usize;
const LPARAM  = isize;
const LRESULT = isize;
const HRESULT = LONG;
const DOUBLE  = f64;

const winapi = std.builtin.CallingConvention.winapi;

const S_OK:          HRESULT = 0;
const E_NOINTERFACE: HRESULT = @as(HRESULT, @bitCast(@as(u32, 0x80004002)));

// ── GUID ─────────────────────────────────────────────────────────────────────

const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

fn guidEql(a: *const GUID, b: *const GUID) bool {
    return std.mem.eql(u8, std.mem.asBytes(a), std.mem.asBytes(b));
}

const IID_IUnknown = GUID{
    .Data1 = 0x00000000, .Data2 = 0x0000, .Data3 = 0x0000,
    .Data4 = .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
};
const IID_IRawElementProviderSimple = GUID{
    .Data1 = 0xD6DD68D1, .Data2 = 0x86FD, .Data3 = 0x4332,
    .Data4 = .{ 0x86, 0x66, 0x9A, 0xBE, 0xDE, 0xA2, 0xD2, 0x4C },
};
const IID_IRawElementProviderFragment = GUID{
    .Data1 = 0xF7063DA8, .Data2 = 0x8359, .Data3 = 0x439C,
    .Data4 = .{ 0x92, 0x97, 0xBB, 0xC5, 0x29, 0x9A, 0x7D, 0x87 },
};
const IID_IRawElementProviderFragmentRoot = GUID{
    .Data1 = 0x620CE2A5, .Data2 = 0xAB8F, .Data3 = 0x40A9,
    .Data4 = .{ 0x86, 0xCB, 0xDE, 0x3C, 0x75, 0x59, 0x9B, 0x58 },
};

// ── VARIANT ──────────────────────────────────────────────────────────────────

const VT_EMPTY: u16 = 0;
const VT_I4:    u16 = 3;
const VT_BOOL:  u16 = 11;
const VT_BSTR:  u16 = 8;

// 16-byte COM VARIANT.  val covers all data-union members on 64-bit Windows.
const VARIANT = extern struct {
    vt:  u16,
    w1:  u16 = 0,
    w2:  u16 = 0,
    w3:  u16 = 0,
    val: u64 = 0,

    fn empty() VARIANT { return .{ .vt = VT_EMPTY }; }

    fn fromI4(v: i32) VARIANT {
        return .{ .vt = VT_I4, .val = @as(u64, @as(u32, @bitCast(v))) };
    }

    fn fromBool(b: bool) VARIANT {
        const v: i16 = if (b) -1 else 0;
        return .{ .vt = VT_BOOL, .val = @as(u64, @as(u16, @bitCast(v))) };
    }

    fn fromBstr(ptr: ?*u16) VARIANT {
        return .{ .vt = VT_BSTR, .val = @intFromPtr(ptr) };
    }
};

// ── Simple spinlock (std.atomic.Mutex is non-blocking; wrap it) ───────────────

const SpinLock = struct {
    inner: std.atomic.Mutex = .unlocked,

    pub fn lock(self: *SpinLock) void {
        while (!self.inner.tryLock()) std.atomic.spinLoopHint();
    }
    pub fn unlock(self: *SpinLock) void {
        self.inner.unlock();
    }
};

// ── UiaRect ──────────────────────────────────────────────────────────────────

const UiaRect = extern struct {
    left:   DOUBLE,
    top:    DOUBLE,
    width:  DOUBLE,
    height: DOUBLE,
};

// ── SAFEARRAY (opaque — created only via OLE API) ────────────────────────────

const SAFEARRAY = opaque {};

// ── Win32 extern declarations ─────────────────────────────────────────────────

const POINT = extern struct { x: LONG, y: LONG };

extern "oleaut32" fn SysAllocStringLen(psz: [*]const u16, len: u32) callconv(winapi) ?*u16;
extern "oleaut32" fn SysFreeString(bstr: ?*u16) callconv(winapi) void;
extern "oleaut32" fn SafeArrayCreateVector(vt: u16, lLbound: LONG, cElements: ULONG) callconv(winapi) ?*SAFEARRAY;
extern "oleaut32" fn SafeArrayDestroy(psa: *SAFEARRAY) callconv(winapi) HRESULT;
extern "oleaut32" fn SafeArrayAccessData(psa: *SAFEARRAY, ppvData: *?*anyopaque) callconv(winapi) HRESULT;
extern "oleaut32" fn SafeArrayUnaccessData(psa: *SAFEARRAY) callconv(winapi) HRESULT;
extern "user32"   fn ClientToScreen(hWnd: HWND, lpPoint: *POINT) callconv(winapi) BOOL;
extern "kernel32" fn LoadLibraryW(lpLibFileName: [*:0]const u16) callconv(winapi) ?*anyopaque;
extern "kernel32" fn GetProcAddress(hModule: *anyopaque, lpProcName: [*:0]const u8) callconv(winapi) ?*anyopaque;

// ── UIAutomationCore — loaded at runtime ─────────────────────────────────────

const UiaReturnFn = *const fn (HWND, WPARAM, LPARAM, *anyopaque) callconv(winapi) LRESULT;
const UiaHostFn   = *const fn (HWND, *?*anyopaque) callconv(winapi) HRESULT;

var g_UiaReturn: ?UiaReturnFn = null;
var g_UiaHost:   ?UiaHostFn   = null;

pub fn loadUiaFunctions() void {
    const dll = LoadLibraryW(
        std.unicode.utf8ToUtf16LeStringLiteral("UIAutomationCore.dll")
    ) orelse return;
    const r = GetProcAddress(dll, "UiaReturnRawElementProvider") orelse return;
    g_UiaReturn = @ptrCast(r);
    if (GetProcAddress(dll, "UiaHostProviderFromHwnd")) |h|
        g_UiaHost = @ptrCast(h);
}

// ── UIA numeric constants ─────────────────────────────────────────────────────

const NavigateDirection_Parent          : i32 = 0;
const NavigateDirection_NextSibling     : i32 = 1;
const NavigateDirection_PreviousSibling : i32 = 2;
const NavigateDirection_FirstChild      : i32 = 3;
const NavigateDirection_LastChild       : i32 = 4;

const ProviderOptions_ServerSideProvider: i32 = 2;
const ProviderOptions_UseComThreading   : i32 = 32;

const UIA_ButtonControlTypeId     : i32 = 50000;
const UIA_CheckBoxControlTypeId   : i32 = 50002;
const UIA_ComboBoxControlTypeId   : i32 = 50003;
const UIA_EditControlTypeId       : i32 = 50004;
const UIA_GroupControlTypeId      : i32 = 50026;
const UIA_ListControlTypeId       : i32 = 50008;
const UIA_ListItemControlTypeId   : i32 = 50007;
const UIA_MenuControlTypeId       : i32 = 50011;
const UIA_MenuItemControlTypeId   : i32 = 50012;
const UIA_ProgressBarControlTypeId: i32 = 50013;
const UIA_SliderControlTypeId     : i32 = 50016;
const UIA_TabControlTypeId        : i32 = 50018;
const UIA_TabItemControlTypeId    : i32 = 50019;
const UIA_TextControlTypeId       : i32 = 50020;
const UIA_WindowControlTypeId     : i32 = 50032;

const UIA_ControlTypePropertyId         : i32 = 30003;
const UIA_NamePropertyId                : i32 = 30005;
const UIA_HasKeyboardFocusPropertyId    : i32 = 30008;
const UIA_IsKeyboardFocusablePropertyId : i32 = 30009;
const UIA_IsEnabledPropertyId           : i32 = 30010;
const UIA_IsContentElementPropertyId    : i32 = 30017;
const UIA_IsControlElementPropertyId    : i32 = 30016;
const UIA_ValueValuePropertyId          : i32 = 30045;

const UiaAppendRuntimeId: i32 = 3;

// ── COM vtable structs ────────────────────────────────────────────────────────

const SimpleVtbl = extern struct {
    QueryInterface:             *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:                     *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:                    *const fn (*anyopaque) callconv(winapi) ULONG,
    get_ProviderOptions:        *const fn (*anyopaque, *i32) callconv(winapi) HRESULT,
    GetPatternProvider:         *const fn (*anyopaque, i32, *?*anyopaque) callconv(winapi) HRESULT,
    GetPropertyValue:           *const fn (*anyopaque, i32, *VARIANT) callconv(winapi) HRESULT,
    get_HostRawElementProvider: *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
};

const FragmentVtbl = extern struct {
    QueryInterface:           *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:                   *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:                  *const fn (*anyopaque) callconv(winapi) ULONG,
    Navigate:                 *const fn (*anyopaque, i32, *?*anyopaque) callconv(winapi) HRESULT,
    GetRuntimeId:             *const fn (*anyopaque, *?*SAFEARRAY) callconv(winapi) HRESULT,
    get_BoundingRectangle:    *const fn (*anyopaque, *UiaRect) callconv(winapi) HRESULT,
    GetEmbeddedFragmentRoots: *const fn (*anyopaque, *?*SAFEARRAY) callconv(winapi) HRESULT,
    SetFocus:                 *const fn (*anyopaque) callconv(winapi) HRESULT,
    get_FragmentRoot:         *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
};

const RootVtbl = extern struct {
    QueryInterface:           *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:                   *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:                  *const fn (*anyopaque) callconv(winapi) ULONG,
    ElementProviderFromPoint: *const fn (*anyopaque, f64, f64, *?*anyopaque) callconv(winapi) HRESULT,
    GetFocus:                 *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
};

// Sub-interface "face" types — each is just a vtable pointer.
const SimpleFace   = extern struct { vtbl: *const SimpleVtbl };
const FragmentFace = extern struct { vtbl: *const FragmentVtbl };
const RootFace     = extern struct { vtbl: *const RootVtbl };

// ── BSTR helper ───────────────────────────────────────────────────────────────

fn allocBstr(utf8: []const u8) ?*u16 {
    var buf: [512]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&buf, utf8) catch return null;
    if (len == 0) return null;
    return SysAllocStringLen(buf[0..len].ptr, @intCast(len));
}

// ── UIA control-type mapper ───────────────────────────────────────────────────

fn controlType(role: Role) i32 {
    return switch (role) {
        .button       => UIA_ButtonControlTypeId,
        .checkbox     => UIA_CheckBoxControlTypeId,
        .combo_box    => UIA_ComboBoxControlTypeId,
        .text_field   => UIA_EditControlTypeId,
        .text_area    => UIA_EditControlTypeId,
        .container, .group, .scroll_area, .separator => UIA_GroupControlTypeId,
        .list         => UIA_ListControlTypeId,
        .list_item    => UIA_ListItemControlTypeId,
        .menu         => UIA_MenuControlTypeId,
        .menu_item    => UIA_MenuItemControlTypeId,
        .progress_bar => UIA_ProgressBarControlTypeId,
        .slider       => UIA_SliderControlTypeId,
        .tab          => UIA_TabControlTypeId,
        .tab_panel    => UIA_TabItemControlTypeId,
        .label        => UIA_TextControlTypeId,
        .window       => UIA_WindowControlTypeId,
    };
}

fn isKeyboardFocusable(role: Role) bool {
    return switch (role) {
        .button, .checkbox, .text_field, .text_area,
        .slider, .list, .combo_box, .tab => true,
        else => false,
    };
}

// ── screenBounds — convert logical client rect to screen physical pixels ──────

fn screenBounds(hwnd: HWND, bounds: Rect, dpi: f32) UiaRect {
    const px = @as(LONG, @intFromFloat(@round(@as(f32, @floatFromInt(bounds.x)) * dpi)));
    const py = @as(LONG, @intFromFloat(@round(@as(f32, @floatFromInt(bounds.y)) * dpi)));
    const pw = @as(LONG, @intFromFloat(@round(@as(f32, @floatFromInt(bounds.width))  * dpi)));
    const ph = @as(LONG, @intFromFloat(@round(@as(f32, @floatFromInt(bounds.height)) * dpi)));
    var tl = POINT{ .x = px,      .y = py };
    var br = POINT{ .x = px + pw, .y = py + ph };
    _ = ClientToScreen(hwnd, &tl);
    _ = ClientToScreen(hwnd, &br);
    return .{
        .left   = @floatFromInt(tl.x),
        .top    = @floatFromInt(tl.y),
        .width  = @floatFromInt(br.x - tl.x),
        .height = @floatFromInt(br.y - tl.y),
    };
}

const Rect = @import("../../layout/geometry.zig").Rect;

// ── makeRuntimeId ─────────────────────────────────────────────────────────────

fn makeRuntimeId(index: u32) ?*SAFEARRAY {
    const sa = SafeArrayCreateVector(3, 0, 2) orelse return null; // VT_I4 = 3
    var raw: ?*anyopaque = null;
    _ = SafeArrayAccessData(sa, &raw);
    if (raw) |d| {
        const ints: *[2]i32 = @ptrCast(@alignCast(d));
        ints[0] = UiaAppendRuntimeId;
        ints[1] = @intCast(index);
    }
    _ = SafeArrayUnaccessData(sa);
    return sa;
}

// ══════════════════════════════════════════════════════════════════════════════
// Forward declaration — WidgetProvider references UiaTree, UiaTree references
// WindowProvider.  Both reference each other via pointer only.
// ══════════════════════════════════════════════════════════════════════════════

pub const UiaTree = struct {
    alloc:            std.mem.Allocator,
    hwnd:             HWND,
    dpi_scale:        f32,
    window_provider:  *WindowProvider,
    widget_providers: std.ArrayListUnmanaged(*WidgetProvider),
    mutex:            SpinLock,

    pub fn create(
        alloc: std.mem.Allocator,
        hwnd:  HWND,
        dpi:   f32,
        title: []const u8,
    ) !*UiaTree {
        const tree = try alloc.create(UiaTree);
        tree.* = .{
            .alloc            = alloc,
            .hwnd             = hwnd,
            .dpi_scale        = dpi,
            .window_provider  = undefined,
            .widget_providers = .empty,
            .mutex            = .{},
        };
        tree.window_provider = try WindowProvider.create(alloc, hwnd, dpi, title, tree);
        return tree;
    }

    pub fn destroy(self: *UiaTree) void {
        self.mutex.lock();
        for (self.widget_providers.items) |wp| {
            _ = wp.releaseSelf();
        }
        self.widget_providers.deinit(self.alloc);
        self.mutex.unlock();
        self.alloc.destroy(self.window_provider);
        self.alloc.destroy(self);
    }

    pub fn update(self: *UiaTree, nodes: []const AccessNode) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.widget_providers.items) |wp| {
            _ = wp.releaseSelf();
        }
        self.widget_providers.clearRetainingCapacity();
        for (nodes, 0..) |node, i| {
            const wp = WidgetProvider.create(
                self.alloc, node, @intCast(i), self, self.hwnd, self.dpi_scale,
            ) catch continue;
            self.widget_providers.append(self.alloc, wp) catch {
                _ = wp.releaseSelf();
                continue;
            };
        }
    }

    pub fn getWindowProvider(self: *UiaTree) *anyopaque {
        return @ptrCast(&self.window_provider.simple);
    }
};

// ══════════════════════════════════════════════════════════════════════════════
// WidgetProvider — IRawElementProviderSimple + IRawElementProviderFragment
// ══════════════════════════════════════════════════════════════════════════════

pub const WidgetProvider = struct {
    simple:    SimpleFace,   // offset 0 — canonical IUnknown
    fragment:  FragmentFace, // offset 8
    ref_count: std.atomic.Value(u32),
    alloc:     std.mem.Allocator,
    node:      AccessNode,
    index:     u32,
    tree:      *UiaTree,
    hwnd:      HWND,
    dpi_scale: f32,

    // ── Struct recovery from sub-interface pointer ────────────────────────────

    fn fromSimple(p: *anyopaque) *WidgetProvider {
        return @fieldParentPtr("simple", @as(*SimpleFace, @ptrCast(@alignCast(p))));
    }
    fn fromFragment(p: *anyopaque) *WidgetProvider {
        return @fieldParentPtr("fragment", @as(*FragmentFace, @ptrCast(@alignCast(p))));
    }

    pub fn addRefSelf(self: *WidgetProvider) ULONG {
        return self.ref_count.fetchAdd(1, .monotonic) + 1;
    }
    pub fn releaseSelf(self: *WidgetProvider) ULONG {
        const prev = self.ref_count.fetchSub(1, .monotonic);
        if (prev == 1) self.alloc.destroy(self);
        return prev - 1;
    }

    // ── Simple vtable methods ─────────────────────────────────────────────────

    fn sQI(p: *anyopaque, riid: *const GUID, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const self = fromSimple(p);
        if (guidEql(riid, &IID_IUnknown) or guidEql(riid, &IID_IRawElementProviderSimple)) {
            ppv.* = p;
        } else if (guidEql(riid, &IID_IRawElementProviderFragment)) {
            ppv.* = @ptrCast(&self.fragment);
        } else {
            ppv.* = null; return E_NOINTERFACE;
        }
        _ = self.addRefSelf();
        return S_OK;
    }
    fn sAddRef(p: *anyopaque) callconv(winapi) ULONG  { return fromSimple(p).addRefSelf(); }
    fn sRelease(p: *anyopaque) callconv(winapi) ULONG { return fromSimple(p).releaseSelf(); }

    fn sProviderOptions(_: *anyopaque, pRet: *i32) callconv(winapi) HRESULT {
        pRet.* = ProviderOptions_ServerSideProvider;
        return S_OK;
    }
    fn sGetPatternProvider(_: *anyopaque, _: i32, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        ppv.* = null; return S_OK;
    }
    fn sGetPropertyValue(p: *anyopaque, propId: i32, pRet: *VARIANT) callconv(winapi) HRESULT {
        const self = fromSimple(p);
        pRet.* = switch (propId) {
            UIA_NamePropertyId => VARIANT.fromBstr(allocBstr(self.node.name)),
            UIA_ControlTypePropertyId         => VARIANT.fromI4(controlType(self.node.role)),
            UIA_IsEnabledPropertyId           => VARIANT.fromBool(self.node.state.enabled),
            UIA_HasKeyboardFocusPropertyId    => VARIANT.fromBool(self.node.state.focused),
            UIA_IsKeyboardFocusablePropertyId => VARIANT.fromBool(isKeyboardFocusable(self.node.role)),
            UIA_IsContentElementPropertyId    => VARIANT.fromBool(true),
            UIA_IsControlElementPropertyId    => VARIANT.fromBool(true),
            UIA_ValueValuePropertyId => blk: {
                if (self.node.value.len == 0) break :blk VARIANT.empty();
                break :blk VARIANT.fromBstr(allocBstr(self.node.value));
            },
            else => VARIANT.empty(),
        };
        return S_OK;
    }
    fn sHostProvider(_: *anyopaque, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        ppv.* = null; return S_OK;
    }

    // ── Fragment vtable methods ───────────────────────────────────────────────

    fn fQI(p: *anyopaque, riid: *const GUID, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const self = fromFragment(p);
        if (guidEql(riid, &IID_IUnknown) or guidEql(riid, &IID_IRawElementProviderSimple)) {
            ppv.* = @ptrCast(&self.simple);
        } else if (guidEql(riid, &IID_IRawElementProviderFragment)) {
            ppv.* = p;
        } else {
            ppv.* = null; return E_NOINTERFACE;
        }
        _ = self.addRefSelf();
        return S_OK;
    }
    fn fAddRef(p: *anyopaque) callconv(winapi) ULONG  { return fromFragment(p).addRefSelf(); }
    fn fRelease(p: *anyopaque) callconv(winapi) ULONG { return fromFragment(p).releaseSelf(); }

    fn fNavigate(p: *anyopaque, dir: i32, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const self = fromFragment(p);
        ppv.* = null;
        const tree = self.tree;
        tree.mutex.lock();
        defer tree.mutex.unlock();
        switch (dir) {
            NavigateDirection_Parent => {
                _ = tree.window_provider.addRefSelf();
                ppv.* = @ptrCast(&tree.window_provider.fragment);
            },
            NavigateDirection_NextSibling => {
                const next = self.index + 1;
                if (next < tree.widget_providers.items.len) {
                    const wp = tree.widget_providers.items[next];
                    _ = wp.addRefSelf();
                    ppv.* = @ptrCast(&wp.fragment);
                }
            },
            NavigateDirection_PreviousSibling => {
                if (self.index > 0) {
                    const wp = tree.widget_providers.items[self.index - 1];
                    _ = wp.addRefSelf();
                    ppv.* = @ptrCast(&wp.fragment);
                }
            },
            else => {},
        }
        return S_OK;
    }

    fn fGetRuntimeId(p: *anyopaque, ppSA: *?*SAFEARRAY) callconv(winapi) HRESULT {
        const self = fromFragment(p);
        ppSA.* = makeRuntimeId(self.index);
        return S_OK;
    }

    fn fGetBoundingRect(p: *anyopaque, pRect: *UiaRect) callconv(winapi) HRESULT {
        const self = fromFragment(p);
        pRect.* = screenBounds(self.hwnd, self.node.bounds, self.dpi_scale);
        return S_OK;
    }

    fn fGetEmbeddedRoots(_: *anyopaque, ppSA: *?*SAFEARRAY) callconv(winapi) HRESULT {
        ppSA.* = null; return S_OK;
    }
    fn fSetFocus(_: *anyopaque) callconv(winapi) HRESULT { return S_OK; }

    fn fGetFragmentRoot(p: *anyopaque, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const self = fromFragment(p);
        _ = self.tree.window_provider.addRefSelf();
        ppv.* = @ptrCast(&self.tree.window_provider.root);
        return S_OK;
    }

    // ── Static vtable instances ───────────────────────────────────────────────

    const s_simple_vtbl = SimpleVtbl{
        .QueryInterface             = sQI,
        .AddRef                     = sAddRef,
        .Release                    = sRelease,
        .get_ProviderOptions        = sProviderOptions,
        .GetPatternProvider         = sGetPatternProvider,
        .GetPropertyValue           = sGetPropertyValue,
        .get_HostRawElementProvider = sHostProvider,
    };
    const s_fragment_vtbl = FragmentVtbl{
        .QueryInterface           = fQI,
        .AddRef                   = fAddRef,
        .Release                  = fRelease,
        .Navigate                 = fNavigate,
        .GetRuntimeId             = fGetRuntimeId,
        .get_BoundingRectangle    = fGetBoundingRect,
        .GetEmbeddedFragmentRoots = fGetEmbeddedRoots,
        .SetFocus                 = fSetFocus,
        .get_FragmentRoot         = fGetFragmentRoot,
    };

    pub fn create(
        alloc:     std.mem.Allocator,
        node:      AccessNode,
        index:     u32,
        tree:      *UiaTree,
        hwnd:      HWND,
        dpi_scale: f32,
    ) !*WidgetProvider {
        const self = try alloc.create(WidgetProvider);
        self.* = .{
            .simple    = .{ .vtbl = &s_simple_vtbl },
            .fragment  = .{ .vtbl = &s_fragment_vtbl },
            .ref_count = .init(1),
            .alloc     = alloc,
            .node      = node,
            .index     = index,
            .tree      = tree,
            .hwnd      = hwnd,
            .dpi_scale = dpi_scale,
        };
        return self;
    }
};

// ══════════════════════════════════════════════════════════════════════════════
// WindowProvider — Simple + Fragment + FragmentRoot
// ══════════════════════════════════════════════════════════════════════════════

pub const WindowProvider = struct {
    simple:    SimpleFace,   // offset 0
    fragment:  FragmentFace, // offset 8
    root:      RootFace,     // offset 16
    ref_count: std.atomic.Value(u32),
    alloc:     std.mem.Allocator,
    hwnd:      HWND,
    dpi_scale: f32,
    tree:      *UiaTree,
    title:     []const u8,

    fn fromSimple(p: *anyopaque) *WindowProvider {
        return @fieldParentPtr("simple", @as(*SimpleFace, @ptrCast(@alignCast(p))));
    }
    fn fromFragment(p: *anyopaque) *WindowProvider {
        return @fieldParentPtr("fragment", @as(*FragmentFace, @ptrCast(@alignCast(p))));
    }
    fn fromRoot(p: *anyopaque) *WindowProvider {
        return @fieldParentPtr("root", @as(*RootFace, @ptrCast(@alignCast(p))));
    }

    pub fn addRefSelf(self: *WindowProvider) ULONG {
        return self.ref_count.fetchAdd(1, .monotonic) + 1;
    }
    fn releaseSelf(self: *WindowProvider) ULONG {
        return self.ref_count.fetchSub(1, .monotonic) - 1;
        // WindowProvider is owned by UiaTree — no heap free here
    }

    // ── Simple ───────────────────────────────────────────────────────────────

    fn wsQI(p: *anyopaque, riid: *const GUID, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const self = fromSimple(p);
        if (guidEql(riid, &IID_IUnknown) or guidEql(riid, &IID_IRawElementProviderSimple)) {
            ppv.* = p;
        } else if (guidEql(riid, &IID_IRawElementProviderFragment)) {
            ppv.* = @ptrCast(&self.fragment);
        } else if (guidEql(riid, &IID_IRawElementProviderFragmentRoot)) {
            ppv.* = @ptrCast(&self.root);
        } else {
            ppv.* = null; return E_NOINTERFACE;
        }
        _ = self.addRefSelf();
        return S_OK;
    }
    fn wsAddRef(p: *anyopaque) callconv(winapi) ULONG  { return fromSimple(p).addRefSelf(); }
    fn wsRelease(p: *anyopaque) callconv(winapi) ULONG { return fromSimple(p).releaseSelf(); }

    fn wsProviderOptions(_: *anyopaque, pRet: *i32) callconv(winapi) HRESULT {
        pRet.* = ProviderOptions_ServerSideProvider;
        return S_OK;
    }
    fn wsGetPatternProvider(_: *anyopaque, _: i32, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        ppv.* = null; return S_OK;
    }
    fn wsGetPropertyValue(p: *anyopaque, propId: i32, pRet: *VARIANT) callconv(winapi) HRESULT {
        const self = fromSimple(p);
        pRet.* = switch (propId) {
            UIA_NamePropertyId            => VARIANT.fromBstr(allocBstr(self.title)),
            UIA_ControlTypePropertyId     => VARIANT.fromI4(UIA_WindowControlTypeId),
            UIA_IsEnabledPropertyId       => VARIANT.fromBool(true),
            UIA_IsContentElementPropertyId => VARIANT.fromBool(true),
            UIA_IsControlElementPropertyId => VARIANT.fromBool(true),
            else => VARIANT.empty(),
        };
        return S_OK;
    }
    fn wsHostProvider(p: *anyopaque, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const self = fromSimple(p);
        if (g_UiaHost) |fn_host| { _ = fn_host(self.hwnd, ppv); }
        else { ppv.* = null; }
        return S_OK;
    }

    // ── Fragment ─────────────────────────────────────────────────────────────

    fn wfQI(p: *anyopaque, riid: *const GUID, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const self = fromFragment(p);
        if (guidEql(riid, &IID_IUnknown) or guidEql(riid, &IID_IRawElementProviderSimple)) {
            ppv.* = @ptrCast(&self.simple);
        } else if (guidEql(riid, &IID_IRawElementProviderFragment)) {
            ppv.* = p;
        } else if (guidEql(riid, &IID_IRawElementProviderFragmentRoot)) {
            ppv.* = @ptrCast(&self.root);
        } else {
            ppv.* = null; return E_NOINTERFACE;
        }
        _ = self.addRefSelf();
        return S_OK;
    }
    fn wfAddRef(p: *anyopaque) callconv(winapi) ULONG  { return fromFragment(p).addRefSelf(); }
    fn wfRelease(p: *anyopaque) callconv(winapi) ULONG { return fromFragment(p).releaseSelf(); }

    fn wfNavigate(p: *anyopaque, dir: i32, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const self = fromFragment(p);
        ppv.* = null;
        const tree = self.tree;
        tree.mutex.lock();
        defer tree.mutex.unlock();
        const items = tree.widget_providers.items;
        switch (dir) {
            NavigateDirection_FirstChild => {
                if (items.len > 0) {
                    _ = items[0].addRefSelf();
                    ppv.* = @ptrCast(&items[0].fragment);
                }
            },
            NavigateDirection_LastChild => {
                if (items.len > 0) {
                    _ = items[items.len - 1].addRefSelf();
                    ppv.* = @ptrCast(&items[items.len - 1].fragment);
                }
            },
            else => {},
        }
        return S_OK;
    }
    fn wfGetRuntimeId(_: *anyopaque, ppSA: *?*SAFEARRAY) callconv(winapi) HRESULT {
        ppSA.* = null; return S_OK; // root: system assigns
    }
    fn wfGetBoundingRect(_: *anyopaque, pRect: *UiaRect) callconv(winapi) HRESULT {
        pRect.* = .{ .left = 0, .top = 0, .width = 0, .height = 0 }; return S_OK;
    }
    fn wfGetEmbeddedRoots(_: *anyopaque, ppSA: *?*SAFEARRAY) callconv(winapi) HRESULT {
        ppSA.* = null; return S_OK;
    }
    fn wfSetFocus(_: *anyopaque) callconv(winapi) HRESULT { return S_OK; }
    fn wfGetFragmentRoot(p: *anyopaque, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const self = fromFragment(p);
        _ = self.addRefSelf();
        ppv.* = @ptrCast(&self.root);
        return S_OK;
    }

    // ── Root ─────────────────────────────────────────────────────────────────

    fn wrQI(p: *anyopaque, riid: *const GUID, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const self = fromRoot(p);
        if (guidEql(riid, &IID_IUnknown) or guidEql(riid, &IID_IRawElementProviderSimple)) {
            ppv.* = @ptrCast(&self.simple);
        } else if (guidEql(riid, &IID_IRawElementProviderFragment)) {
            ppv.* = @ptrCast(&self.fragment);
        } else if (guidEql(riid, &IID_IRawElementProviderFragmentRoot)) {
            ppv.* = p;
        } else {
            ppv.* = null; return E_NOINTERFACE;
        }
        _ = self.addRefSelf();
        return S_OK;
    }
    fn wrAddRef(p: *anyopaque) callconv(winapi) ULONG  { return fromRoot(p).addRefSelf(); }
    fn wrRelease(p: *anyopaque) callconv(winapi) ULONG { return fromRoot(p).releaseSelf(); }

    fn wrElementProviderFromPoint(p: *anyopaque, x: f64, y: f64, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const self = fromRoot(p);
        ppv.* = null;
        const tree = self.tree;
        tree.mutex.lock();
        defer tree.mutex.unlock();
        for (tree.widget_providers.items) |wp| {
            const r = screenBounds(self.hwnd, wp.node.bounds, self.dpi_scale);
            if (x >= r.left and x < r.left + r.width and
                y >= r.top  and y < r.top  + r.height)
            {
                _ = wp.addRefSelf();
                ppv.* = @ptrCast(&wp.fragment);
                return S_OK;
            }
        }
        return S_OK;
    }

    fn wrGetFocus(p: *anyopaque, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const self = fromRoot(p);
        ppv.* = null;
        const tree = self.tree;
        tree.mutex.lock();
        defer tree.mutex.unlock();
        for (tree.widget_providers.items) |wp| {
            if (wp.node.state.focused) {
                _ = wp.addRefSelf();
                ppv.* = @ptrCast(&wp.fragment);
                return S_OK;
            }
        }
        return S_OK;
    }

    // ── Static vtable instances ───────────────────────────────────────────────

    const s_simple_vtbl = SimpleVtbl{
        .QueryInterface             = wsQI,
        .AddRef                     = wsAddRef,
        .Release                    = wsRelease,
        .get_ProviderOptions        = wsProviderOptions,
        .GetPatternProvider         = wsGetPatternProvider,
        .GetPropertyValue           = wsGetPropertyValue,
        .get_HostRawElementProvider = wsHostProvider,
    };
    const s_fragment_vtbl = FragmentVtbl{
        .QueryInterface           = wfQI,
        .AddRef                   = wfAddRef,
        .Release                  = wfRelease,
        .Navigate                 = wfNavigate,
        .GetRuntimeId             = wfGetRuntimeId,
        .get_BoundingRectangle    = wfGetBoundingRect,
        .GetEmbeddedFragmentRoots = wfGetEmbeddedRoots,
        .SetFocus                 = wfSetFocus,
        .get_FragmentRoot         = wfGetFragmentRoot,
    };
    const s_root_vtbl = RootVtbl{
        .QueryInterface           = wrQI,
        .AddRef                   = wrAddRef,
        .Release                  = wrRelease,
        .ElementProviderFromPoint = wrElementProviderFromPoint,
        .GetFocus                 = wrGetFocus,
    };

    pub fn create(
        alloc:  std.mem.Allocator,
        hwnd:   HWND,
        dpi:    f32,
        title:  []const u8,
        tree:   *UiaTree,
    ) !*WindowProvider {
        const self = try alloc.create(WindowProvider);
        self.* = .{
            .simple    = .{ .vtbl = &s_simple_vtbl },
            .fragment  = .{ .vtbl = &s_fragment_vtbl },
            .root      = .{ .vtbl = &s_root_vtbl },
            .ref_count = .init(1),
            .alloc     = alloc,
            .hwnd      = hwnd,
            .dpi_scale = dpi,
            .tree      = tree,
            .title     = title,
        };
        return self;
    }
};

// ── Public helper — call from WM_GETOBJECT handler ────────────────────────────

pub fn handleGetObject(
    tree: *UiaTree,
    hwnd: HWND,
    wp:   WPARAM,
    lp:   LPARAM,
) LRESULT {
    // UiaRootObjectId (-25) is the correct ID for UIA native clients.
    // OBJID_CLIENT (-4) is the MSAA-bridge path; handle both.
    const UIA_ROOT:    LPARAM = -25;
    const OBJID_CLIENT: LPARAM = -4;
    if (lp != UIA_ROOT and lp != OBJID_CLIENT) return 0;
    const fn_ret = g_UiaReturn orelse return 0;
    return fn_ret(hwnd, wp, lp, tree.getWindowProvider());
}
