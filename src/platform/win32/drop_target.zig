// Win32 IDropTarget implementation for zui.
//
// Registers each window as a COM drop target so files and text can be dragged
// into it from the shell or other applications.
//
// Memory model
// ──────────────
// A single ArenaAllocator is embedded in each DropTarget instance. It is reset
// at the start of every DragEnter call so that the previous payload's memory is
// recycled. DragPayload slices returned through the event queue point into this
// arena; callers must copy any data they want to outlive the next event poll.

const std    = @import("std");
const builtin = @import("builtin");
const event_mod = @import("../../events/event.zig");

comptime {
    if (builtin.os.tag != .windows) @compileError("drop_target.zig is Windows-only");
}

const Event        = event_mod.Event;
const DragPayload  = event_mod.DragPayload;
const DragPosition = event_mod.DragPosition;

// ── Win32 primitive types ──────────────────────────────────────────────────────

// Use *anyopaque for HWND so it is compatible across compilation units.
// (Two different `*opaque {}` declarations produce different types in Zig.)
const HWND    = *anyopaque;
const BOOL    = i32;
const DWORD   = u32;
const ULONG   = u32;
const LONG    = i32;
const HRESULT = LONG;
const POINT   = extern struct { x: LONG, y: LONG };

const winapi = std.builtin.CallingConvention.winapi;

const S_OK:          HRESULT = 0;
const E_NOINTERFACE: HRESULT = @as(HRESULT, @bitCast(@as(u32, 0x80004002)));

// DROPEFFECT constants
const DROPEFFECT_NONE: DWORD = 0;
const DROPEFFECT_COPY: DWORD = 1;

// Clipboard format IDs — pre-registered; fixed values on all Windows versions.
const CF_UNICODETEXT: DWORD = 13;
const CF_HDROP:       DWORD = 15;

// ── GUID ──────────────────────────────────────────────────────────────────────

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
const IID_IDropTarget = GUID{
    .Data1 = 0x00000122, .Data2 = 0x0000, .Data3 = 0x0000,
    .Data4 = .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
};

// ── FORMATETC / STGMEDIUM (minimal subset needed for GetData) ─────────────────

// DVASPECT_CONTENT
const DVASPECT_CONTENT: LONG = 1;
// TYMED_HGLOBAL
const TYMED_HGLOBAL: DWORD = 1;

const FORMATETC = extern struct {
    cfFormat: DWORD,
    ptd:      ?*anyopaque,   // DVTARGETDEVICE* — always null for us
    dwAspect: LONG,
    lindex:   LONG,
    tymed:    DWORD,
};

const STGMEDIUM = extern struct {
    tymed:          DWORD,
    u:              usize,   // union { HGLOBAL hGlobal; ... } — we use the HGLOBAL path
    pUnkForRelease: ?*anyopaque,
};

// ── IDataObject vtable (only GetData needed; rest are stubs) ──────────────────

const IDataObjectVtbl = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    GetData:        *const fn (*anyopaque, *const FORMATETC, *STGMEDIUM) callconv(winapi) HRESULT,
    GetDataHere:    *const fn (*anyopaque, *const FORMATETC, *STGMEDIUM) callconv(winapi) HRESULT,
    QueryGetData:   *const fn (*anyopaque, *const FORMATETC) callconv(winapi) HRESULT,
    GetCanonicalFormatEtc: *const fn (*anyopaque, *const FORMATETC, *FORMATETC) callconv(winapi) HRESULT,
    SetData:        *const fn (*anyopaque, *const FORMATETC, *STGMEDIUM, BOOL) callconv(winapi) HRESULT,
    EnumFormatEtc:  *const fn (*anyopaque, DWORD, *?*anyopaque) callconv(winapi) HRESULT,
    DAdvise:        *const fn (*anyopaque, *const FORMATETC, DWORD, *anyopaque, *DWORD) callconv(winapi) HRESULT,
    DUnadvise:      *const fn (*anyopaque, DWORD) callconv(winapi) HRESULT,
    EnumDAdvise:    *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
};

const IDataObject = extern struct { vtbl: *const IDataObjectVtbl };

// ── Win32 OLE / Shell API declarations ───────────────────────────────────────

extern "ole32" fn OleInitialize(pvReserved: ?*anyopaque) callconv(winapi) HRESULT;
extern "ole32" fn OleUninitialize() callconv(winapi) void;
extern "ole32" fn RegisterDragDrop(hwnd: HWND, pDropTarget: *anyopaque) callconv(winapi) HRESULT;
extern "ole32" fn RevokeDragDrop(hwnd: HWND) callconv(winapi) HRESULT;
extern "ole32" fn ReleaseStgMedium(pMedium: *STGMEDIUM) callconv(winapi) void;

extern "shell32" fn DragQueryFileW(
    hDrop:    usize,   // HDROP is an opaque handle (same underlying type as HGLOBAL)
    iFile:    DWORD,
    lpszFile: ?[*]u16,
    cch:      DWORD,
) callconv(winapi) DWORD;

extern "kernel32" fn GlobalLock(hMem: usize) callconv(winapi) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(hMem: usize) callconv(winapi) BOOL;
extern "kernel32" fn GlobalSize(hMem: usize) callconv(winapi) usize;

extern "user32" fn ScreenToClient(hWnd: HWND, lpPoint: *POINT) callconv(winapi) BOOL;

// ── EventQueue (type-erased push handle) ──────────────────────────────────────
//
// Cannot import window.zig (circular deps), so we use a function-pointer pair.

pub const EventQueue = struct {
    ptr:     *anyopaque,
    push_fn: *const fn (*anyopaque, Event) void,

    pub fn push(self: *EventQueue, ev: Event) void {
        self.push_fn(self.ptr, ev);
    }
};

// ── IDropTarget vtable struct ─────────────────────────────────────────────────

const IDropTargetVtbl = extern struct {
    // IUnknown
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    // IDropTarget
    DragEnter: *const fn (*anyopaque, *IDataObject, DWORD, LONG, LONG, *DWORD) callconv(winapi) HRESULT,
    DragOver:  *const fn (*anyopaque, DWORD, LONG, LONG, *DWORD) callconv(winapi) HRESULT,
    DragLeave: *const fn (*anyopaque) callconv(winapi) HRESULT,
    Drop:      *const fn (*anyopaque, *IDataObject, DWORD, LONG, LONG, *DWORD) callconv(winapi) HRESULT,
};

// ── DropTarget ────────────────────────────────────────────────────────────────

pub const DropTarget = struct {
    vtbl:        *const IDropTargetVtbl,
    ref_count:   std.atomic.Value(u32),
    hwnd:        HWND,
    alloc:       std.mem.Allocator,
    arena:       std.heap.ArenaAllocator,
    event_queue: EventQueue,
    /// Track whether a drag is currently active (for DragLeave guard).
    in_drag:     bool,

    // ── Recover self pointer from the IUnknown/IDropTarget pointer ─────────

    fn self(p: *anyopaque) *DropTarget {
        return @ptrCast(@alignCast(p));
    }

    // ── IUnknown ────────────────────────────────────────────────────────────

    fn qi(p: *anyopaque, riid: *const GUID, ppv: *?*anyopaque) callconv(winapi) HRESULT {
        const dt = self(p);
        if (guidEql(riid, &IID_IUnknown) or guidEql(riid, &IID_IDropTarget)) {
            ppv.* = p;
            _ = dt.ref_count.fetchAdd(1, .monotonic);
            return S_OK;
        }
        ppv.* = null;
        return E_NOINTERFACE;
    }

    fn addRef(p: *anyopaque) callconv(winapi) ULONG {
        return self(p).ref_count.fetchAdd(1, .monotonic) + 1;
    }

    fn release(p: *anyopaque) callconv(winapi) ULONG {
        const dt = self(p);
        const prev = dt.ref_count.fetchSub(1, .monotonic);
        if (prev == 1) {
            dt.arena.deinit();
            dt.alloc.destroy(dt);
        }
        return prev - 1;
    }

    // ── Payload extraction from IDataObject ─────────────────────────────────

    /// Extract file paths from a CF_HDROP data object. Returns a slice of
    /// UTF-8 strings allocated from the arena.
    fn extractFiles(dt: *DropTarget, data_obj: *IDataObject) []const []const u8 {
        const arena_alloc = dt.arena.allocator();
        const fe = FORMATETC{
            .cfFormat = CF_HDROP,
            .ptd      = null,
            .dwAspect = DVASPECT_CONTENT,
            .lindex   = -1,
            .tymed    = TYMED_HGLOBAL,
        };
        var medium: STGMEDIUM = std.mem.zeroes(STGMEDIUM);
        const hr = data_obj.vtbl.GetData(@ptrCast(data_obj), &fe, &medium);
        if (hr != S_OK) return &.{};
        defer ReleaseStgMedium(&medium);

        const hglobal = medium.u;
        // DragQueryFile with 0xFFFFFFFF returns the file count.
        const count = DragQueryFileW(hglobal, 0xFFFFFFFF, null, 0);
        if (count == 0) return &.{};

        const files = arena_alloc.alloc([]const u8, count) catch return &.{};
        var n: u32 = 0;
        for (0..count) |i| {
            // First call: get required buffer length (in UTF-16 code units, excl. null).
            const len = DragQueryFileW(hglobal, @intCast(i), null, 0);
            if (len == 0) continue;
            const buf = arena_alloc.alloc(u16, len + 1) catch continue;
            _ = DragQueryFileW(hglobal, @intCast(i), buf.ptr, @intCast(buf.len));
            const utf8 = std.unicode.utf16LeToUtf8Alloc(arena_alloc, buf[0..len]) catch continue;
            files[n] = utf8;
            n += 1;
        }
        return files[0..n];
    }

    /// Extract Unicode text from a CF_UNICODETEXT data object. Returns a
    /// UTF-8 string allocated from the arena, or empty string on failure.
    fn extractText(dt: *DropTarget, data_obj: *IDataObject) []const u8 {
        const arena_alloc = dt.arena.allocator();
        const fe = FORMATETC{
            .cfFormat = CF_UNICODETEXT,
            .ptd      = null,
            .dwAspect = DVASPECT_CONTENT,
            .lindex   = -1,
            .tymed    = TYMED_HGLOBAL,
        };
        var medium: STGMEDIUM = std.mem.zeroes(STGMEDIUM);
        const hr = data_obj.vtbl.GetData(@ptrCast(data_obj), &fe, &medium);
        if (hr != S_OK) return "";
        defer ReleaseStgMedium(&medium);

        const hglobal = medium.u;
        const raw = GlobalLock(hglobal) orelse return "";
        defer _ = GlobalUnlock(hglobal);

        const byte_size = GlobalSize(hglobal);
        if (byte_size < 2) return "";

        // The data is a null-terminated UTF-16LE string.
        const wptr: [*]const u16 = @ptrCast(@alignCast(raw));
        const wlen_max = byte_size / 2;
        var wlen: usize = 0;
        while (wlen < wlen_max and wptr[wlen] != 0) wlen += 1;
        if (wlen == 0) return "";

        return std.unicode.utf16LeToUtf8Alloc(arena_alloc, wptr[0..wlen]) catch "";
    }

    /// Convert screen coordinates to logical client-area coordinates.
    fn toLogical(dt: *DropTarget, x_screen: LONG, y_screen: LONG) struct { x: i32, y: i32 } {
        var pt = POINT{ .x = x_screen, .y = y_screen };
        _ = ScreenToClient(dt.hwnd, &pt);
        return .{ .x = pt.x, .y = pt.y };
    }

    // ── IDropTarget methods ──────────────────────────────────────────────────

    fn dragEnter(
        p: *anyopaque,
        data_obj: *IDataObject,
        grfKeyState: DWORD,
        x_screen: LONG,
        y_screen: LONG,
        pdwEffect: *DWORD,
    ) callconv(winapi) HRESULT {
        _ = grfKeyState;
        const dt = self(p);
        dt.in_drag = true;

        // Recycle memory from the last drag.
        _ = dt.arena.reset(.retain_capacity);

        const files = dt.extractFiles(data_obj);
        const text  = dt.extractText(data_obj);
        const pos   = dt.toLogical(x_screen, y_screen);

        const has_payload = files.len > 0 or text.len > 0;
        pdwEffect.* = if (has_payload) DROPEFFECT_COPY else DROPEFFECT_NONE;

        dt.event_queue.push(.{ .drag_enter = .{
            .files = files,
            .text  = text,
            .x     = pos.x,
            .y     = pos.y,
        }});
        return S_OK;
    }

    fn dragOver(
        p: *anyopaque,
        grfKeyState: DWORD,
        x_screen: LONG,
        y_screen: LONG,
        pdwEffect: *DWORD,
    ) callconv(winapi) HRESULT {
        _ = grfKeyState;
        const dt = self(p);
        if (!dt.in_drag) {
            pdwEffect.* = DROPEFFECT_NONE;
            return S_OK;
        }
        pdwEffect.* = DROPEFFECT_COPY;
        const pos = dt.toLogical(x_screen, y_screen);
        dt.event_queue.push(.{ .drag_over = .{ .x = pos.x, .y = pos.y }});
        return S_OK;
    }

    fn dragLeave(p: *anyopaque) callconv(winapi) HRESULT {
        const dt = self(p);
        if (dt.in_drag) {
            dt.in_drag = false;
            dt.event_queue.push(.drag_leave);
        }
        return S_OK;
    }

    fn drop(
        p: *anyopaque,
        data_obj: *IDataObject,
        grfKeyState: DWORD,
        x_screen: LONG,
        y_screen: LONG,
        pdwEffect: *DWORD,
    ) callconv(winapi) HRESULT {
        _ = grfKeyState;
        const dt = self(p);
        dt.in_drag = false;

        // Re-parse from the data object at the final coordinates.
        _ = dt.arena.reset(.retain_capacity);

        const files = dt.extractFiles(data_obj);
        const text  = dt.extractText(data_obj);
        const pos   = dt.toLogical(x_screen, y_screen);

        const has_payload = files.len > 0 or text.len > 0;
        pdwEffect.* = if (has_payload) DROPEFFECT_COPY else DROPEFFECT_NONE;

        dt.event_queue.push(.{ .drop = .{
            .files = files,
            .text  = text,
            .x     = pos.x,
            .y     = pos.y,
        }});
        return S_OK;
    }

    // ── Static vtable instance ───────────────────────────────────────────────

    const s_vtbl = IDropTargetVtbl{
        .QueryInterface = qi,
        .AddRef         = addRef,
        .Release        = release,
        .DragEnter      = dragEnter,
        .DragOver       = dragOver,
        .DragLeave      = dragLeave,
        .Drop           = drop,
    };

    // ── Public lifecycle ─────────────────────────────────────────────────────

    /// Create a new DropTarget, initialise OLE on this thread, and register it
    /// with the given window handle. Returns an error if OLE init or
    /// RegisterDragDrop fails; in that case no cleanup is needed by the caller.
    ///
    /// The DropTarget holds a COM reference count of 1 on behalf of the caller.
    /// Call `destroy()` to revoke and release.
    pub fn create(
        alloc:       std.mem.Allocator,
        hwnd:        HWND,
        event_queue: EventQueue,
    ) !*DropTarget {
        const hr_init = OleInitialize(null);
        // S_OK (0) = freshly initialized; S_FALSE (1) = already initialized.
        if (hr_init != 0 and hr_init != 1) return error.OleInitFailed;

        const dt = try alloc.create(DropTarget);
        dt.* = .{
            .vtbl        = &s_vtbl,
            .ref_count   = .init(1),
            .hwnd        = hwnd,
            .alloc       = alloc,
            .arena       = std.heap.ArenaAllocator.init(alloc),
            .event_queue = event_queue,
            .in_drag     = false,
        };

        const hr_reg = RegisterDragDrop(hwnd, @ptrCast(dt));
        if (hr_reg != S_OK) {
            dt.arena.deinit();
            alloc.destroy(dt);
            OleUninitialize();
            return error.RegisterDragDropFailed;
        }

        return dt;
    }

    /// Revoke the drop target registration and release the COM reference.
    /// After this call `dt` is invalid and must not be used.
    pub fn destroy(dt: *DropTarget) void {
        const hwnd = dt.hwnd;
        _ = RevokeDragDrop(hwnd);
        // release() handles arena.deinit() + alloc.destroy() when count reaches 0.
        _ = release(@ptrCast(dt));
        OleUninitialize();
    }
};
